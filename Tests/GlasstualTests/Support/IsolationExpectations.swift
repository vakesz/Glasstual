/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Testing

/// Records a test failure unless the caller is running on the main actor.
///
/// Phase 8 moves work between isolation domains, and the interesting mistakes
/// are the ones the compiler cannot see: a callback that arrives on a global
/// executor, an actor method that hands a result back on the wrong domain.
/// This is the runtime half of the check.
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
		isMainActor(isolation),
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
		!isMainActor(isolation),
		comment ?? "expected any domain but the main actor",
		sourceLocation: sourceLocation
	)
}

func isMainActor(_ isolation: (any Actor)?) -> Bool {
	guard let isolation else {
		return false
	}

	return isolation === (MainActor.shared as any Actor)
}

func describeIsolation(_ isolation: (any Actor)?) -> String {
	guard let isolation else {
		return "no actor (a nonisolated context)"
	}

	return String(describing: type(of: isolation))
}
