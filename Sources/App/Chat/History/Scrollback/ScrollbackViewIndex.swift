// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation

/** A fixed-width stand-in for a string the index only ever compares for
 equality: a message identifier, or a line's timestamp, nickname and body.

 A 128-bit SHA-256 prefix replaces the text it would otherwise keep a second
 copy of. Each kind of input is hashed under its own domain byte, and a
 nickname is length-prefixed, so no two inputs can be split a different way to
 produce the same digest. */
nonisolated struct LineDigest: Hashable, Sendable {
	private enum Domain: UInt8 {
		case messageIdentifier = 1
		case fallback = 2
	}

	private let high: UInt64
	private let low: UInt64

	/// Stored where a contribution carries no digest; a flag says it is absent.
	fileprivate static let placeholder = LineDigest(high: 0, low: 0)

	private init(high: UInt64, low: UInt64) {
		self.high = high
		self.low = low
	}

	private init(domain: Domain, _ feed: (inout SHA256) -> Void) {
		var hasher = SHA256()
		withUnsafeBytes(of: domain.rawValue) { hasher.update(bufferPointer: $0) }
		feed(&hasher)
		var high: UInt64 = 0
		var low: UInt64 = 0
		for (index, byte) in hasher.finalize().prefix(16).enumerated() {
			if index < 8 {
				high = high << 8 | UInt64(byte)
			} else {
				low = low << 8 | UInt64(byte)
			}
		}
		self.init(high: high, low: low)
	}

	/// Compared by UTF-8 bytes, as `MessageIdentifierKey` compares.
	static func messageIdentifier(_ identifier: String) -> Self {
		var identifier = identifier
		return Self(domain: .messageIdentifier) { hasher in
			identifier.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
		}
	}

	static func fallback(milliseconds: Int64, nickname: String, messageBody: String) -> Self {
		var nickname = nickname
		var messageBody = messageBody
		return Self(domain: .fallback) { hasher in
			withUnsafeBytes(of: milliseconds.littleEndian) { hasher.update(bufferPointer: $0) }
			nickname.withUTF8 { bytes in
				withUnsafeBytes(of: UInt64(bytes.count).littleEndian) { hasher.update(bufferPointer: $0) }
				hasher.update(bufferPointer: UnsafeRawBufferPointer(bytes))
			}
			messageBody.withUTF8 { hasher.update(bufferPointer: UnsafeRawBufferPointer($0)) }
		}
	}
}

/** What names a stored line in the index.

 A line identifier minted by this app is four hex digits, a dash and twelve
 more — 17 bytes, which Swift keeps on the heap — so it is packed into one
 integer. Anything else, such as an identifier an older store minted, is kept
 as it is. Only the canonical upper-case spelling packs, so two different
 strings never share a key. */
nonisolated enum LineKey: Hashable, Sendable {
	case packed(UInt64)
	case text(String)

	init(_ identifier: String) {
		var value: UInt64 = 0
		var digits = 0
		for (offset, byte) in identifier.utf8.enumerated() {
			if offset == 4 {
				guard byte == 0x2D else {
					self = .text(identifier)
					return
				}
				continue
			}
			guard digits < 16, let nibble = Self.nibble(byte) else {
				self = .text(identifier)
				return
			}
			value = value << 4 | nibble
			digits += 1
		}
		self = digits == 16 && identifier.utf8.count == 17 ? .packed(value) : .text(identifier)
	}

	private static func nibble(_ byte: UInt8) -> UInt64? {
		switch byte {
		case 0x30 ... 0x39: UInt64(byte - 0x30)
		case 0x41 ... 0x46: UInt64(byte - 0x41 + 10)
		default: nil
		}
	}
}

/** Which removal a line was indexed under.

 Opaque and compared only for equality. The directory hands out a new one each
 time a removal is requested, and never reuses one while a removal that holds
 it can still be waiting. */
nonisolated struct ScrollbackGeneration: Hashable, Sendable {
	private let rawValue: UInt32

	static let initial = ScrollbackGeneration(rawValue: 0)

	func advanced() -> Self {
		Self(rawValue: rawValue &+ 1)
	}
}

