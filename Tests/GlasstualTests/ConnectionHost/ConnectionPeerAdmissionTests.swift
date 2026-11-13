// Copyright (c) 2017, 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Testing

@Suite("Connection host peer admission")
struct ConnectionPeerAdmissionTests {
	@Test("Without a requirement a build that allows no unverified peer refuses")
	func missingRequirementRefusesInRelease() {
		#expect(ConnectionPeerAdmission.decide(requirement: nil, allowsUnverifiedPeer: false) == .refuse)
	}

	@Test("Without a requirement a build that allows unverified peers accepts")
	func missingRequirementIsAcceptedInDebug() {
		#expect(ConnectionPeerAdmission.decide(requirement: nil, allowsUnverifiedPeer: true) == .acceptUnverified)
	}

	@Test("A requirement is always applied, whatever the build allows", arguments: [true, false])
	func requirementIsApplied(allowsUnverifiedPeer: Bool) {
		let requirement = "anchor apple generic and identifier \"com.example.app\""

		#expect(
			ConnectionPeerAdmission.decide(requirement: requirement, allowsUnverifiedPeer: allowsUnverifiedPeer)
				== .enforce(requirement: requirement)
		)
	}

	@Test("An empty requirement is still a requirement")
	func emptyRequirementIsEnforced() {
		#expect(ConnectionPeerAdmission.decide(requirement: "", allowsUnverifiedPeer: true) == .enforce(requirement: ""))
	}
}
