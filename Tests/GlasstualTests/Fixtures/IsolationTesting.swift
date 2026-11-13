// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Synchronization
import Testing

/// Records a test failure unless the caller is running on the main actor.
///
/// The interesting mistakes are the ones the compiler cannot see: a callback
/// that arrives on a global executor, or an actor method that hands a result
/// back on the wrong domain. This is the runtime half of the check.
///
/// `MainActor.preconditionIsolated()` answers the same question by trapping,
/// which takes the rest of the suite down with it and reports a crash rather
/// than a named failure. The `isolation` parameter's `#isolation` default
/// carries the caller's isolation domain in as an ordinary value instead, so
/// the check reads it, compares it, and reports through Swift Testing.
///
/// The parameter is what makes this work: it is never passed explicitly.
///
/// ```swift
/// @Test func resultsArriveOnTheMainActor() async {
///     await sut.load()
///     await expectMainActor()
/// }
/// ```
func expectMainActor(
	_ comment: Comment? = nil,
	isolation: isolated (any Actor)? = #isolation,
	sourceLocation: SourceLocation = #_sourceLocation
) async {
	#expect(
		isolationIsMainActor(isolation),
		comment ?? "expected the main actor, ran on \(describeIsolation(isolation))",
		sourceLocation: sourceLocation
	)
}

/// Records a test failure when the caller *is* on the main actor.
///
/// The mirror of ``expectMainActor()``, for the seams whose whole point is that
/// they no longer block the main thread: a render pass, a socket read, an XPC
/// fetch. Asserting only the positive direction lets work quietly migrate back
/// onto the main actor without a test noticing.
func expectOffMainActor(
	_ comment: Comment? = nil,
	isolation: isolated (any Actor)? = #isolation,
	sourceLocation: SourceLocation = #_sourceLocation
) async {
	#expect(
		!isolationIsMainActor(isolation),
		comment ?? "expected any domain but the main actor",
		sourceLocation: sourceLocation
	)
}

nonisolated func isolationIsMainActor(_ isolation: (any Actor)?) -> Bool { // nonisolated: pure
	guard let isolation else {
		return false
	}

	return isolation === (MainActor.shared as any Actor)
}

private nonisolated func describeIsolation(_ isolation: (any Actor)?) -> String { // nonisolated: pure
	guard let isolation else {
		return "no actor (a nonisolated context)"
	}

	return String(describing: type(of: isolation))
}

/// Records where, and in what order, a seam delivered its callbacks.
///
/// The two properties that break silently at asynchronous boundaries are
/// ordering (the render pipeline must stay FIFO per view; a scrollback fetch
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
		let observation = Observation(label: label, onMainActor: isolationIsMainActor(isolation))

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

	/// Checks that the deliveries arrived in exactly this order.
	func expectOrder(_ expected: [String], sourceLocation: SourceLocation = #_sourceLocation) {
		#expect(labels == expected, sourceLocation: sourceLocation)
	}

	/// Checks that no delivery so far reached the main actor.
	func expectNoneOnMainActor(sourceLocation: SourceLocation = #_sourceLocation) {
		let strays = observations.filter(\.onMainActor).map(\.label)

		#expect(strays.isEmpty, "these deliveries ran on the main actor: \(strays)", sourceLocation: sourceLocation)
	}
}
