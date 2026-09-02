/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/** Transcript zoom is a multiplier the window keeps and hands to every log
 controller. Its only rule is the clamp: a step that would leave the allowed
 range is refused outright rather than pinned to the edge, so the multiplier the
 controllers are given never leaves 0.5 ... 3.0 and never drifts by a partial
 step at the boundary. */
@MainActor
@Suite("Main window text zoom", .serialized)
struct MainWindowTextZoomTests {
	private func window() -> MainWindow {
		MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
	}

	@Test("A window starts at the unscaled size")
	func startsUnscaled() {
		#expect(window().textSizeMultiplier == 1.0)
	}

	@Test("Each step multiplies or divides by the same factor")
	func stepsAreMultiplicative() {
		let window = window()

		window.changeTextSize(true)
		#expect(window.textSizeMultiplier == 1.2)

		window.changeTextSize(true)
		#expect(abs(window.textSizeMultiplier - 1.44) < 0.000_001)

		window.changeTextSize(false)
		#expect(abs(window.textSizeMultiplier - 1.2) < 0.000_001)
	}

	/// The step that would leave the range is refused whole: the multiplier
	/// stays where it was rather than being clamped to the boundary.
	@Test("A step past either end of the range changes nothing")
	func stepsPastTheRangeAreRefused() {
		let bigger = window()
		while bigger.textSizeMultiplier < 3.0 {
			let before = bigger.textSizeMultiplier
			bigger.changeTextSize(true)
			if bigger.textSizeMultiplier == before {
				break
			}
		}

		let largest = bigger.textSizeMultiplier
		#expect(largest <= 3.0)
		bigger.changeTextSize(true)
		#expect(bigger.textSizeMultiplier == largest)

		let smaller = window()
		while smaller.textSizeMultiplier > 0.5 {
			let before = smaller.textSizeMultiplier
			smaller.changeTextSize(false)
			if smaller.textSizeMultiplier == before {
				break
			}
		}

		let smallest = smaller.textSizeMultiplier
		#expect(smallest >= 0.5)
		smaller.changeTextSize(false)
		#expect(smaller.textSizeMultiplier == smallest)
	}
}
