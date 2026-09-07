/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

private nonisolated let applicationLinkLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "ApplicationLink"
)

nonisolated enum ApplicationLink: Equatable { // nonisolated: value
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

		init(name: String) {
			switch name.lowercased() {
			case "acknowledgements", "contributors": self = .acknowledgements
			case "application-support-folder": self = .applicationSupportFolder
			case "custom-scripts-folder", "unsupervised-script-folder", "unsupervised-scripts-folder":
				self = .customScriptsFolder
			case "diagnostic-reports-folder": self = .diagnosticReportsFolder
			case "goto": self = .goto
			case "support-channel": self = .supportChannel
			case "testing-channel": self = .testingChannel
			default: self = .unknown(name)
			}
		}
	}

	/// Parses the application-owned `glasstual:`, `textual:`, `irc:` and
	/// `ircs:` schemes. All four are registered in the application's URL types.
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

		if scheme == "glasstual" || scheme == "textual" {
			guard let url = components.url else { return nil }
			return .applicationAction(Action(name: host), source: url)
		}
		guard scheme == "irc" || scheme == "ircs", components.query == nil else { return nil }
		if host.hasPrefix("["), host.hasSuffix("]") {
			host = String(host.dropFirst().dropLast())
		}
		guard (host as NSString).isValidInternetAddress,
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
			? IRCConnectionDefaults.serverPortSecure
			: IRCConnectionDefaults.serverPort
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

@MainActor
enum ApplicationLinkHandler {
	static func open(_ location: String) {
		switch ApplicationLink.parse(location) {
		case let .applicationAction(action, source):
			perform(action, source: source)
		case let .connect(intent):
			ServerConnectionCoordinator.connect(using: intent)
		case nil:
			break
		}
	}

	private static func perform(_ action: ApplicationLink.Action, source: URL) {
		let menu = ClientEnvironment.shared.menu

		switch action {
		case .acknowledgements:
			menu?.openAcknowledgements(nil)
		case .applicationSupportFolder:
			reveal(PathInfo.groupContainerApplicationSupportURL, with: menu)
		case .customScriptsFolder:
			reveal(SharedApplication.sharedPluginManager().customScriptsURL, with: menu)
		case .diagnosticReportsFolder:
			reveal(PathInfo.userDiagnosticReportsURL, with: menu)
			reveal(PathInfo.systemDiagnosticReportsURL, with: menu)
		case .goto:
			menu?.navigateToTreeItem(at: source)
		case .supportChannel:
			menu?.connectToGlasstualHelpChannel(nil)
		case .testingChannel:
			menu?.connectToGlasstualTestingChannel(nil)
		case let .unknown(name):
			/* A link naming something this build does not have. Say which,
			 rather than dropping it silently. */
			applicationLinkLogger.info("Ignoring an unknown application link action: \(name, privacy: .public)")
		}
	}

	private static func reveal(_ url: URL?, with menu: (any ClientMenuPresenting)?) {
		guard let url else { return }
		menu?.revealInFinder(url)
	}
}
