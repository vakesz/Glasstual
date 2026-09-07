/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Synchronization

/// NSXPC cannot suspend a one-way callback. Bound its admitted data and fail
/// explicitly after the accepted prefix instead of silently dropping IRC lines.
final nonisolated class ConnectionInputBudget: Sendable { // nonisolated: immutable
	enum Admission {
		case accepted
		case overflow
		case closed
	}

	struct State: Sendable {
		var bytes = 0
		var entries = 0
		var peakBytes = 0
		var failed = false
	}

	static let maximumBytes = 8 * 1024 * 1024
	static let maximumEntries = 8192
	private let state = Mutex(State())

	func admit(bytes: Int) -> Admission {
		state.withLock {
			guard $0.failed == false else { return .closed }
			guard bytes <= Self.maximumBytes - $0.bytes, $0.entries < Self.maximumEntries else {
				$0.failed = true
				return .overflow
			}
			$0.bytes += bytes
			$0.entries += 1
			$0.peakBytes = max($0.peakBytes, $0.bytes)
			return .accepted
		}
	}

	func consumed(bytes: Int) {
		state.withLock {
			$0.bytes -= bytes
			$0.entries -= 1
		}
	}

	var snapshot: State {
		state.withLock { $0 }
	}
}
