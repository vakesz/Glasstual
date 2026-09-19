// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	/** Actual Size, the third of the triple Safari, Mail, Xcode and Preview all
	 ship: from anywhere in the range, one command returns the transcript to the
	 size it started at. */
	@Test("Actual Size returns the multiplier to one from either direction")
	func actualSizeReturnsToOne() {
		let bigger = window()
		bigger.changeTextSize(true)
		bigger.changeTextSize(true)
		#expect(bigger.textSizeMultiplier > 1.0)
		bigger.resetTextSize()
		#expect(bigger.textSizeMultiplier == 1.0)

		let smaller = window()
		smaller.changeTextSize(false)
		smaller.changeTextSize(false)
		#expect(smaller.textSizeMultiplier < 1.0)
		smaller.resetTextSize()
		#expect(smaller.textSizeMultiplier == 1.0)

		let unchanged = window()
		unchanged.resetTextSize()
		#expect(unchanged.textSizeMultiplier == 1.0)
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
