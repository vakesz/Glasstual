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
 *********************************************************************** */

import AppKit

@objc(IRCHighlightLogEntry)
public class HighlightLogEntry: XRPortablePropertyObject {
	fileprivate var lineLoggedStorage: TVCLogLine!
	fileprivate var clientIdStorage = ""
	fileprivate var channelIdStorage = ""

	@objc public var lineLogged: TVCLogLine {
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
				NSObject.masterController().world.findChannel(withId: channelId, onClientWithId: clientId)
			}
		}

		nonisolated(unsafe) var resolvedChannel: IRCChannel?
		XRPerformBlockSynchronouslyOnMainQueue {
			resolvedChannel = MainActor.assumeIsolated {
				NSObject.masterController().world.findChannel(withId: channelId, onClientWithId: clientId)
			}
		}
		return resolvedChannel
	}

	@objc public var channelName: String {
		if let channel {
			return channel.name
		}

		return LocalizedKey("BasicLanguage[vbl-xi]")
	}

	@objc public var timeLoggedFormatted: String {
		let timeInterval = lineLogged.receivedAt.timeIntervalSinceNow
		let formattedTimeInterval = humanReadableTimeInterval(timeInterval, true, 0) as String? ?? ""

		return LocalizedKey("BasicLanguage[4um-w4]", formattedTimeInterval)
	}

	@objc public var renderedMessage: NSAttributedString {
		let logLine = lineLogged
		let channel = channel

		let nicknameBody: String?
		let messageBody: String

		if logLine.lineType == .action {
			nicknameBody = logLine.nickname
			messageBody = TXNotificationHighlightLogStandardActionFormat
		} else {
			nicknameBody = logLine.formattedNickname(in: channel)
			messageBody = TXNotificationHighlightLogStandardMessageFormat
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
	override public func populateDuringCopy(_ newObject: XRPortablePropertyObject, mutableCopy _: Bool) {
		guard let object = newObject as? HighlightLogEntry else {
			return
		}

		object.lineLoggedStorage = lineLoggedStorage
		object.clientIdStorage = clientIdStorage
		object.channelIdStorage = channelIdStorage
	}

	override public var mutableClass: XRPortablePropertyObject {
		unsafeBitCast(MutableHighlightLogEntry.self, to: XRPortablePropertyObject.self)
	}
}

@objc(IRCHighlightLogEntryMutable)
public final class MutableHighlightLogEntry: HighlightLogEntry {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyObject {
		unsafeBitCast(HighlightLogEntry.self, to: XRPortablePropertyObject.self)
	}

	@objc override public var lineLogged: TVCLogLine {
		get { lineLoggedStorage }
		set { lineLoggedStorage = newValue.copy() as! TVCLogLine }
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
