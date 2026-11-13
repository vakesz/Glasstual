// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The host's two wire-order classes. Bypass writes overtake queued ordinary
/// writes, but retain their own order. A write the transport did not accept
/// stays first even if more bypass writes arrived while it was in flight.
nonisolated struct ConnectionHostSendQueue {
	struct Entry: Sendable {
		let data: Data
		let bypassesFloodControl: Bool
	}

	private var bypass = FIFO()
	private var ordinary = FIFO()
	private var retry: Entry?
	private(set) var clearGeneration: UInt64 = 0

	var isEmpty: Bool {
		retry == nil && bypass.isEmpty && ordinary.isEmpty
	}

	var firstBypassesFloodControl: Bool {
		if let retry {
			return retry.bypassesFloodControl
		}
		return bypass.isEmpty == false
	}

	mutating func append(_ data: Data, bypassingFloodControl: Bool) {
		if bypassingFloodControl {
			bypass.append(data)
		} else {
			ordinary.append(data)
		}
	}

	mutating func takeFirst() -> Entry? {
		if let retry {
			self.retry = nil
			return retry
		}
		if let data = bypass.takeFirst() {
			return Entry(data: data, bypassesFloodControl: true)
		}
		return ordinary.takeFirst().map { Entry(data: $0, bypassesFloodControl: false) }
	}

	mutating func putBack(_ entry: Entry) {
		precondition(retry == nil)
		retry = entry
	}

	mutating func removeAll() {
		bypass.removeAll()
		ordinary.removeAll()
		retry = nil
		clearGeneration &+= 1
	}

	/// Popping advances a head instead of shifting every queued line. Compact
	/// only after at least half the storage has been consumed, so the total
	/// copying over any run of dequeues stays proportional to its writes.
	private struct FIFO {
		private var elements: [Data] = []
		private var head = 0

		var isEmpty: Bool {
			head == elements.count
		}

		mutating func append(_ data: Data) {
			elements.append(data)
		}

		mutating func takeFirst() -> Data? {
			guard head < elements.count else { return nil }
			let data = elements[head]
			head += 1
			if head == elements.count {
				removeAll()
			} else if head >= 64, head * 2 >= elements.count {
				elements.removeFirst(head)
				head = 0
			}
			return data
		}

		mutating func removeAll() {
			// Reuse small queues; release storage from a completed burst.
			elements.removeAll(keepingCapacity: elements.capacity <= 512)
			head = 0
		}
	}
}
