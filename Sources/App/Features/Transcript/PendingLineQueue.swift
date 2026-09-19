// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The lines that have been handed to a render and not applied to a view yet,
 in the order they were printed.

 Lines are applied in the order they were printed, so the one being withdrawn is
 almost always the first still waiting: withdrawing it moves a head rather than
 shifting every line behind it, and the storage is compacted once the head is
 past half of it. */
nonisolated struct PendingLineQueue: Sendable {
	private var storage: [ChatLine] = []
	private var head = 0

	/// The lines still waiting, oldest first.
	var lines: ArraySlice<ChatLine> {
		storage[head...]
	}

	mutating func append(_ chatLine: ChatLine) {
		storage.append(chatLine)
	}

	mutating func withdraw(_ chatLine: ChatLine) {
		if head < storage.count, storage[head].uniqueIdentifier == chatLine.uniqueIdentifier {
			head += 1
			if head * 2 >= storage.count {
				storage.removeFirst(head)
				head = 0
			}
			return
		}
		storage.removeFirst(head)
		head = 0
		storage.removeAll { $0.uniqueIdentifier == chatLine.uniqueIdentifier }
	}

	mutating func removeAll() {
		storage.removeAll()
		head = 0
	}
}
