// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The people who answered one message with each emoji.
typealias ReactionsByEmoji = [String: [String]]

/** The reactions that arrived this session, by the message they answer.

 A reaction is carried by the connection, not by the line it decorates, so it
 has to be kept beside the transcript until the line it belongs to is drawn —
 and dropped again when that line's last row goes, otherwise the ledger grows
 for as long as the process runs. Which messages still have a row is the
 transcript's question, so a caller answers it with the `stillHeld` predicate.

 The caps are enforced here rather than at the wire: a reaction is an emoji
 sent by a stranger, and neither its length, the number of people who send it
 nor the number of different reactions one message collects is bounded by
 anything the server promises. */
nonisolated struct TranscriptReactionLedger: Sendable {
	/// The longest reaction kept, in UTF-16 units. A reaction is an emoji, and
	/// the longest sequences in use are a few dozen units.
	static let maximumReactionLength = 64
	/// How many people one reaction on one message records.
	static let maximumReactorsPerReaction = 256
	/// How many different reactions one message records. A reaction that is
	/// already recorded still gains reactors once the message is at this cap.
	static let maximumReactionsPerMessage = 32

	private var reactionsByMessage: [MessageIdentifierKey: ReactionsByEmoji] = [:]

	/// Everything recorded, as a render job reads it.
	var all: [MessageIdentifierKey: ReactionsByEmoji] {
		reactionsByMessage
	}

	func reactions(forMessage messageIdentifier: String) -> ReactionsByEmoji? {
		reactionsByMessage[MessageIdentifierKey(messageIdentifier)]
	}

	/** Records `wireEmoji` from `nickname`, and returns every reaction the
	 message now carries — what a drawn row is updated with. `nil` where the
	 reaction was refused: an empty emoji after sanitising, one longer than the
	 cap, a nameless sender, a message already answered by as many different
	 reactions as it records, or by as many people as one reaction records. */
	mutating func record(
		_ wireEmoji: String,
		from nickname: String,
		forMessage messageIdentifier: String
	) -> ReactionsByEmoji? {
		let emoji = ControlCharacterDisposition.singleLine(wireEmoji)
		guard !emoji.isEmpty, emoji.utf16.count <= Self.maximumReactionLength,
		      !nickname.isEmpty, !messageIdentifier.isEmpty
		else {
			return nil
		}
		var reactions = reactionsByMessage[MessageIdentifierKey(messageIdentifier)] ?? [:]
		guard reactions[emoji] != nil || reactions.count < Self.maximumReactionsPerMessage else { return nil }
		var nicknames = reactions[emoji] ?? []
		guard nicknames.count < Self.maximumReactorsPerReaction || nicknames.contains(nickname) else { return nil }
		if !nicknames.contains(nickname) {
			nicknames.append(nickname)
		}
		reactions[emoji] = nicknames
		reactionsByMessage[MessageIdentifierKey(messageIdentifier)] = reactions
		return reactions
	}

	/** Copies what `previousIdentifier` recorded onto `messageIdentifier`, for a
	 row whose identity changed — a local echo the server acknowledged under
	 its own identifier. The earlier reactors come first, as they were drawn,
	 and each reaction keeps the per-reaction cap. A reaction the target does
	 not hold yet is added, in sorted order, only while the target is under the
	 per-message cap. The previous entry stays
	 until `forget(_:stillHeld:)` finds no row left for it. */
	mutating func carry(from previousIdentifier: String, to messageIdentifier: String) {
		let previousKey = MessageIdentifierKey(previousIdentifier)
		let key = MessageIdentifierKey(messageIdentifier)
		guard previousKey != key, !messageIdentifier.isEmpty,
		      let previous = reactionsByMessage[previousKey]
		else {
			return
		}
		var reactions = reactionsByMessage[key] ?? [:]
		for emoji in previous.keys.sorted() {
			guard let earlier = previous[emoji],
			      reactions[emoji] != nil || reactions.count < Self.maximumReactionsPerMessage
			else {
				continue
			}
			let later = reactions[emoji] ?? []
			let merged = earlier + later.filter { !earlier.contains($0) }
			reactions[emoji] = Array(merged.prefix(Self.maximumReactorsPerReaction))
		}
		reactionsByMessage[key] = reactions
	}

	/// Drops what `identifiers` recorded, except where the transcript still
	/// holds a row for the message.
	mutating func forget(_ identifiers: [String], stillHeld: (String) -> Bool) {
		for identifier in identifiers where reactionsByMessage[MessageIdentifierKey(identifier)] != nil {
			guard stillHeld(identifier) == false else { continue }
			reactionsByMessage.removeValue(forKey: MessageIdentifierKey(identifier))
		}
	}

	mutating func removeAll() {
		reactionsByMessage.removeAll()
	}
}
