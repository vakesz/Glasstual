// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** Greedy packing of an outbound list into the commands a server will take.

 Every list the session sends in pieces -- channels on a `JOIN`, nicknames on an
 `ISON`, capabilities on a `CAP REQ`, mode changes on a `MODE` -- is bounded the
 same two ways: how many items one command may carry, and how many bytes the
 line has left. What differs is what an item costs, and whether anything beyond
 those two ceilings closes a batch early. Both are the caller's.
 */
nonisolated enum WireBatching {
	/** `items` packed in order into as few batches as the ceilings allow.

	 - Parameters:
	   - maximumCount: The most items one batch carries; zero for no count
	     ceiling.
	   - budget: The bytes one batch has for its items, the separators between
	     them included; unbounded by default, for a list only the count limits.
	     An item that alone exceeds the budget still goes out in a batch of its
	     own rather than being dropped.
	   - closesBatch: A rule beyond the two ceilings — the batch so far cannot
	     also carry this item.
	   - cost: The bytes this item adds to the batch it is appended to, the
	     separator in front of it included. A batch is filled in order, so the
	     cost may depend on what is already in it.
	 */
	static func pack<Item>(
		_ items: some Sequence<Item>,
		maximumCount: Int = 0,
		budget: Int = .max,
		closesBatch: (Item, [Item]) -> Bool = { _, _ in false },
		cost: (Item, [Item]) -> Int = { _, _ in 0 }
	) -> [[Item]] {
		var batches: [[Item]] = []
		var current: [Item] = []
		var length = 0

		for item in items {
			let itemCost = cost(item, current)

			if current.isEmpty == false,
			   maximumCount > 0 && current.count >= maximumCount
			   || length + itemCost > budget
			   || closesBatch(item, current)
			{
				batches.append(current)
				current = []
				length = cost(item, [])
			} else {
				length += itemCost
			}

			current.append(item)
		}

		if current.isEmpty == false {
			batches.append(current)
		}

		return batches
	}

	/// Splits `targets` into lists of at most `limit` entries, in order.
	///
	/// Zero is a server that advertised no limit, and it chunks the same way as
	/// one: a target list the server never said it accepts is not sent.
	static func chunkTargets(_ targets: [String], limit: UInt) -> [[String]] {
		pack(targets, maximumCount: max(Int(min(limit, UInt(targets.count))), 1))
	}

	/** A list of single-token parameters packed into one command's worth each.

	 `ISON`, `WATCH` and `MONITOR` all take a list the user's address book
	 decides the length of, and a list long enough overruns either the fifteen
	 parameters RFC 1459 allows or the 512 bytes the line has. Both are the same
	 split, so both use this one.

	 - Parameters:
	   - tokens: The tokens to spread over commands. Empty ones are dropped:
	     they cannot survive as their own wire token anyway.
	   - maximumCount: The most parameters one command takes.
	   - budget: The bytes one command has for its parameters, the spaces
	     between them included.
	 */
	static func packTokens(
		_ tokens: [String],
		maximumCount: Int = 0,
		budget: Int = .max
	) -> [[String]] {
		pack(
			tokens.filter { $0.isEmpty == false },
			maximumCount: maximumCount,
			budget: budget,
			cost: { token, batch in
				(batch.isEmpty ? 0 : 1) + token.utf8.count
			}
		)
	}
}
