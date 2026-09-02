/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Input bar height policy")
struct MainWindowInputBarHeightPolicyTests {
	/// The ceiling used to be derived from the bar's own minimum-height
	/// constraint, which made it `windowHeight - 35`: a pasted message could
	/// grow the bar over the whole transcript.
	@Test("The bar is capped well below the window it sits in")
	func maximumHeightLeavesTheTranscriptItsShare() {
		let maximum = MainWindowInputBarHeightPolicy.maximumHeight(windowHeight: 800, padding: 12)

		#expect(maximum < 800 * 0.5)
		#expect(maximum > 0)
		#expect(maximum == (800 * MainWindowInputBarHeightPolicy.maximumWindowHeightFraction) - 12)
	}

	@Test("The ceiling grows with the window")
	func maximumHeightScalesWithTheWindow() {
		let small = MainWindowInputBarHeightPolicy.maximumHeight(windowHeight: 500, padding: 12)
		let large = MainWindowInputBarHeightPolicy.maximumHeight(windowHeight: 1200, padding: 12)

		#expect(large > small)
	}

	/// A window shorter than the padding must not produce a negative ceiling:
	/// the growth search would then never find a height to settle on.
	@Test("A window too short for the padding yields no room rather than negative room")
	func maximumHeightNeverGoesNegative() {
		#expect(MainWindowInputBarHeightPolicy.maximumHeight(windowHeight: 10, padding: 40) == 0)
	}
}