/** What one indexed line contributed, so the contribution can be withdrawn
 when the line goes.

 Laid out flat, with a flag for each optional part, so a contribution takes
 56 bytes rather than the padded optionals a literal spelling would. */
nonisolated struct ScrollbackContribution: Sendable {
	private struct Flags: OptionSet, Sendable {
		let rawValue: UInt8

		static let hasMessageIdentifier = Flags(rawValue: 1 << 0)
		static let hasFallbackKey = Flags(rawValue: 1 << 1)
		static let isConversation = Flags(rawValue: 1 << 2)
		static let hasReadMarker = Flags(rawValue: 1 << 3)
	}

	private let identifierDigest: LineDigest
	private let fallbackDigest: LineDigest
	let receivedAt: Date
	private let markerInterval: TimeInterval
	private let flags: Flags

	init(
		messageIdentifier: LineDigest?,
		fallbackKey: LineDigest?,
		receivedAt: Date,
		isConversation: Bool,
		readMarkerTimestamp: Date?
	) {
		var flags: Flags = []
		if messageIdentifier != nil {
			flags.insert(.hasMessageIdentifier)
		}
		if fallbackKey != nil {
			flags.insert(.hasFallbackKey)
		}
		if isConversation {
			flags.insert(.isConversation)
		}
		if readMarkerTimestamp != nil {
			flags.insert(.hasReadMarker)
		}
		identifierDigest = messageIdentifier ?? .placeholder
		fallbackDigest = fallbackKey ?? .placeholder
		self.receivedAt = receivedAt
		markerInterval = readMarkerTimestamp?.timeIntervalSinceReferenceDate ?? 0
		self.flags = flags
	}

	var messageIdentifier: LineDigest? {
		flags.contains(.hasMessageIdentifier) ? identifierDigest : nil
	}

	var fallbackKey: LineDigest? {
		flags.contains(.hasFallbackKey) ? fallbackDigest : nil
	}

	var isConversation: Bool {
		flags.contains(.isConversation)
	}

	var readMarkerTimestamp: Date? {
		flags.contains(.hasReadMarker) ? Date(timeIntervalSinceReferenceDate: markerInterval) : nil
	}
}

/** What the app knows about the lines of one view, kept in memory so that chat
 history replayed by the server can be checked against the local scrollback.
 The index is filled from every line written and every line fetched, and
 withdrawn again when the store prunes the row behind it — otherwise it would
 hold a second copy of every message the process has ever seen.

 The newest `recentLimit` lines, by their own time, are held whole. An older
 line keeps only what a later check can still ask of it: its message
 identifier when it has one, since a replayed line that carries an identifier
 is checked by that alone, and its fallback key when it has none, since that is
 then the only thing it can be matched by. The dates a history request and a
 read marker are answered from are maxima over every line the index has seen,
 so they do not depend on the older tier; they are recomputed from the recent
 tier alone, which can only lower them.

 The two lookups are counted rather than set-valued: two lines can carry the
 same body at the same second from the same nickname, and dropping one of them
 must not make the other invisible to the duplicate check.

 The index itself is a value with no reference-typed state; the directory owns
 the only copies and keeps them on the main actor. */
