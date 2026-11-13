// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// The acknowledgements are read in the About panel's credits rather than
/// opened in another application.
@MainActor
@Suite("About panel credits")
struct AboutCreditsTests {
	@Test("The credits carry the acknowledgements under their heading")
	func creditsCarryTheAcknowledgements() {
		let credits = AboutCredits.make(acknowledgements: "  Portions © Someone.\n").string

		#expect(credits.contains(String(localized: .About.acknowledgementsButton)))
		#expect(credits.hasSuffix("Portions © Someone."))
		#expect(credits.contains(String(localized: .About.privacyPolicyLink)))
	}

	@Test("With no acknowledgements there is no heading over nothing")
	func noAcknowledgementsNoHeading() {
		for text in [nil, "", " \n "] as [String?] {
			let credits = AboutCredits.make(acknowledgements: text).string
			#expect(credits.contains(String(localized: .About.acknowledgementsButton)) == false)
			#expect(credits.contains(String(localized: .About.supportLink)))
		}
	}

	@Test("The bundled acknowledgements document has text to show")
	func bundledAcknowledgementsAreReadable() {
		#expect(AboutCredits.make().string.contains(String(localized: .About.acknowledgementsButton)))
	}
}
