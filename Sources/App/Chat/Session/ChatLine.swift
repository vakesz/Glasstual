// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The raw values are persisted — they are written into the renderer
 attribute dictionary and archived with every chat line — so a number may never
 be reused and a new case may only ever be appended. `offTheRecordEncryptionStatus`
 stays at 15 for the sake of already-archived lines even though OTR is gone. */
enum ChatLineKind: UInt, Codable, Sendable {
	case undefined = 0
	case action = 1
	case actionNoHighlight = 2
	case ctcp = 3
	case ctcpQuery = 4
	case ctcpReply = 5
	case dccFileTransfer = 6
	case debug = 7
	case invite = 8
	case join = 9
	case kick = 10
	case kill = 11
	case mode = 12
	case nick = 13
	case notice = 14
	case offTheRecordEncryptionStatus = 15
	case part = 16
	case privateMessage = 17
	case privateMessageNoHighlight = 18
	case quit = 19
	case topic = 20
	case website = 21

	/// Something a person said, as opposed to an event the session narrates —
	/// a join, a mode, a topic. The unread marker is placed before the first
	/// of these, not before the first line of any kind.
	nonisolated var isConversation: Bool { // nonisolated: pure
		switch self {
		case .action, .actionNoHighlight, .notice, .privateMessage, .privateMessageNoHighlight:
			true
		default:
			false
		}
	}

	/// A message whose body the renderer scans for the conversation's members and
	/// the reader's highlight keywords.
	nonisolated var mentionsMembers: Bool { // nonisolated: pure
		self == .privateMessage || self == .action
	}
}

/** Persisted alongside the chat line; see `ChatLineKind`. */
enum ChatLineMemberKind: UInt, Codable, Sendable {
	case normal = 0
	case localUser = 1
}

/** Persisted alongside the chat line; see `ChatLineKind`. */
enum ChatLineDeliveryState: UInt, Codable, Sendable {
	case none = 0
	case pending = 1
	case delivered = 2
	case failed = 3
}

/** One printed line: what the renderer draws and what the scrollback stores.

 A value. Every field is a `Sendable` value, so a line crosses into the render
 pipeline as itself rather than through a hand-written snapshot, and a line a
 controller has already queued cannot change underneath it. `uniqueIdentifier`
 is its identity: assigned once when the line is created and carried through
 every copy and every archive.

 A history entry is stored as ``ChatLineStoredPayload``, a versioned Codable
 property list. */
