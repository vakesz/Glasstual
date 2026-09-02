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
 *********************************************************************** */

import CocoaExtensions
import Foundation

private nonisolated enum LogLineArchiveKey { // nonisolated: value
	static let command = "command"
	static let deliveryState = "deliveryState"
	static let excludeKeywords = "excludeKeywords"
	static let highlightKeywords = "highlightKeywords"
	static let isEncrypted = "isEncrypted"
	static let isFirstForDay = "isFirstForDay"
	static let lineType = "lineType"
	static let memberType = "memberType"
	static let messageBody = "messageBody"
	static let messageIdentifier = "messageIdentifier"
	static let nickname = "nickname"
	static let reactions = "reactions"
	static let receivedAt = "receivedAt"
	static let replyToMessageIdentifier = "replyToMessageIdentifier"
	static let sessionIdentifier = "sessionIdentifier"
	static let uniqueIdentifier = "uniqueIdentifier"
}

/** The archive form of a ``LogLine``.

 A ``LogLine`` is a value, and `NSKeyedArchiver` needs a class, so the coding
 lives here: the envelope is built at the archive boundary, immutable, and
 discarded on the far side of it. It answers to `TVCLogLine` because that is the
 class name every archive on disk records as its root object, and the key names
 and encoding order are the ones those archives were written with.
 */
@objc(TVCLogLine)
public final nonisolated class LogLineArchive: NSObject, NSSecureCoding, Sendable { // nonisolated: immutable
	/// The values one archive carried, before defaults are applied.
	struct DecodedValues {
		var receivedAt = Date()
		var excludeKeywords: [String]?
		var highlightKeywords: [String]?
		var isEncrypted = false
		var isFirstForDay = false
		var command = LogLineFormat.defaultCommand
		var messageBody = ""
		var messageIdentifier: String?
		var replyToMessageIdentifier: String?
		var reactions: [String: [String]]?
		var nickname: String?
		var lineType = LogLineType.undefined
		var memberType = LogLineMemberType.normal
		var deliveryState = LogLineDeliveryState.none
		var uniqueIdentifier: String?
		var sessionIdentifier: UInt = 0
	}

	public let line: LogLine

	public init(_ line: LogLine) {
		self.line = line

		super.init()
	}

	public required init?(coder: NSCoder) {
		var decoded = DecodedValues()

		decoded.receivedAt = coder
			.decodeObject(of: NSDate.self, forKey: LogLineArchiveKey.receivedAt) as Date? ?? Date()

		let stringArrayClasses: [AnyClass] = [NSArray.self, NSString.self]
		decoded.excludeKeywords = coder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.excludeKeywords
		) as? [String]
		decoded.highlightKeywords = coder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.highlightKeywords
		) as? [String]

		decoded.isEncrypted = coder.decodeBool(forKey: LogLineArchiveKey.isEncrypted)
		decoded.isFirstForDay = coder.decodeBool(forKey: LogLineArchiveKey.isFirstForDay)
		decoded.command = coder.textual_decodeString(
			forKey: LogLineArchiveKey.command
		) as String? ?? LogLineFormat.defaultCommand
		decoded.messageBody = coder.textual_decodeString(forKey: LogLineArchiveKey.messageBody) as String? ?? ""
		decoded.messageIdentifier = coder.textual_decodeString(
			forKey: LogLineArchiveKey.messageIdentifier
		) as String?
		decoded.replyToMessageIdentifier = coder.textual_decodeString(
			forKey: LogLineArchiveKey.replyToMessageIdentifier
		) as String?

		let reactionClasses: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self]
		decoded.reactions = coder.decodeObject(
			of: reactionClasses,
			forKey: LogLineArchiveKey.reactions
		) as? [String: [String]]
		decoded.nickname = coder.textual_decodeString(forKey: LogLineArchiveKey.nickname) as String?
		decoded.lineType = LogLineType(
			rawValue: UInt(coder.decodeInteger(forKey: LogLineArchiveKey.lineType))
		) ?? .undefined
		decoded.memberType = LogLineMemberType(
			rawValue: UInt(coder.decodeInteger(forKey: LogLineArchiveKey.memberType))
		) ?? .normal

		/* A line that was still in flight when the app last quit is not pending
		 any more; nothing is going to deliver it. */
		let decodedDeliveryState = LogLineDeliveryState(
			rawValue: UInt(coder.decodeInteger(forKey: LogLineArchiveKey.deliveryState))
		) ?? .none
		decoded.deliveryState = decodedDeliveryState == .pending ? .none : decodedDeliveryState
		decoded.uniqueIdentifier = coder.textual_decodeString(
			forKey: LogLineArchiveKey.uniqueIdentifier
		) as String?
		decoded.sessionIdentifier = UInt(coder.decodeInteger(forKey: LogLineArchiveKey.sessionIdentifier))

		var line = LogLine()
		line.restore(from: decoded)
		line.populateDefaultsPostflight()
		self.line = line

		super.init()
	}

	public func encode(with coder: NSCoder) {
		coder.encode(line.command as NSString, forKey: LogLineArchiveKey.command)
		coder.encode(line.messageBody as NSString, forKey: LogLineArchiveKey.messageBody)
		if let excludeKeywords = line.excludeKeywords {
			coder.encode(excludeKeywords, forKey: LogLineArchiveKey.excludeKeywords)
		}
		if let highlightKeywords = line.highlightKeywords {
			coder.encode(highlightKeywords, forKey: LogLineArchiveKey.highlightKeywords)
		}
		if let messageIdentifier = line.messageIdentifier {
			coder.encode(messageIdentifier as NSString, forKey: LogLineArchiveKey.messageIdentifier)
		}
		if let replyToMessageIdentifier = line.replyToMessageIdentifier {
			coder.encode(
				replyToMessageIdentifier as NSString,
				forKey: LogLineArchiveKey.replyToMessageIdentifier
			)
		}
		if let reactions = line.reactions {
			coder.encode(reactions, forKey: LogLineArchiveKey.reactions)
		}
		if let nickname = line.nickname {
			coder.encode(nickname as NSString, forKey: LogLineArchiveKey.nickname)
		}
		coder.encode(line.isEncrypted, forKey: LogLineArchiveKey.isEncrypted)
		coder.encode(line.isFirstForDay, forKey: LogLineArchiveKey.isFirstForDay)
		coder.encode(line.receivedAt, forKey: LogLineArchiveKey.receivedAt)
		coder.encode(Int(line.lineType.rawValue), forKey: LogLineArchiveKey.lineType)
		coder.encode(Int(line.memberType.rawValue), forKey: LogLineArchiveKey.memberType)

		if line.deliveryState != .none {
			coder.encode(Int(line.deliveryState.rawValue), forKey: LogLineArchiveKey.deliveryState)
		}

		if let uniqueIdentifier = line.archivedUniqueIdentifier {
			coder.encode(uniqueIdentifier as NSString, forKey: LogLineArchiveKey.uniqueIdentifier)
		}
		coder.encode(Int(line.sessionIdentifier), forKey: LogLineArchiveKey.sessionIdentifier)
	}

	public static var supportsSecureCoding: Bool {
		true
	}

	override public var description: String {
		line.description
	}
}

public extension LogLine {
	/// The line's `NSSecureCoding` form, ready for `NSKeyedArchiver`.
	var archived: LogLineArchive {
		LogLineArchive(self)
	}
}
