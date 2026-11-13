// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private nonisolated let applicationLinkLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ApplicationLink"
)

nonisolated enum ApplicationLink: Equatable {
	case connect(ServerConnectionRequest)
	case applicationAction(Action, source: URL)

	enum Action: Equatable, Sendable {
		case acknowledgements
		case applicationSupportFolder
		case customScriptsFolder
		case diagnosticReportsFolder
		case goto
		case supportChannel
		case testingChannel
		case unknown(String)

		/// Whether following the link reveals something on disk or connects to a
		/// server, which a link written by someone else must not do unasked.
		var requiresConfirmation: Bool {
			switch self {
			case .applicationSupportFolder, .customScriptsFolder, .diagnosticReportsFolder,
			     .supportChannel, .testingChannel:
				true
			case .acknowledgements, .goto, .unknown:
				false
			}
		}

		init(name: String) {
			switch name.lowercased() {
			case "acknowledgements", "contributors": self = .acknowledgements
			case "application-support-folder": self = .applicationSupportFolder
			case "custom-scripts-folder": self = .customScriptsFolder
			case "diagnostic-reports-folder": self = .diagnosticReportsFolder
			case "goto": self = .goto
			case "support-channel": self = .supportChannel
			case "testing-channel": self = .testingChannel
			default: self = .unknown(name)
			}
		}
	}

	/// The link that selects a conversation or server by its identifier, which
	/// `goto` resolves against the sidebar's rows. `nil` for an identifier that
	/// cannot sit in a URL path.
	static func conversationLink(identifier: String) -> String? { // nonisolated: pure
		guard let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
		      encoded.isEmpty == false, encoded.contains("/") == false
		else { return nil }
		return "glasstual://goto/" + encoded
	}

	/// Whether a `glasstual:` link a conversation shows has to be confirmed
	/// before it is followed. A link that does not parse only logs, so it opens
	/// as any other would.
	static func requiresConfirmation(_ url: URL) -> Bool { // nonisolated: pure
		guard case let .applicationAction(action, _) = parse(url.absoluteString) else { return false }
		return action.requiresConfirmation
	}

	/// Parses the application-owned `glasstual:`, `irc:` and `ircs:` schemes.
	/// All three are registered in the application's URL types.
	static func parse(_ location: String) -> Self? { // nonisolated: pure
		guard location.isEmpty == false,
		      location.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
		      let components = URLComponents(string: location, encodingInvalidCharacters: false),
		      let scheme = components.scheme?.lowercased(),
		      let encodedHost = components.percentEncodedHost,
		      var host = encodedHost.removingPercentEncoding,
		      host.isEmpty == false,
		      components.user == nil, components.password == nil
		else {
			return nil
		}

		if scheme == "glasstual" {
			guard let url = components.url else { return nil }
			return .applicationAction(Action(name: host), source: url)
		}
		guard scheme == "irc" || scheme == "ircs", components.query == nil else { return nil }
		if host.hasPrefix("["), host.hasSuffix("]") {
			host = String(host.dropFirst().dropLast())
		}
		guard host.isValidInternetAddress,
		      host.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil
		else { return nil }

		var connectSecurely = (scheme == "ircs")
		let path = components.percentEncodedPath
		guard path.isEmpty || (path.hasPrefix("/") && path.dropFirst().contains("/") == false) else { return nil }
		let channelText: String
		if let fragment = components.percentEncodedFragment {
			guard path.isEmpty || path == "/" else { return nil }
			channelText = "#" + fragment
		} else {
			channelText = String(path.dropFirst())
		}
		var sections: [String] = []
		for encoded in channelText.split(separator: ",", omittingEmptySubsequences: false) {
			guard let decoded = String(encoded).removingPercentEncoding else { return nil }
			sections.append(decoded)
		}
		if sections.last?.lowercased() == "needssl" {
			connectSecurely = true
			sections.removeLast()
		}
		var channels: [String] = []
		for section in sections where section.isEmpty == false {
			guard section.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
			      section.contains(",") == false, section.contains(":") == false
			else { return nil }
			let channel = section.first.map { "#&+!".contains($0) } == true ? section : "#\(section)"
			guard channel.count > 1 else { return nil }
			if channels.contains(where: { $0.caseInsensitiveCompare(channel) == .orderedSame }) == false {
				channels.append(channel)
			}
		}
		let defaultPort = connectSecurely
			? ConnectionDefaults.serverPortSecure
			: ConnectionDefaults.serverPort
		guard let port = UInt16(exactly: components.port ?? Int(defaultPort)), port > 0 else {
			return nil
		}
		return .connect(ServerConnectionRequest(
			serverAddress: host.lowercased(),
			serverPort: port,
			serverPassword: nil,
			connectSecurely: connectSecurely,
			channels: Array(channels.prefix(5)),
			options: .externalLink
		))
	}
}