nonisolated struct ChatLine: Codable, Hashable, Sendable, CustomStringConvertible {
	var isEncrypted = false
	var isFirstForDay = false
	var receivedAt = Date()
	var messageBody = ""
	var command = ChatLineFormat.defaultCommand
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var reactions: [String: [String]]?
	var lineType: ChatLineKind = .undefined
	var memberType: ChatLineMemberKind = .normal
	var deliveryState: ChatLineDeliveryState = .none
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?

	var nickname: String?
	private(set) var sessionIdentifier: UInt = 0

	/// The line's identity, stable across copies and archives.
	private(set) var uniqueIdentifier = ""

	/** The names the fields carry inside ``ChatLineStoredPayload``, and so inside
	 every stored scrollback row.

	 Pinned rather than synthesized: a property rename would otherwise compile
	 cleanly and quietly stop every row already on disk from decoding, which the
	 reader sees as a scrollback that emptied itself. Renaming a property is
	 fine; changing a string here is a storage format change.
	 `Tests/Corpora/History/ScrollbackPayload-v1.plist` holds these names, and
	 `CaseIterable` is what lets the test compare the two sets. */
	enum CodingKeys: String, CodingKey, CaseIterable {
		case isEncrypted
		case isFirstForDay
		case receivedAt
		case messageBody
		case command
		case messageIdentifier
		case replyToMessageIdentifier
		case reactions
		case lineType
		case memberType
		case deliveryState
		case highlightKeywords
		case excludeKeywords
		case nickname
		case sessionIdentifier
		case uniqueIdentifier
	}

	init() {
		populateDefaultsPostflight()
	}

	init?(data: Data) {
		if let payload = try? PropertyListDecoder().decode(ChatLineStoredPayload.self, from: data) {
			guard payload.version == ChatLineStoredPayload.currentVersion else { return nil }
			self = payload.line
			if deliveryState == .pending {
				deliveryState = .none
			}
			populateDefaultsPostflight()
			return
		}
		return nil
	}

	/// The line a stored scrollback row holds, or `nil` when the row's payload is
	/// not one this build can read.
	init?(entry: ScrollbackEntry) {
		guard var line = ChatLine(data: entry.data) else {
			return nil
		}

		if line.uniqueIdentifier.isEmpty {
			line.uniqueIdentifier = entry.uniqueIdentifier
		}

		self = line
	}

	/// Fills in the identifiers a fresh line needs and folds the two retired
	/// "no highlight" line types onto their live equivalents.
	mutating func populateDefaultsPostflight() {
		populateDefaultUniqueIdentifier()
		populateDefaultSessionIdentifier()

		switch lineType {
		case .actionNoHighlight:
			lineType = .action
			highlightKeywords = nil
		case .privateMessageNoHighlight:
			lineType = .privateMessage
			highlightKeywords = nil
		default:
			break
		}
	}

	mutating func populateDefaultUniqueIdentifier() {
		if uniqueIdentifier.isEmpty {
			uniqueIdentifier = Self.newUniqueIdentifier()
		}
	}

	mutating func populateDefaultSessionIdentifier() {
		if sessionIdentifier == 0 {
			sessionIdentifier = Self.currentSessionIdentifier()
		}
	}

	/// Restores the two identities a stored line carried. Every other field is
	/// settable within the module; these are the line's own. A stored line that
	/// carried none leaves them empty, which is what tells
	/// `populateDefaultsPostflight` to mint a fresh one.
	mutating func restoreIdentity(uniqueIdentifier: String?, sessionIdentifier: UInt) {
		self.uniqueIdentifier = uniqueIdentifier ?? ""
		self.sessionIdentifier = sessionIdentifier
	}

	func scrollbackEntry(forView viewIdentifier: String) -> ScrollbackEntry {
		guard let data = try? PropertyListEncoder().encode(ChatLineStoredPayload(line: self)) else {
			preconditionFailure("A chat line must remain encodable")
		}

		return ScrollbackEntry(
			lineData: data,
			uniqueIdentifier: uniqueIdentifier,
			viewIdentifier: viewIdentifier,
			sessionIdentifier: sessionIdentifier,
			creationDate: receivedAt.timeIntervalSince1970
		)
	}

	static func newUniqueIdentifier() -> String {
		String(UUID().uuidString.dropFirst(19))
	}

	static func currentSessionIdentifier() -> UInt {
		Session.identifier
	}

	var fromCurrentSession: Bool {
		sessionIdentifier == Self.currentSessionIdentifier()
	}

	/// Names the line without formatting it: the identifier is what a failure
	/// log needs in order to find it again in the archive.
	var description: String {
		"<ChatLine \(uniqueIdentifier) \(lineTypeString ?? "undefined")>"
	}

	/** A session identifier for a new process.

	 Never zero, because zero is what tells `populateDefaultSessionIdentifier`
	 that a line has none yet; and drawn from the whole range the archive and
	 the store keep (a signed 64-bit integer), so a later launch does not pick
	 an earlier one's and count that session's lines as its own. */
	static func newSessionIdentifier(using generator: inout some RandomNumberGenerator) -> UInt {
		UInt.random(in: 1 ... UInt(Int64.max), using: &generator)
	}

	private enum Session {
		static let identifier: UInt = {
			var generator = SystemRandomNumberGenerator()
			return newSessionIdentifier(using: &generator)
		}()
	}
}

/** One stored scrollback row: a version this build understands, and the line.

 Version 1 is the only version there has ever been of this format — a row
 written by any other is refused rather than adapted, and the store drops it.
 The coding keys are pinned for the same reason ``ChatLine``'s are. */
nonisolated struct ChatLineStoredPayload: Codable {
	static let currentVersion = 1
	var version = currentVersion
	let line: ChatLine

	enum CodingKeys: String, CodingKey {
		case version
		case line
	}
}