nonisolated struct ScrollbackViewIndex: Sendable {
	private struct Entry: Sendable {
		let contribution: ScrollbackContribution
		let generation: ScrollbackGeneration
	}

	/// What an older line is still found by.
	private enum Handle: Sendable {
		case messageIdentifier(LineDigest)
		case fallbackKey(LineDigest)

		init?(_ contribution: ScrollbackContribution) {
			if let identifier = contribution.messageIdentifier {
				self = .messageIdentifier(identifier)
			} else if let fallbackKey = contribution.fallbackKey {
				self = .fallbackKey(fallbackKey)
			} else {
				return nil
			}
		}
	}

	private struct LightEntry: Sendable {
		let handle: Handle
		let generation: ScrollbackGeneration
	}

	private(set) var messageIdentifiers: [LineDigest: UInt32] = [:]
	private(set) var fallbackKeys: [LineDigest: UInt32] = [:]
	private var recent: [LineKey: Entry] = [:]
	private var older: [LineKey: LightEntry] = [:]
	private var generation: ScrollbackGeneration
	private let recentLimit: Int
	/// The oldest time left in the recent tier after the last demotion. A line
	/// older than this goes straight to the older tier once the recent tier is full.
	private var cutoff: Date?
	/// Whether a line in the older tier may be the one a newest date came from,
	/// so that pruning it has to recompute the dates rather than leave a date
	/// no stored line carries.
	private var olderMayHoldNewest = false
	private(set) var newestDate: Date?
	/** The newest line a person wrote, as opposed to one the session narrated.

	 A read marker is answered against this rather than `newestDate`: joining a
	 channel prints a topic, a mode and a join line stamped now, and none of them
	 is news the badge should count. */
	private(set) var newestConversationDate: Date?
	private(set) var newestReadMarkerTimestamp: Date?

	init(generation: ScrollbackGeneration, recentLimit: Int) {
		self.generation = generation
		self.recentLimit = max(1, recentLimit)
	}

	var isEmpty: Bool {
		recent.isEmpty && older.isEmpty
	}

	/// Records what `uniqueIdentifier` contributes, and reports whether this
	/// call added it. A line the index already holds is left alone: the same
	/// row is indexed again on every fetch.
	@discardableResult
	mutating func add(_ contribution: ScrollbackContribution, for uniqueIdentifier: String) -> Bool {
		guard uniqueIdentifier.isEmpty == false else {
			retain(contribution)
			return false
		}
		let key = LineKey(uniqueIdentifier)
		guard recent[key] == nil, older[key] == nil else { return false }
		noteNewest(contribution)
		if let cutoff, recent.count >= recentLimit, contribution.receivedAt < cutoff {
			noteOlder(contribution)
			if let handle = Handle(contribution) {
				retain(handle)
				older[key] = LightEntry(handle: handle, generation: generation)
			}
			return true
		}
		retain(contribution)
		recent[key] = Entry(contribution: contribution, generation: generation)
		if recent.count > recentLimit + max(1, recentLimit / 4) {
			demoteOldest()
		}
		return true
	}

	mutating func replace(_ contribution: ScrollbackContribution, for identifier: String) -> Bool {
		let key = LineKey(identifier)
		if let previous = recent[key] {
			release(previous.contribution)
			recent[key] = Entry(contribution: contribution, generation: previous.generation)
			retain(contribution)
			refreshDates()
			return true
		}
		if let previous = older[key] {
			release(previous.handle)
			if let handle = Handle(contribution) {
				retain(handle)
				older[key] = LightEntry(handle: handle, generation: previous.generation)
			} else {
				older.removeValue(forKey: key)
			}
			return true
		}
		return false
	}

	/// Later writes belong to a new generation. A successful deletion only
	/// withdraws the generations that existed when it was requested.
	mutating func beginRemoval(next: ScrollbackGeneration) -> Set<ScrollbackGeneration> {
		var removed = Set(recent.values.map(\.generation))
		removed.formUnion(older.values.map(\.generation))
		generation = next
		return removed
	}

	mutating func remove(generations: Set<ScrollbackGeneration>) {
		let recentKeys = recent.compactMap { generations.contains($0.value.generation) ? $0.key : nil }
		let olderKeys = older.compactMap { generations.contains($0.value.generation) ? $0.key : nil }
		for key in recentKeys + olderKeys {
			remove(key, updateDates: false)
		}
		refreshDates()
	}

	/// Withdraws what a pruned line contributed.
	mutating func remove(_ uniqueIdentifier: String) {
		remove(LineKey(uniqueIdentifier), updateDates: true)
	}

	private mutating func remove(_ key: LineKey, updateDates: Bool) {
		if let contribution = recent.removeValue(forKey: key)?.contribution {
			release(contribution)
			if updateDates,
			   contribution.receivedAt == newestDate || contribution.receivedAt == newestConversationDate
			   || (contribution.readMarkerTimestamp != nil && contribution.readMarkerTimestamp == newestReadMarkerTimestamp)
			{
				refreshDates()
			}
		} else if let light = older.removeValue(forKey: key) {
			release(light.handle)
			if updateDates, olderMayHoldNewest {
				refreshDates()
			}
		} else {
			return
		}
		compactIfSparse()
	}

	/// Moves the oldest lines of the recent tier down to the limit. Runs once
	/// the tier has grown a quarter past it, so the sort is paid per batch of
	/// lines and not per line.
	private mutating func demoteOldest() {
		let excess = recent.count - recentLimit
		guard excess > 0 else { return }
		let ordered = recent.sorted { $0.value.contribution.receivedAt < $1.value.contribution.receivedAt }
		for (key, entry) in ordered.prefix(excess) {
			recent.removeValue(forKey: key)
			let contribution = entry.contribution
			noteOlder(contribution)
			guard let handle = Handle(contribution) else { continue }
			// A line found by its identifier no longer needs its fallback key.
			if case .messageIdentifier = handle, let fallbackKey = contribution.fallbackKey {
				Self.release(fallbackKey, from: &fallbackKeys)
			}
			older[key] = LightEntry(handle: handle, generation: entry.generation)
		}
		cutoff = ordered[excess].value.contribution.receivedAt
		compactIfSparse()
	}

	private mutating func noteNewest(_ contribution: ScrollbackContribution) {
		newestDate = max(newestDate ?? contribution.receivedAt, contribution.receivedAt)
		if contribution.isConversation {
			newestConversationDate = max(newestConversationDate ?? contribution.receivedAt, contribution.receivedAt)
		}
		if let timestamp = contribution.readMarkerTimestamp {
			newestReadMarkerTimestamp = max(newestReadMarkerTimestamp ?? timestamp, timestamp)
		}
	}

	private mutating func noteOlder(_ contribution: ScrollbackContribution) {
		if contribution.receivedAt == newestDate
			|| (contribution.isConversation && contribution.receivedAt == newestConversationDate)
			|| (contribution.readMarkerTimestamp != nil && contribution.readMarkerTimestamp == newestReadMarkerTimestamp)
		{
			olderMayHoldNewest = true
		}
	}

	private mutating func refreshDates() {
		olderMayHoldNewest = false
		newestDate = recent.values.map(\.contribution.receivedAt).max()
		newestConversationDate = recent.values.filter(\.contribution.isConversation)
			.map(\.contribution.receivedAt).max()
		newestReadMarkerTimestamp = recent.values.compactMap(\.contribution.readMarkerTimestamp).max()
	}

	private mutating func retain(_ contribution: ScrollbackContribution) {
		if let messageIdentifier = contribution.messageIdentifier {
			messageIdentifiers[messageIdentifier, default: 0] += 1
		}
		if let fallbackKey = contribution.fallbackKey {
			fallbackKeys[fallbackKey, default: 0] += 1
		}
	}

	private mutating func retain(_ handle: Handle) {
		switch handle {
		case let .messageIdentifier(digest): messageIdentifiers[digest, default: 0] += 1
		case let .fallbackKey(digest): fallbackKeys[digest, default: 0] += 1
		}
	}

	private mutating func release(_ contribution: ScrollbackContribution) {
		Self.release(contribution.messageIdentifier, from: &messageIdentifiers)
		Self.release(contribution.fallbackKey, from: &fallbackKeys)
	}

	private mutating func release(_ handle: Handle) {
		switch handle {
		case let .messageIdentifier(digest): Self.release(digest, from: &messageIdentifiers)
		case let .fallbackKey(digest): Self.release(digest, from: &fallbackKeys)
		}
	}

	private static func release(_ key: LineDigest?, from counts: inout [LineDigest: UInt32]) {
		guard let key, let count = counts[key] else { return }
		if count <= 1 {
			counts.removeValue(forKey: key)
		} else {
			counts[key] = count - 1
		}
	}

	/// A dictionary never gives back the room it grew to, so a table that has
	/// lost more than half of what it held is rebuilt at the size it needs.
	private mutating func compactIfSparse() {
		Self.compact(&recent)
		Self.compact(&older)
		Self.compact(&messageIdentifiers)
		Self.compact(&fallbackKeys)
	}

	private static func compact<Key: Hashable, Value>(_ dictionary: inout [Key: Value]) {
		guard dictionary.capacity > 256, dictionary.count * 2 < dictionary.capacity else { return }
		var compacted = [Key: Value](minimumCapacity: dictionary.count)
		for (key, value) in dictionary {
			compacted[key] = value
		}
		dictionary = compacted
	}
}
