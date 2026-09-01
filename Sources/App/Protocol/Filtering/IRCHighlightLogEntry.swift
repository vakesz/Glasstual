/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
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

// AppKit: the highlight's attributed text is built with a system font.
import AppKit
import CocoaExtensions
import os

private let highlightLogEntryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCHighlightLogEntry"
)

/** An entry in a client's in-memory highlight log.

 A value, owned by the client that logged it (`IRCClient.cachedHighlights`) and
 read by `ServerHighlightListSheet`, which sorts and draws the entries itself
 rather than binding an `NSArrayController` to them by KVC key path.

 Its identity is the line it logged: `lineNumber` names one printed line. */
public struct HighlightLogEntry: Codable, Hashable, Sendable {
	public var lineLogged: LogLine
	public var clientId: String
	public var channelId: String

	public init(lineLogged: LogLine, clientId: String, channelId: String) {
		self.lineLogged = lineLogged
		self.clientId = clientId
		self.channelId = channelId

		// An incomplete entry used to abort the app from a health check; it is
		// only logged now, and callers that care check `isWellFormed`.
		if isWellFormed == false {
			highlightLogEntryLogger.error("Created an incomplete highlight log entry")
		}
	}

	/// `true` when the entry carries everything its accessors need.
	public var isWellFormed: Bool {
		clientId.isEmpty == false && channelId.isEmpty == false
	}

	public var timeLogged: Date {
		lineLogged.receivedAt
	}

	public var lineNumber: String {
		lineLogged.uniqueIdentifier
	}

	@MainActor public var channel: IRCChannel? {
		ClientEnvironment.shared.world?.findChannel(
			withId: channelId,
			onClientWithId: clientId
		)
	}

	@MainActor public var channelName: String {
		channel?.name ?? ApplicationStrings.unknownValue
	}

	public var timeLoggedFormatted: String {
		let timeInterval = lineLogged.receivedAt.timeIntervalSinceNow
		let formattedTimeInterval = humanReadableTimeInterval(timeInterval, true, 0) as String? ?? ""

		return ApplicationStrings.relativeTime(formattedTimeInterval)
	}

	@MainActor public var renderedMessage: NSAttributedString {
		let logLine = lineLogged
		let channel = channel

		let formatted = if logLine.lineType == .action {
			NotificationStrings.actionBody(
				nickname: logLine.nickname ?? "",
				text: logLine.messageBody
			)
		} else {
			NotificationStrings.messageBody(
				formattedNickname: logLine.formattedNickname(in: channel) ?? "",
				text: logLine.messageBody
			)
		}

		return (formatted as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: 13.0),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString(string: formatted)
	}
}
