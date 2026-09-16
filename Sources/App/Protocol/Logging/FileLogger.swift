/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions

enum TranscriptDirectory {
	static let console = "Console"
	static let channel = "Channels"
	static let privateMessage = "Queries"
}

/// Synchronous acceptance only. The shared FIFO outlives individual loggers,
/// including a close followed immediately by a new logger for the same file.
@MainActor
final class FileLogger {
	private static let commands = FileLogCommands()
	private static var noSpaceAlert = FileLogAlertThrottle()
	private static var terminating = false

	private let identifier = UUID()
	private let commands: FileLogCommands
	private let fixedDestination: FileLogDestination?
	private weak var client: Client?
	private weak var channel: Channel?

	convenience init(client: Client) {
		self.init(client: client, commands: Self.commands)
	}

	init(channel: Channel) {
		client = channel.associatedClient
		self.channel = channel
		commands = Self.commands
		fixedDestination = nil
	}

	init(client: Client, commands: FileLogCommands, destination: FileLogDestination? = nil) {
		self.client = client
		self.commands = commands
		fixedDestination = destination
	}

	isolated deinit {
		commands.submit(.close(identifier))
	}

	func writeLogLine(_ logLine: LogLine) {
		let body = if let channel {
			logLine.renderedBodyForTranscriptLog(in: channel)
		} else {
			logLine.renderedBodyForTranscriptLog
		}
		writePlainText(body)
	}

	func writePlainText(_ string: String) {
		guard let destination else { return }
		commands.submit(.write(identifier, destination, Date(), string))
	}

	func close() {
		commands.submit(.close(identifier))
	}

	func reopenIfNeeded() {
		commands.submit(.reopen(identifier, destination, Date()))
	}

	private var destination: FileLogDestination? {
		if let fixedDestination {
			return fixedDestination
		}
		let bookmark = Preferences.Logging.transcriptFolderBookmark.value
		guard !bookmark.isEmpty else { return nil }
		let item: ChatItem? = if let channel {
			channel
		} else {
			client
		}
		guard let item, let relativePath = Self.relativeTranscriptPath(for: item) else { return nil }
		return FileLogDestination(folder: .bookmark(bookmark), relativePath: relativePath)
	}

	/// Seals acceptance synchronously, then synchronizes and closes every file.
	/// The application's existing termination deadline bounds this callback.
	static func prepareForApplicationTermination(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
		terminating = true
		commands.finish(completion: completion)
	}

	static func writePath(for item: ChatItem) -> String? {
		guard let sourcePath = PathInfo.transcriptFolder else { return nil }
		return writePath(for: item, relativeTo: sourcePath)
	}

	static func writePath(for item: ChatItem, relativeTo sourcePath: String) -> String? {
		guard let relativePath = relativeTranscriptPath(for: item) else { return nil }
		return (sourcePath as NSString).appendingPathComponent(relativePath)
	}

	private static func relativeTranscriptPath(for item: ChatItem) -> String? {
		let channel = item.associatedChannel
		if let channel, channel.isUtility {
			return nil
		}
		guard let client = item.associatedClient else { return nil }

		let clientIdentifier = String(client.uniqueIdentifier.prefix(5))
		let clientName = "\(client.name) (\(clientIdentifier))".safeFilename
		guard let channel else {
			return "/\(clientName)/\(TranscriptDirectory.console)/"
		}
		let channelName = channel.name.safeFilename
		if channel.isChannel {
			return "/\(clientName)/\(TranscriptDirectory.channel)/\(channelName)/"
		}
		if channel.isPrivateMessage || channel.isDirectChat {
			return "/\(clientName)/\(TranscriptDirectory.privateMessage)/\(channelName)/"
		}
		return nil
	}

	static func reportNoSpace(at now: Date = Date()) {
		guard !terminating, noSpaceAlert.begin(at: now) else { return }
		Alerts.alert(
			withMessage: PromptStrings.Logging.resumeAfterLowStorageBody,
			title: PromptStrings.Logging.disabledForLowStorageTitle,
			defaultButton: PromptStrings.Action.confirmation
		) { _ in
			noSpaceAlert.dismiss()
		}
	}
}

nonisolated struct FileLogAlertThrottle { // nonisolated: value
	private var visible = false
	private var lastAlert: Date?

	mutating func begin(at now: Date) -> Bool {
		guard !visible else { return false }
		if let lastAlert, now.timeIntervalSince(lastAlert) < 300 {
			return false
		}
		lastAlert = now
		visible = true
		return true
	}

	mutating func dismiss() {
		visible = false
	}
}
