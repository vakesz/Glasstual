// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Testing

/// A domain that is definitely not the main actor, so the helpers can be shown
/// to distinguish the two rather than to always agree.
private actor Bystander {
	func isOnMainActor() -> Bool {
		isolationIsMainActor(#isolation)
	}

	func record(_ label: String, into probe: IsolationProbe) async {
		await probe.record(label)
	}
}

/// Every test that asserts a delivery domain trusts these helpers, so one
/// test has to show they can tell the main actor from another actor: a helper
/// that always agreed would make all of those vacuous.
@MainActor
@Suite("Isolation testing helpers")
struct IsolationTestingTests {
	@Test("The helpers tell the main actor from another actor and keep delivery order")
	func helpersDistinguishTheMainActorFromAnotherActor() async {
		await expectMainActor()
		#expect(await Bystander().isOnMainActor() == false)

		let probe = IsolationProbe()

		await probe.record("first")
		await Bystander().record("second", into: probe)
		await probe.record("third")

		probe.expectOrder(["first", "second", "third"])
		#expect(probe.observations.map(\.onMainActor) == [true, false, true])
	}
}
