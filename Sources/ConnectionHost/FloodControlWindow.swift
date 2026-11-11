// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/** The pacing rule the two flood-control settings state: at most `capacity`
 lines in any span of `interval`.

 A sliding log of the last sends enforces exactly that. A counter reset on a
 fixed tick lets two full allowances out back to back across the tick, and a
 token bucket with the same burst and rate lets a burst, then a full refill,
 through one interval. The log holds at most `capacity` instants. */
nonisolated struct FloodControlWindow {
	let capacity: Int
	let interval: Duration

	/// When each admitted line went out, oldest first.
	private var sends: [ContinuousClock.Instant] = []

	/// `capacity` below one is raised to one, so a window always drains.
	init(capacity: Int, interval: Duration) {
		self.capacity = max(1, capacity)
		self.interval = interval
		sends.reserveCapacity(self.capacity)
	}

	/// The sends recorded and not yet forgotten, for inspection.
	var recordedCount: Int {
		sends.count
	}

	/// Whether a line may go out at `now`.
	func admits(at now: ContinuousClock.Instant) -> Bool {
		let horizon = now - interval
		return sends.count { $0 > horizon } < capacity
	}

	/// Notes a line that went out at `now`, forgetting the sends that have
	/// left the window.
	mutating func record(at now: ContinuousClock.Instant) {
		let horizon = now - interval
		sends.removeAll { $0 <= horizon }
		sends.append(now)
	}

	/// Gives back the slot of the most recent send, for a line that was put
	/// back on the queue rather than written.
	mutating func forgetLatest() {
		_ = sends.popLast()
	}

	/// When the next line may go out, or `nil` while fewer sends than the
	/// capacity are recorded. An instant already past means there is room now.
	func nextAdmission() -> ContinuousClock.Instant? {
		guard sends.count >= capacity else { return nil }
		// The send whose departure leaves exactly one free slot.
		return sends[sends.count - capacity] + interval
	}

	mutating func reset() {
		sends.removeAll(keepingCapacity: true)
	}
}
