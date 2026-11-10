// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Synchronization

/** How many CPU-bound renders may run at once across every transcript.

 Each transcript's pipeline already bounds its own renders, but a window with
 many conversations multiplies that bound, and rendering is not free to run
 wide: link detection shares state inside Foundation, so a line costs about
 twice as much of the CPU with four renders running and about two and a half
 times with eight, while throughput stops improving at four. A shared budget
 keeps the machine at the width that finishes the most lines.

 A slot covers one render and nothing else. It is released before a job waits
 for the lines ahead of it or for the main actor, so a job holding a slot is
 never waiting on one that needs a slot to finish. Waiters are served in the
 order they asked, which keeps one busy conversation from holding off the rest. */
final nonisolated class RenderConcurrencyLimit: Sendable { // nonisolated: guarded
	/// The budget every transcript in the application shares.
	static let shared = RenderConcurrencyLimit(
		capacity: min(4, max(1, ProcessInfo.processInfo.activeProcessorCount))
	)

	private struct Waiter {
		let identifier: UInt64
		let continuation: CheckedContinuation<Bool, Never>
	}

	private struct State {
		var available: Int
		var nextIdentifier: UInt64 = 0
		var waiters: [Waiter] = []
	}

	private let state: Mutex<State>

	init(capacity: Int) {
		precondition(capacity > 0)
		state = Mutex(State(available: capacity))
	}

	/** Waits for a slot. Returns `false`, holding nothing, when the caller was
	 cancelled first; a caller that gets `true` must call ``release()``. */
	func acquire() async -> Bool {
		guard Task.isCancelled == false else { return false }
		let identifier = state.withLock { state -> UInt64 in
			state.nextIdentifier &+= 1
			return state.nextIdentifier
		}
		return await withTaskCancellationHandler {
			await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
				let granted = state.withLock { state -> Bool in
					if state.available > 0 {
						state.available -= 1
						return true
					}
					state.waiters.append(Waiter(identifier: identifier, continuation: continuation))
					return false
				}
				if granted {
					continuation.resume(returning: true)
				} else if Task.isCancelled {
					/* The handler may have run before the waiter was queued and
					 found nothing to remove. */
					cancelWaiter(identifier)
				}
			}
		} onCancel: {
			cancelWaiter(identifier)
		}
	}

	/// Slots free right now, and callers queued for one. Read by tests that have
	/// to wait for a caller to be parked before acting on it.
	var availableCount: Int {
		state.withLock { $0.available }
	}

	var waitingCount: Int {
		state.withLock { $0.waiters.count }
	}

	/// Gives the slot back, or hands it straight to the longest waiter.
	func release() {
		let next = state.withLock { state -> Waiter? in
			if state.waiters.isEmpty {
				state.available += 1
				return nil
			}
			return state.waiters.removeFirst()
		}
		next?.continuation.resume(returning: true)
	}

	private func cancelWaiter(_ identifier: UInt64) {
		let waiter = state.withLock { state -> Waiter? in
			guard let index = state.waiters.firstIndex(where: { $0.identifier == identifier }) else { return nil }
			return state.waiters.remove(at: index)
		}
		waiter?.continuation.resume(returning: false)
	}
}
