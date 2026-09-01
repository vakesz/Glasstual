/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Testing

/// A domain that is definitely not the main actor, so the helpers can be shown
/// to distinguish the two rather than to always agree.
private actor Bystander {
	func isOnMainActor() -> Bool {
		isMainActor(#isolation)
	}

	func record(_ label: String, into probe: IsolationProbe) async {
		await probe.record(label)
	}
}

@MainActor
struct IsolationSupportTests {
	@Test
	func expectMainActorAcceptsTheMainActor() async {
		await expectMainActor()
	}

	@Test
	func mainActorPredicateRejectsAnotherActor() async {
		#expect(await Bystander().isOnMainActor() == false)
	}

	@Test
	func mainActorPredicateAcceptsTheMainActor() {
		#expect(currentIsolationIsMainActor())
	}

	@Test
	func probeRecordsDeliveryOrderAndDomain() async {
		let probe = IsolationProbe()

		await probe.record("first")
		await Bystander().record("second", into: probe)
		await probe.record("third")

		probe.expectOrder(["first", "second", "third"])
		#expect(probe.observations.map(\.onMainActor) == [true, false, true])
	}

	@Test
	func probeClearsItsHistory() async {
		let probe = IsolationProbe()

		await probe.record("stale")
		probe.clear()

		#expect(probe.labels.isEmpty)
	}
}

private func currentIsolationIsMainActor(
	isolation: isolated (any Actor)? = #isolation
) -> Bool {
	isMainActor(isolation)
}
