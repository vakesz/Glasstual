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

/// The on-disk history payload. The Core Data row stays unchanged, and its
/// opaque data can be decoded independently of the application's runtime names.
nonisolated struct LogLineStoredPayload: Codable { // nonisolated: value
	static let currentVersion = 1
	var version = currentVersion
	let line: LogLine

	/// Reads the stored time without constructing a line or assigning identity.
	static func receivedAt(in data: Data) -> Date? {
		guard let timestamp = try? PropertyListDecoder().decode(Timestamp.self, from: data),
		      timestamp.version == currentVersion else { return nil }
		return timestamp.line.receivedAt
	}

	private struct Timestamp: Decodable {
		let version: Int
		let line: TimestampLine
	}

	private struct TimestampLine: Decodable { let receivedAt: Date }
}

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

/** The legacy archive form of a ``LogLine``.

 Kept for reading existing history. New writes use ``LogLineStoredPayload``.
 This decoder answers to `TVCLogLine`, the root class older archives recorded.
 */
@objc(TVCLogLine)
final nonisolated class LogLineArchive: NSObject, NSSecureCoding, Sendable { // nonisolated: immutable
	let line: LogLine

	init(_ line: LogLine) {
		self.line = line

		super.init()
	}

	required init?(coder: NSCoder) {
		var line = LogLine()

		line.receivedAt = coder
			.decodeObject(of: NSDate.self, forKey: LogLineArchiveKey.receivedAt) as Date? ?? Date()

		let stringArrayClasses: [AnyClass] = [NSArray.self, NSString.self]
		line.excludeKeywords = coder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.excludeKeywords
		) as? [String]
		line.highlightKeywords = coder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.highlightKeywords
		) as? [String]

		line.isEncrypted = coder.decodeBool(forKey: LogLineArchiveKey.isEncrypted)
		line.isFirstForDay = coder.decodeBool(forKey: LogLineArchiveKey.isFirstForDay)
		line.command = coder.textual_decodeString(
			forKey: LogLineArchiveKey.command
		) as String? ?? LogLineFormat.defaultCommand
		line.messageBody = coder.textual_decodeString(forKey: LogLineArchiveKey.messageBody) as String? ?? ""
		line.messageIdentifier = coder.textual_decodeString(
			forKey: LogLineArchiveKey.messageIdentifier
		) as String?
		line.replyToMessageIdentifier = coder.textual_decodeString(
			forKey: LogLineArchiveKey.replyToMessageIdentifier
		) as String?

		let reactionClasses: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self]
		line.reactions = coder.decodeObject(
			of: reactionClasses,
			forKey: LogLineArchiveKey.reactions
		) as? [String: [String]]
		line.nickname = coder.textual_decodeString(forKey: LogLineArchiveKey.nickname) as String?
		/* Nothing here was ever encoded negative, so a negative value belongs to
		 a damaged or hand-written archive. `UInt(exactly:)` sends it to the same
		 default an unknown raw value takes rather than trapping the conversion. */
		line.lineType = UInt(exactly: coder.decodeInteger(forKey: LogLineArchiveKey.lineType))
			.flatMap(LogLineType.init(rawValue:)) ?? .undefined
		line.memberType = UInt(exactly: coder.decodeInteger(forKey: LogLineArchiveKey.memberType))
			.flatMap(LogLineMemberType.init(rawValue:)) ?? .normal

		/* A line that was still in flight when the app last quit is not pending
		 any more; nothing is going to deliver it. */
		let deliveryState = UInt(exactly: coder.decodeInteger(forKey: LogLineArchiveKey.deliveryState))
			.flatMap(LogLineDeliveryState.init(rawValue:)) ?? .none
		line.deliveryState = deliveryState == .pending ? .none : deliveryState
		line.restoreIdentity(
			uniqueIdentifier: coder.textual_decodeString(forKey: LogLineArchiveKey.uniqueIdentifier) as String?,
			sessionIdentifier: UInt(exactly: coder.decodeInteger(forKey: LogLineArchiveKey.sessionIdentifier)) ?? 0
		)
		line.populateDefaultsPostflight()
		self.line = line

		super.init()
	}

	func encode(with coder: NSCoder) {
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

	static var supportsSecureCoding: Bool {
		true
	}

	override var description: String {
		line.description
	}
}
