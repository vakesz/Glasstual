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

 Both caps are enforced here rather than at the wire: a reaction is an emoji
 sent by a stranger, and neither its length nor the number of people who send
 it is bounded by anything the server promises. */
nonisolated struct TranscriptReactionLedger: Sendable {
	/// The longest reaction kept, in UTF-16 units. A reaction is an emoji, and
	/// the longest sequences in use are a few dozen units.
	static let maximumReactionLength = 64
	/// How many people one reaction on one message records.
	static let maximumReactorsPerReaction = 256

	private var reactionsByMessage: [String: ReactionsByEmoji] = [:]

	/// Everything recorded, as a render job reads it.
	var all: [String: ReactionsByEmoji] {
		reactionsByMessage
	}

	func reactions(forMessage messageIdentifier: String) -> ReactionsByEmoji? {
		reactionsByMessage[messageIdentifier]
	}

	/** Records `wireEmoji` from `nickname`, and returns every reaction the
	 message now carries — what a drawn row is updated with. `nil` where the
	 reaction was refused: an empty emoji after sanitising, one longer than the
	 cap, a nameless sender, or a message already answered by as many people as
	 one reaction records. */
	mutating func record(
		_ wireEmoji: String,
		from nickname: String,
		forMessage messageIdentifier: String
	) -> ReactionsByEmoji? {
		let emoji = TranscriptTextSanitizer.singleLine(wireEmoji)
		guard !emoji.isEmpty, emoji.utf16.count <= Self.maximumReactionLength,
		      !nickname.isEmpty, !messageIdentifier.isEmpty
		else {
			return nil
		}
		var reactions = reactionsByMessage[messageIdentifier] ?? [:]
		var nicknames = reactions[emoji] ?? []
		guard nicknames.count < Self.maximumReactorsPerReaction || nicknames.contains(nickname) else { return nil }
		if !nicknames.contains(nickname) {
			nicknames.append(nickname)
		}
		reactions[emoji] = nicknames
		reactionsByMessage[messageIdentifier] = reactions
		return reactions
	}

	/// Drops what `identifiers` recorded, except where the transcript still
	/// holds a row for the message.
	mutating func forget(_ identifiers: [String], stillHeld: (String) -> Bool) {
		for identifier in identifiers where reactionsByMessage[identifier] != nil {
			guard stillHeld(identifier) == false else { continue }
			reactionsByMessage.removeValue(forKey: identifier)
		}
	}

	mutating func removeAll() {
		reactionsByMessage.removeAll()
	}
}
