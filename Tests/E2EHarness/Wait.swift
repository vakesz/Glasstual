import Foundation
import Synchronization

/// Why a run, scenario or step stopped. Messages carry only harness-authored
/// text: never wire payloads, settings values or secrets.
enum HarnessFailure: Error, CustomStringConvertible {
	/// The machine or build cannot run the suite. Exit status 2.
	case setup(String)
	/// The application or a peer did something other than expected.
	case assertion(String)
	/// A bounded wait ran out.
	case timeout(String)

	var description: String {
		switch self {
		case let .setup(message): message
		case let .assertion(message): message
		case let .timeout(step): "Timed out: \(step)"
		}
	}
}

/// A monotonic point in time a step has to finish by.
struct Deadline {
	let end: ContinuousClock.Instant

	init(after duration: Duration) {
		end = .now + duration
	}

	var remaining: Duration {
		max(.zero, end - .now)
	}

	var hasPassed: Bool {
		ContinuousClock.now >= end
	}
}

/** Counts changes the application reports through `AXObserver`, so a wait can
 re-evaluate as soon as something happened instead of at its next poll.

 The observer's callback is a C function the run loop calls, so the count is
 guarded rather than owned by the main actor. */
final nonisolated class ChangeSignal: Sendable { // nonisolated: guarded
	private let count = Mutex(0)

	var generation: Int {
		count.withLock { $0 }
	}

	func notify() {
		count.withLock { $0 &+= 1 }
	}
}

/// A transient Accessibility error: the application was busy or an element
/// went away between a lookup and a read. A wait retries it.
struct TransientAXError: Error {
	let code: Int32
}

/// The one way the harness waits for anything.
enum Wait {
	/** The one way the harness waits for anything.

	 `probe` runs until it returns a value or `timeout` passes. Transient AX errors
	 count as "not yet". Between evaluations the wait sleeps a bounded, growing
	 interval, and wakes early when `signal` reports an Accessibility notification.
	 Cancellation, which is how the scenario watchdog stops a run that is over its
	 budget, ends the wait at once. */
	static func until<Value>(
		_ description: String,
		timeout: Duration = .seconds(20),
		signal: ChangeSignal? = nil,
		_ probe: () throws -> Value?
	) async throws -> Value {
		let deadline = Deadline(after: timeout)
		var interval = Duration.milliseconds(20)
		while true {
			try Task.checkCancellation()
			do {
				if let value = try probe() {
					return value
				}
			} catch is TransientAXError {
				// Not yet: the next evaluation asks again.
			}
			guard deadline.hasPassed == false else {
				throw HarnessFailure.timeout(description)
			}
			let generation = signal?.generation
			let wake = ContinuousClock.now + min(interval, deadline.remaining)
			while ContinuousClock.now < wake {
				try await Task.sleep(for: .milliseconds(10))
				if let generation, signal?.generation != generation {
					break
				}
			}
			interval = min(interval * 2, .milliseconds(250))
		}
	}

	/// `until` for a condition with no value to hand back.
	static func until(
		_ description: String,
		timeout: Duration = .seconds(20),
		signal: ChangeSignal? = nil,
		_ condition: () throws -> Bool
	) async throws {
		_ = try await until(description, timeout: timeout, signal: signal) { try condition() ? true : nil }
	}
}

extension Duration {
	/// Seconds as a `Double`, for printing and comparisons with thresholds.
	var inSeconds: Double {
		let (whole, attoseconds) = components
		return Double(whole) + Double(attoseconds) / 1e18
	}
}
