// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Synchronous acceptance only. The shared FIFO outlives individual loggers,
/// including a close followed immediately by a new logger for the same file.
@MainActor
final class FileLogger {
	/// Whether the application is shutting down, which is when a logging failure
	/// is no longer worth interrupting anyone over.
	private(set) static var isTerminating = false

	private let identifier = UUID()
	private let commands: FileLogCommands
	private let fixedDestination: FileLogDestination?
	private weak var session: ServerSession?
	private weak var conversation: Conversation?

	convenience init(session: ServerSession) {
		self.init(session: session, commands: .shared)
	}

	init(conversation: Conversation) {
		session = conversation.associatedSession
		self.conversation = conversation
		commands = .shared
		fixedDestination = nil
	}

	init(session: ServerSession, commands: FileLogCommands, destination: FileLogDestination? = nil) {
		self.session = session
		self.commands = commands
		fixedDestination = destination
	}

	isolated deinit {
		commands.submit(.close(identifier))
	}

	func writeChatLine(_ chatLine: ChatLine) {
		let body = if let conversation {
			chatLine.renderedBodyForTranscriptLog(in: conversation)
		} else {
			chatLine.renderedBodyForTranscriptLog
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
		let bookmark = SettingsKeys.Logging.transcriptFolderBookmark.value
		guard !bookmark.isEmpty else { return nil }
		let item: ChatItem? = if let conversation {
			conversation
		} else {
			session
		}
		guard let item, let relativePath = TranscriptPath.relative(for: item) else { return nil }
		return FileLogDestination(folder: .bookmark(bookmark), relativePath: relativePath)
	}

	/// Seals acceptance synchronously, then synchronizes and closes every file.
	/// The application's existing termination deadline bounds this callback.
	static func prepareForApplicationTermination(completion: @escaping @MainActor @Sendable (Bool) -> Void) {
		isTerminating = true
		FileLogCommands.shared.finish(completion: completion)
	}
}
