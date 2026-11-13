// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What an item has to supply for its transcript to reach a file on disk.

 A session's console and a conversation keep the same log; they differ only in
 whether logging applies to them at all, which file their lines go to, and how
 the begin-and-end banner is written. Both conformances are at the end of this
 file: there are only two of them, and reading them beside the protocol is what
 shows how small the difference between the two logs is. */
protocol TranscriptFileLogOwner: AnyObject {
	/// This item's transcript file, and whether a session is open in it.
	var transcriptLog: TranscriptFileLog { get }
	/// Whether this item's lines are written to disk at all.
	var fileLoggingIsEnabled: Bool { get }
	/// A logger addressed at this item's transcript file.
	func makeFileLogger() -> FileLogger
	/// Writes the banner that opens or closes a logging session for this item.
	func recordFileLogSessionChange(_ startsSession: Bool)
}

/** One item's transcript file.

 The file is opened by the first line written to it, not by the item coming into
 existence: a session that logs nothing leaves nothing behind. */
final class TranscriptFileLog {
	/** The open transcript file, `nil` until a line is written to it. A test
	 installs a logger of its own so it can read the destination back. */
	var logger: FileLogger?

	/** Whether a logging session banner has been written and not yet closed. A line
	 counter cannot express this: writing the banner is itself a write. */
	private(set) var sessionIsOpen = false

	/// Picks the file back up after the transcript folder moved, or lets it go
	/// when logging has been switched off since the last write.
	func reopenIfNeeded(for owner: some TranscriptFileLogOwner) {
		if owner.fileLoggingIsEnabled {
			logger?.reopenIfNeeded()
		} else {
			close(for: owner)
		}
	}

	func close(for owner: some TranscriptFileLogOwner) {
		endSession(for: owner)
		logger?.close()
		// The shared file-command stream retains the pending banner and close.
		logger = nil
	}

	func write(_ chatLine: ChatLine, for owner: some TranscriptFileLogOwner) {
		guard owner.fileLoggingIsEnabled else {
			return
		}

		beginSession(for: owner)
		openedLogger(for: owner).writeChatLine(chatLine)
	}

	/// Opening a session is the first write's own business: nothing outside asks
	/// for a banner without a line to put under it.
	private func beginSession(for owner: some TranscriptFileLogOwner) {
		guard sessionIsOpen == false else { return }

		/* Set before writing: the banner itself goes through write(_:for:). */
		sessionIsOpen = true
		owner.recordFileLogSessionChange(true)
	}

	func endSession(for owner: some TranscriptFileLogOwner) {
		guard sessionIsOpen else { return }

		owner.recordFileLogSessionChange(false)
		sessionIsOpen = false
	}

	/** The session banner is written through `write(_:for:)`, which opens the
	 session, which writes the banner: the optimizer inlines that cycle, and a
	 lazy assignment left inside the read of the same property made it produce
	 SIL its own verifier rejects (Xcode 27 beta 6). Resolving the logger into a
	 local first keeps the read and the write apart. */
	private func openedLogger(for owner: some TranscriptFileLogOwner) -> FileLogger {
		if let logger {
			return logger
		}
		let opened = owner.makeFileLogger()
		logger = opened
		return opened
	}
}

/// The spelling every caller uses, so an item's own file reads the same whether
/// it is a console or a conversation.
extension TranscriptFileLogOwner {
	/// Whether a logging session banner has been written and not yet closed.
	var logFileSessionIsOpen: Bool {
		transcriptLog.sessionIsOpen
	}

	func reopenLogFileIfNeeded() {
		transcriptLog.reopenIfNeeded(for: self)
	}

	func closeLogFile() {
		transcriptLog.close(for: self)
	}

	func writeToLogFile(_ chatLine: ChatLine) {
		transcriptLog.write(chatLine, for: self)
	}

	func endLogFileSession() {
		transcriptLog.endSession(for: self)
	}
}

extension ServerSession: TranscriptFileLogOwner {
	var fileLoggingIsEnabled: Bool {
		environment.settings.logToDiskIsEnabled
	}

	func makeFileLogger() -> FileLogger {
		FileLogger(session: self)
	}

	func recordFileLogSessionChange(_ startsSession: Bool) {
		logFileRecordSessionChanged(startsSession, in: nil)
	}

	/// Writes the banner that opens or closes a logging session, into this
	/// session's console or into one of its conversations.
	func logFileRecordSessionChanged(_ startsSession: Bool, in conversation: Conversation?) {
		precondition(conversation?.isConsole != true)
		let message = startsSession
			? String(localized: .IRC.beginSession)
			: String(localized: .IRC.endSession)

		for body in [" ", message, " "] {
			var line = ChatLine()
			line.messageBody = body
			if let conversation {
				conversation.writeToLogFile(line)
			} else {
				writeToLogFile(line)
			}
		}
	}

	/// Closes the session in every transcript this session writes, its own last:
	/// the conversation banners are lines this session is still able to write.
	func endLoggingSessions() {
		for conversation in conversationList where conversation.isConsole == false {
			conversation.endLogFileSession()
		}
		endLogFileSession()
	}
}

extension Conversation: TranscriptFileLogOwner {
	/// A console view is the session's own scratch transcript, which is never
	/// written to disk however the setting stands.
	var fileLoggingIsEnabled: Bool {
		isConsole == false && chatSettings.logToDiskIsEnabled
	}

	func makeFileLogger() -> FileLogger {
		FileLogger(conversation: self)
	}

	func recordFileLogSessionChange(_ startsSession: Bool) {
		associatedSession?.logFileRecordSessionChanged(startsSession, in: self)
	}
}