/** Follows the links the application owns, from wherever they come.

 Every `glasstual:` link passes through here: from another application through
 the URL event, from a transcript after `NSWorkspace` hands it back, and from
 Spotlight and Shortcuts. An action that reveals something on disk or connects
 to a server is therefore confirmed here, once, whatever opened it. */
@MainActor
enum ApplicationLinkHandler {
	/// What a link does once it may run.
	typealias Performer = @MainActor (ApplicationLink.Action, URL) -> Void

	/// The confirmation on screen, if any. A newer link that needs one replaces
	/// it, so a burst of links from another application asks once.
	private static var pendingConfirmation: Task<Void, Never>?

	/// Follows `location`. The task it returns, when there is one, is the
	/// confirmation the link waits on.
	@discardableResult
	static func open(
		_ location: String,
		prompts: any PromptPresenting = AppServices.prompts,
		perform: @escaping Performer = performAction
	) -> Task<Void, Never>? {
		guard ChatServices.shared.applicationState?.applicationIsTerminating != true else { return nil }
		switch ApplicationLink.parse(location) {
		case let .applicationAction(action, source):
			guard action.requiresConfirmation else {
				perform(action, source)
				return nil
			}
			return confirm(action, source: source, prompts: prompts, perform: perform)
		case let .connect(intent):
			ServerConnection.connect(using: intent)
		case nil:
			/* A link the application was handed and could not read. It is not
			 the reader's mistake to answer for, but dropping it without a
			 word leaves nothing to diagnose it with. */
			applicationLinkLogger.info("Ignoring a malformed application link")
		}
		return nil
	}

	/// Asks with the question a transcript link gets, and performs `action`
	/// only on Open. Cancel is the default answer, and there is no "do not ask
	/// again" for these links.
	private static func confirm(
		_ action: ApplicationLink.Action,
		source: URL,
		prompts: any PromptPresenting,
		perform: @escaping Performer
	) -> Task<Void, Never> {
		pendingConfirmation?.cancel()
		let request = TranscriptCommands.openLinkRequest(for: source)
		/* A link from another application is about no conversation: the
		 question appears wherever the reader is, and Open has to be spelled
		 out there. Cancelling the task for a newer link withdraws it. */
		let task = Task {
			guard !Task.isCancelled else { return }
			let answer = await prompts.ask(request, about: .application)
			guard !Task.isCancelled, answer.response == .alternate else { return }
			perform(action, source)
		}
		pendingConfirmation = task
		return task
	}

	/// Opens what a Spotlight result names: the identifier the index was given.
	static func openIndexedItem(identifier: String) {
		guard let link = ApplicationLink.conversationLink(identifier: identifier) else { return }
		open(link)
	}

	private static func performAction(_ action: ApplicationLink.Action, source: URL) {
		let menu = ChatServices.shared.menu

		switch action {
		case .acknowledgements:
			menu?.openAcknowledgements(nil)
		case .applicationSupportFolder:
			reveal(ApplicationPaths.groupContainerApplicationSupportURL, with: menu)
		case .customScriptsFolder:
			reveal(AppServices.scripts.customScriptsURL, with: menu)
		case .diagnosticReportsFolder:
			reveal(ApplicationPaths.userDiagnosticReportsURL, with: menu)
			reveal(ApplicationPaths.systemDiagnosticReportsURL, with: menu)
		case .goto:
			menu?.navigate(to: source)
		case .supportChannel:
			ServerConnection.connect(to: .help)
		case .testingChannel:
			ServerConnection.connect(to: .testing)
		case let .unknown(name):
			/* A link naming something this build does not have. Say which,
			 rather than dropping it silently. */
			applicationLinkLogger.info("Ignoring an unknown application link action: \(name, privacy: .public)")
		}
	}

	private static func reveal(_ url: URL?, with menu: (any MenuPresenting)?) {
		guard let url else { return }
		menu?.revealInFinder(url)
	}
}
