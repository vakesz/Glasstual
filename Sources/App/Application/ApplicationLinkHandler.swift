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

nonisolated enum ApplicationLink: Equatable { // nonisolated: value
	case connect(ConnectionIntent)
	case applicationAction(name: String, source: String)

	struct ConnectionIntent: Equatable, Sendable {
		let serverInfo: String
		let channelList: String?
	}

	/// Parses the application-owned `glasstual:`, `irc:`, and `ircs:` schemes.
	static func parse(_ location: String) -> Self? { // nonisolated: pure
		guard location.isEmpty == false else { return nil }

		let locationValue = (location.removingPercentEncoding ?? location)
			.trimmingCharacters(in: .whitespacesAndNewlines)
		let slashCount = locationValue.reduce(into: 0) { count, character in
			if character == "/" {
				count += 1
			}
		}

		guard (2 ... 3).contains(slashCount) else { return nil }

		var serverInfo = locationValue
		var channelInfo: String?
		if slashCount == 3, let separator = locationValue.lastIndex(of: "/") {
			serverInfo = String(locationValue[..<separator])
			channelInfo = String(locationValue[locationValue.index(after: separator)...])
		}

		guard let baseURL = URL(string: serverInfo),
		      let scheme = baseURL.scheme?.lowercased(),
		      let host = baseURL.host
		else {
			return nil
		}

		if scheme == "glasstual" {
			return .applicationAction(name: host, source: locationValue)
		}
		guard scheme == "irc" || scheme == "ircs" else { return nil }
		guard let port = UInt16(exactly: baseURL.port ?? Int(IRCConnectionDefaults.serverPort)) else {
			return nil
		}

		var connectSecurely = (scheme == "ircs")
		var channels: [String] = []
		if let channelInfo {
			var sections = channelInfo.components(separatedBy: ",").filter { $0.isEmpty == false }
			if let last = sections.last, last.caseInsensitiveCompare("needssl") == .orderedSame {
				connectSecurely = true
				sections.removeLast()
			}

			channels = sections.prefix(5).map { section in
				(section as NSString).hasPrefix("#") ? section : "#\(section)"
			}
		}

		let prefix = connectSecurely ? "-SSL " : ""
		return .connect(ConnectionIntent(
			serverInfo: "\(prefix)\(host):\(port)",
			channelList: channels.isEmpty ? nil : channels.joined(separator: ",")
		))
	}

	static func connectionIntent(for location: String) -> ConnectionIntent? { // nonisolated: pure
		guard case let .connect(intent) = parse(location) else { return nil }
		return intent
	}
}

@MainActor
enum ApplicationLinkHandler {
	private enum Action: String {
		case acknowledgements
		case applicationSupportFolder = "application-support-folder"
		case contributors
		case customScriptsFolder = "custom-scripts-folder"
		case unsupervisedScriptFolder = "unsupervised-script-folder"
		case unsupervisedScriptsFolder = "unsupervised-scripts-folder"
		case diagnosticReportsFolder = "diagnostic-reports-folder"
		case goto
		case supportChannel = "support-channel"
		case testingChannel = "testing-channel"
	}

	static func open(_ location: String) {
		switch ApplicationLink.parse(location) {
		case let .applicationAction(name, source):
			perform(name, source: source)
		case let .connect(intent):
			ServerConnectionCoordinator.connect(
				to: intent.serverInfo,
				channels: intent.channelList,
				options: ServerConnectionOptions(
					connectWhenCreated: false,
					mergeConnectionIfPossible: true,
					selectFirstChannelAdded: false
				)
			)
		case nil:
			break
		}
	}

	private static func perform(_ actionName: String, source: String) {
		guard let action = Action(rawValue: actionName) else { return }
		let menu = ClientEnvironment.shared.menu

		switch action {
		case .acknowledgements, .contributors:
			menu?.openAcknowledgements(nil)
		case .applicationSupportFolder:
			reveal(PathInfo.groupContainerApplicationSupportURL, with: menu)
		case .customScriptsFolder, .unsupervisedScriptFolder, .unsupervisedScriptsFolder:
			reveal(SharedApplication.sharedPluginManager().customScriptsURL, with: menu)
		case .diagnosticReportsFolder:
			reveal(PathInfo.userDiagnosticReportsURL, with: menu)
			reveal(PathInfo.systemDiagnosticReportsURL, with: menu)
		case .goto:
			guard let url = URL(string: source) else { return }
			menu?.navigateToTreeItem(at: url)
		case .supportChannel:
			menu?.connectToGlasstualHelpChannel(nil)
		case .testingChannel:
			menu?.connectToGlasstualTestingChannel(nil)
		}
	}

	private static func reveal(_ url: URL?, with menu: (any ClientMenuPresenting)?) {
		guard let url else { return }
		menu?.revealInFinder(url)
	}
}
