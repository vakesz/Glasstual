/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

import AppKit
import CocoaExtensions
import os

private nonisolated let highlightLogEntryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCHighlightLogEntry"
)

/** An entry in a client's in-memory highlight log.

 The entry is never written to disk, so it is not `Codable`. It stays an `@objc`
 `NSObject` because `TDCServerHighlightListSheet` puts it into an
 `NSArrayController` and binds table columns to `channelName`,
 `renderedMessage` and `timeLoggedFormatted` — and sorts on `timeLogged` — by
 KVC key path from its nib. */
@objc(IRCHighlightLogEntry)
public final nonisolated class HighlightLogEntry: NSObject {
	@objc public var lineLogged: LogLine
	@objc public var clientId: String
	@objc public var channelId: String

	@objc public init(lineLogged: LogLine, clientId: String, channelId: String) {
		self.lineLogged = lineLogged
		self.clientId = clientId
		self.channelId = channelId

		super.init()

		// An incomplete entry used to abort the app from a health check; it is
		// only logged now, and callers that care check `isWellFormed`.
		if isWellFormed == false {
			highlightLogEntryLogger.error("Created an incomplete highlight log entry")
		}
	}

	/// `true` when the entry carries everything its accessors need.
	@objc public var isWellFormed: Bool {
		clientId.isEmpty == false && channelId.isEmpty == false
	}

	@objc public var timeLogged: Date {
		lineLogged.receivedAt
	}

	@objc public var lineNumber: String {
		lineLogged.uniqueIdentifier
	}

	@objc @MainActor public var channel: IRCChannel? {
		AppController.shared.world.findChannel(
			withId: channelId,
			onClientWithId: clientId
		)
	}

	@objc @MainActor public var channelName: String {
		channel?.name ?? ApplicationStrings.unknownValue
	}

	@objc public var timeLoggedFormatted: String {
		let timeInterval = lineLogged.receivedAt.timeIntervalSinceNow
		let formattedTimeInterval = humanReadableTimeInterval(timeInterval, true, 0) as String? ?? ""

		return ApplicationStrings.relativeTime(formattedTimeInterval)
	}

	@objc @MainActor public var renderedMessage: NSAttributedString {
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

	/** `NSObject.description` is nonisolated, so it cannot resolve the channel or
	 format the line against it; the identifiers name the entry instead. */
	override public var description: String {
		"<IRCHighlightLogEntry [\(channelId)]: \(lineNumber)>"
	}
}
