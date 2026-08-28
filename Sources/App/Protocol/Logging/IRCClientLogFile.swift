/* *********************************************************************
  *                  _____         _               _
  *                 |_   _|____  _| |_ _   _  __ _| |
  *                   | |/ _ \\ \/ / __| | | |/ _` | |
  *                   | |  __/>  <| |_| |_| | (_| | |
  *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
  *
  * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
  * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
  *       Please see Acknowledgements.pdf for additional information.
 + *
  * Redistribution and use in source and binary forms, with or without
  * modification, are permitted provided that the following conditions
  * are met:
  *
  *  * Redistributions of source code must retain the above copyright
  *    notice, this list of conditions and the following disclaimer.
  *  * Redistributions in binary form must reproduce the above copyright
  *    notice, this list of conditions and the following disclaimer in the
  *    documentation and/or other materials provided with the distribution.
  *  * Neither the name of Textual, "Codeux Software, LLC", nor the
  *    names of its contributors may be used to endorse or promote products
  *    derived from this software without specific prior written permission.
  *
  * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
  * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
  * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
  * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
  * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
  * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
  * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
  * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
  * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
  * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
  * SUCH DAMAGE.
  *
  *********************************************************************** */

import Foundation

public extension IRCClient {
	@objc(reopenLogFileIfNeeded)
	func reopenLogFileIfNeeded() {
		if environment.preferences.logToDiskIsEnabled {
			logFile?.reopenIfNeeded()
		} else {
			closeClientLogFile()
		}
	}

	@objc(closeLogFile)
	func closeLogFile() {
		closeClientLogFile()
	}

	@objc(writeToLogLineToLogFile:)
	func writeToLogFile(_ logLine: LogLine) {
		writeClientLogLine(logLine)
	}

	@objc(logFileRecordSessionChanged:inChannel:)
	func logFileRecordSessionChanged(_ startsSession: Bool, in channel: IRCChannel?) {
		recordLogSessionChange(startsSession, in: channel)
	}

	@objc(endLoggingSessions)
	func endLoggingSessions() {
		for channel in channelList where channel.isUtility == false {
			channel.logFileWriteSessionEnd()
		}
		finishClientLogSession()
	}

	@objc(logFileWriteSessionBegin)
	func logFileWriteSessionBegin() {
		beginClientLogSession()
	}

	@objc(logFileWriteSessionEnd)
	func logFileWriteSessionEnd() {
		finishClientLogSession()
	}

	@MainActor
	private func closeClientLogFile() {
		logFile?.close()
		/* Leaving the handle in place made the lazy re-creation below unreachable, so
		 every later write went to a closed logger. */
		logFile = nil
	}

	@MainActor
	private func writeClientLogLine(_ logLine: LogLine) {
		guard environment.preferences.logToDiskIsEnabled else { return }

		beginClientLogSession()

		if logFile == nil {
			logFile = FileLogger(client: self)
		}
		logFile?.writeLogLine(logLine)
	}

	@MainActor
	private func recordLogSessionChange(_ startsSession: Bool, in channel: IRCChannel?) {
		precondition(channel?.isUtility != true)
		let message = IRCLogStrings.sessionMarker(startsSession: startsSession)

		for body in [" ", message, " "] {
			let line = LogLine()
			line.messageBody = body
			if let channel {
				channel.writeToLogFile(line)
			} else {
				writeClientLogLine(line)
			}
		}
	}

	@MainActor
	private func beginClientLogSession() {
		guard logFileSessionIsOpen == false else { return }

		/* Set before writing: the banner itself goes through writeClientLogLine. */
		logFileSessionIsOpen = true
		recordLogSessionChange(true, in: nil)
	}

	@MainActor
	private func finishClientLogSession() {
		guard logFileSessionIsOpen else { return }

		recordLogSessionChange(false, in: nil)
		logFileSessionIsOpen = false
	}
}
