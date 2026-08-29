/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Testing

/// A domain that is definitely not the main actor, so the helpers can be shown
/// to distinguish the two rather than to always agree.
private actor Bystander {
	func check() async {
		await expectMainActor()
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
	func expectMainActorRejectsAnotherActor() async {
		await withKnownIssue("expectMainActor() has to notice a caller on some other actor") {
			await Bystander().check()
		}
	}

	@Test
	func expectOffMainActorRejectsTheMainActor() async {
		await withKnownIssue("expectOffMainActor() has to notice a caller on the main actor") {
			await expectOffMainActor()
		}
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
