// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Reads the lines of `draft/multiline` batches as the messages they are.

 A batch of that type carries one message cut into `PRIVMSG` or `NOTICE` lines:
 each line is a new line of text, except one tagged `draft/multiline-concat`,
 which continues the line before it. The assembler takes a queue of messages in
 arrival order and answers it with every such batch replaced by a single
 message, in the place its first line held, so what is replayed afterwards
 never sees the lines.

 The combined message is the first line with the joined text, and takes the
 tags the batch's own `BATCH +` line carries, which is where the server puts
 the message's identifier, time and account. It keeps the batch it belongs to,
 so a label on the batch, a history page around it or a netsplit wrapping it
 still reach it. */
enum MultilineAssembler {
	/// The most text one assembled message holds. Lines past it are replayed
	/// as the lines they are, rather than as one very large message.
	static let maximumPayloadBytes = 64 * 1024

	private struct Group {
		let index: Int
		let batch: MessageBatch
		var lines: [String]
		var bytes: Int
		var concatenated: [Bool]
		/// Set at the first line that does not belong: from there on the
		/// batch is malformed, and what follows is replayed as it came.
		var isClosed = false
	}

	static func assemble(_ messages: [Message]) -> [Message] {
		var output: [Message] = []
		var groups: [ObjectIdentifier: Group] = [:]
		var order: [ObjectIdentifier] = []

		for message in messages {
			guard let batch = message.parentBatchMessage, batch.kind == .multiline,
			      message.remoteCommand == .privmsg || message.remoteCommand == .notice,
			      message.params.count >= 2
			else {
				output.append(message)
				continue
			}

			let key = ObjectIdentifier(batch)
			let text = message.params[1]
			let continues = message.messageTags?[MultilineLimits.concatTag] != nil

			guard var group = groups[key] else {
				groups[key] = Group(
					index: output.count,
					batch: batch,
					lines: [text],
					bytes: text.utf8.count,
					concatenated: [false]
				)
				order.append(key)
				output.append(message)
				continue
			}

			guard group.isClosed == false else {
				output.append(message)
				continue
			}

			let first = output[group.index]
			let sameMessage = message.remoteCommand == first.remoteCommand
				&& message.params[0] == first.params[0]
				&& message.senderNickname == first.senderNickname
			let added = text.utf8.count + (continues ? 0 : 1)

			guard sameMessage, group.bytes + added <= maximumPayloadBytes else {
				group.isClosed = true
				groups[key] = group
				output.append(message)
				continue
			}

			group.lines.append(text)
			group.concatenated.append(continues)
			group.bytes += added
			groups[key] = group
		}

		/* Every group is combined, one line included: the message's identifier,
		 time and account sit on the opening line of the batch, never on the
		 line inside it, and a batch holding a single line is still a batch. */
		for key in order {
			guard let group = groups[key] else { continue }

			output[group.index] = combined(first: output[group.index], group: group)
		}

		return output
	}

	private static func combined(first: Message, group: Group) -> Message {
		var message = first
		var text = ""

		for (index, line) in group.lines.enumerated() {
			if index > 0, group.concatenated[index] == false {
				text.append("\n")
			}

			text.append(line)
		}

		message.params[1] = text

		var tags = first.messageTags ?? [:]
		tags.removeValue(forKey: MultilineLimits.concatTag)

		if let opening = group.batch.openingMessage {
			tags.merge(opening.messageTags ?? [:]) { _, opened in opened }
			tags.removeValue(forKey: "label")
			message.messageIdentifier = opening.messageIdentifier ?? message.messageIdentifier
			message.senderAccount = opening.senderAccount ?? message.senderAccount

			if opening.hasServerTime {
				message.receivedAt = opening.receivedAt
				message.hasServerTime = true
			}
		}

		tags["batch"] = group.batch.batchToken
		message.messageTags = tags

		return message
	}
}
