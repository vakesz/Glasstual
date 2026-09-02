/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** Settings -> IRCv3 lists one switch per capability the client negotiates on
 its own. A capability without a summary would be a wire name and a switch with
 nothing to say what turning it off costs, and one without a specification
 would leave the user no way to look it up, so the registry has to carry both
 for every capability the pane shows. */
@MainActor
@Suite("IRCv3 capability listing")
struct PreferencesIRCv3CapabilityListingTests {
	/// What the pane lists: everything negotiated automatically. A capability
	/// with a preference of its own keeps that switch instead, which is what
	/// keeps the draft and final spellings of one feature to one control.
	private var switchableCapabilities: [Capability] {
		CapabilityRegistry.defaultRegistry.capabilities.filter { $0.preference == .always }
	}

	@Test("Every capability the pane switches carries a summary")
	func everySwitchableCapabilityHasASummary() {
		for capability in switchableCapabilities {
			let summary = PreferencesIRCv3Strings.capabilitySummary(for: capability.name)

			#expect(summary?.isEmpty == false, "\(capability.name) has no summary")
		}
	}

	@Test("Every capability the pane switches links to the document that defines it")
	func everySwitchableCapabilityHasASpecification() {
		for capability in switchableCapabilities {
			guard let specification = capability.specification else {
				Issue.record("\(capability.name) has no specification")
				continue
			}

			#expect(specification.scheme == "https", "\(capability.name) is not linked over https")
			#expect(specification.host()?.isEmpty == false, "\(capability.name) has no host")
		}
	}

	@Test("The paired draft and final spellings of a feature stay out of the list")
	func preferenceGatedCapabilitiesAreNotListed() {
		let listed = Set(switchableCapabilities.map(\.name))

		for name in ["draft/chathistory", "chathistory", "draft/read-marker", "read-marker", "echo-message"] {
			#expect(listed.contains(name) == false, "\(name) has a preference of its own")
		}
	}

	@Test("A name the registry does not declare has no summary")
	func unknownCapabilitiesHaveNoSummary() {
		#expect(PreferencesIRCv3Strings.capabilitySummary(for: "example.com/vendor") == nil)
		/* Capability names are case-sensitive, and so is the lookup. */
		#expect(PreferencesIRCv3Strings.capabilitySummary(for: "Away-Notify") == nil)
	}

	@Test("The summary reads as its own sentence beside the wire name")
	func summariesAreSentences() throws {
		let summary = try #require(PreferencesIRCv3Strings.capabilitySummary(for: "away-notify"))

		#expect(summary.hasSuffix("."))
		#expect(summary.contains("away"))
		#expect(
			PreferencesIRCv3Strings.capabilityAccessibilityLabel(name: "away-notify", summary: summary)
				== "away-notify. \(summary)"
		)
	}
}
