/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Synchronization
import Testing

/// Records where, and in what order, a seam delivered its callbacks.
///
/// The two properties that break silently at asynchronous boundaries are
/// ordering (the render pipeline must stay FIFO per view; a historic-log fetch
/// must not overtake its predecessor) and destination (results must land on
/// the main actor, work must not). A test
/// hands a probe to the seam, the seam calls ``record(_:)`` at each delivery,
/// and the test then reads back a list it can compare against.
///
/// The probe is `Sendable` so it can be captured by whatever closure or actor
/// the seam delivers through; its storage is a `Mutex` around a value, which is
/// the one form of lock the isolation rules allow.
final class IsolationProbe: Sendable {
	/// One delivery: what happened, and which domain saw it.
	struct Observation: Sendable, Equatable {
		let label: String
		let onMainActor: Bool
	}

	private let storage = Mutex<[Observation]>([])

	init() {}

	/// Appends an observation tagged with the caller's isolation domain.
	///
	/// `isolation` is never passed explicitly: its `#isolation` default is what
	/// carries the caller's domain in.
	func record(_ label: String, isolation: isolated (any Actor)? = #isolation) async {
		let observation = Observation(label: label, onMainActor: isMainActor(isolation))

		storage.withLock { $0.append(observation) }
	}

	/// Every observation, oldest first.
	var observations: [Observation] {
		storage.withLock { $0 }
	}

	/// The labels alone, oldest first -- the usual thing an ordering test wants.
	var labels: [String] {
		observations.map(\.label)
	}

	func clear() {
		storage.withLock { $0.removeAll() }
	}

	/// Checks that the deliveries arrived in exactly this order.
	func expectOrder(_ expected: [String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(labels == expected, sourceLocation: sourceLocation)
	}

	/// Checks that every delivery so far reached the main actor.
	func expectAllOnMainActor(sourceLocation: SourceLocation = #_sourceLocation) {
		let strays = observations.filter { !$0.onMainActor }.map(\.label)

		#expect(strays.isEmpty, "these deliveries missed the main actor: \(strays)", sourceLocation: sourceLocation)
	}

	/// Checks that no delivery so far reached the main actor.
	func expectNoneOnMainActor(sourceLocation: SourceLocation = #_sourceLocation) {
		let strays = observations.filter(\.onMainActor).map(\.label)

		#expect(strays.isEmpty, "these deliveries ran on the main actor: \(strays)", sourceLocation: sourceLocation)
	}
}
