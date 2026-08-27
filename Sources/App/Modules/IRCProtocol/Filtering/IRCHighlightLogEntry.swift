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

@objc(IRCHighlightLogEntry)
public class HighlightLogEntry: PortablePropertyObject {
	fileprivate var lineLoggedStorage: LogLine!
	fileprivate var clientIdStorage = ""
	fileprivate var channelIdStorage = ""

	@objc public var lineLogged: LogLine {
		lineLoggedStorage
	}

	@objc public var clientId: String {
		clientIdStorage
	}

	@objc public var channelId: String {
		channelIdStorage
	}

	@objc public var timeLogged: Date {
		lineLogged.receivedAt
	}

	@objc public var lineNumber: String {
		lineLogged.uniqueIdentifier
	}

	@objc public var channel: IRCChannel? {
		let channelId = channelIdStorage
		let clientId = clientIdStorage

		if Thread.isMainThread {
			return MainActor.assumeIsolated {
				NSObject.applicationController().world.findChannel(withId: channelId, onClientWithId: clientId)
			}
		}

		nonisolated(unsafe) var resolvedChannel: IRCChannel?
		performSynchronouslyOnMainQueue {
			resolvedChannel = MainActor.assumeIsolated {
				NSObject.applicationController().world.findChannel(withId: channelId, onClientWithId: clientId)
			}
		}
		return resolvedChannel
	}

	@objc public var channelName: String {
		if let channel {
			return channel.name
		}

		return ApplicationStrings.unknownValue
	}

	@objc public var timeLoggedFormatted: String {
		let timeInterval = lineLogged.receivedAt.timeIntervalSinceNow
		let formattedTimeInterval = humanReadableTimeInterval(timeInterval, true, 0) as String? ?? ""

		return ApplicationStrings.relativeTime(formattedTimeInterval)
	}

	@objc public var renderedMessage: NSAttributedString {
		let logLine = lineLogged
		let channel = channel

		let nicknameBody: String?
		let messageBody: String

		if logLine.lineType == .action {
			nicknameBody = logLine.nickname
			messageBody = NotificationPayload.highlightActionFormat
		} else {
			nicknameBody = logLine.formattedNickname(in: channel)
			messageBody = NotificationPayload.highlightMessageFormat
		}

		let formatted = String(format: messageBody, nicknameBody ?? "", logLine.messageBody)

		return (formatted as NSString).attributedString(
			withIRCFormatting: NSFont.systemFont(ofSize: 13.0),
			preferredFontColor: .controlTextColor
		) ?? NSAttributedString(string: formatted)
	}

	override public var description: String {
		guard let channel else {
			return super.description
		}

		return lineLogged.renderedBodyForTranscriptLog(in: channel)
	}

	override public init() {
		super.init()
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if isMutable || initializedAsCopy {
			return
		}

		precondition(lineLoggedStorage != nil)
		precondition(!clientIdStorage.isEmpty)
		precondition(!channelIdStorage.isEmpty)
	}

	@objc(populateDuringCopy:mutableCopy:)
	override public func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		guard let object = newObject as? HighlightLogEntry else {
			return
		}

		object.lineLoggedStorage = lineLoggedStorage
		object.clientIdStorage = clientIdStorage
		object.channelIdStorage = channelIdStorage
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(MutableHighlightLogEntry.self, to: PortablePropertyObject.self)
	}
}

@objc(IRCHighlightLogEntryMutable)
public final class MutableHighlightLogEntry: HighlightLogEntry {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(HighlightLogEntry.self, to: PortablePropertyObject.self)
	}

	@objc override public var lineLogged: LogLine {
		get { lineLoggedStorage }
		set {
			guard let copiedLine = newValue.copy() as? LogLine else {
				preconditionFailure("LogLine.copy() must return a LogLine")
			}
			lineLoggedStorage = copiedLine
		}
	}

	@objc override public var clientId: String {
		get { clientIdStorage }
		set { clientIdStorage = newValue }
	}

	@objc override public var channelId: String {
		get { channelIdStorage }
		set { channelIdStorage = newValue }
	}
}
