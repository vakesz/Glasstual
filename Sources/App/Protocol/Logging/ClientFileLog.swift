// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension Client {
	func reopenLogFileIfNeeded() {
		if environment.preferences.logToDiskIsEnabled {
			logFile?.reopenIfNeeded()
		} else {
			closeLogFile()
		}
	}

	func closeLogFile() {
		endLogSession()
		logFile?.close()
		// The shared file-command stream retains the pending banner and close.
		logFile = nil
	}

	func writeToLogFile(_ logLine: LogLine) {
		guard environment.preferences.logToDiskIsEnabled else { return }

		beginLogSession()
		openedLogFile().writeLogLine(logLine)
	}

	/// Same shape as `Channel.openedLogFile()`, for the same compiler reason.
	private func openedLogFile() -> FileLogger {
		if let logFile {
			return logFile
		}
		let opened = FileLogger(client: self)
		logFile = opened
		return opened
	}

	func logFileRecordSessionChanged(_ startsSession: Bool, in channel: Channel?) {
		precondition(channel?.isUtility != true)
		let message = startsSession
			? String(localized: .IRC.beginSession)
			: String(localized: .IRC.endSession)

		for body in [" ", message, " "] {
			var line = LogLine()
			line.messageBody = body
			if let channel {
				channel.writeToLogFile(line)
			} else {
				writeToLogFile(line)
			}
		}
	}

	func endLoggingSessions() {
		for channel in channelList where channel.isUtility == false {
			channel.logFileWriteSessionEnd()
		}
		endLogSession()
	}

	private func beginLogSession() {
		guard logFileSessionIsOpen == false else { return }

		/* Set before writing: the banner itself goes through writeToLogFile. */
		logFileSessionIsOpen = true
		logFileRecordSessionChanged(true, in: nil)
	}

	private func endLogSession() {
		guard logFileSessionIsOpen else { return }

		logFileRecordSessionChanged(false, in: nil)
		logFileSessionIsOpen = false
	}
}
