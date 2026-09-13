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
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

/** Greedy packing of an outbound list into the commands a server will take.

 Every list the client sends in pieces -- channels on a `JOIN`, nicknames on an
 `ISON`, capabilities on a `CAP REQ`, mode changes on a `MODE` -- is bounded the
 same two ways: how many items one command may carry, and how many bytes the
 line has left. What differs is what an item costs, and whether anything beyond
 those two ceilings closes a batch early. Both are the caller's.
 */
nonisolated enum WireBatching { // nonisolated: value
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
}
