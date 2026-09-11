/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// The history buffer is capped, and dropping its oldest entry moves every
/// index -- the cursor the arrow keys walk included.
@Suite("Input history buffer")
@MainActor
struct InputHistoryBufferTests {
	private static let channelSpecificKey = "SaveInputHistoryPerSelection"
	/// `inputHistoryMaximumCount` in `InputHistory.swift`.
	private static let maximumCount = 100

	private func makeHistory() -> InputHistory {
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		return InputHistory(window: window)
	}

	/// The suite runs against the scheme's scratch defaults, so the original
	/// value is restored rather than left behind.
	private func withGlobalHistory(_ body: (InputHistory) -> Void) {
		let defaults = TextualUserDefaults.container
		let original = defaults.persistedObject(forKey: Self.channelSpecificKey)
		defer {
			if let original {
				defaults.set(original, forKey: Self.channelSpecificKey)
			} else {
				defaults.removeObject(forKey: Self.channelSpecificKey)
			}
		}

		defaults.set(false, forKey: Self.channelSpecificKey)
		body(makeHistory())
	}

	private func fill(_ history: InputHistory, count: Int) {
		for index in 1 ... count {
			history.add(NSAttributedString(string: "line \(index)"))
		}
	}

	/** The regression. At a full buffer the draft being stashed pushed the
	 oldest entry out, every index moved down by one, and the cursor did not:
	 the first press of Up handed back the draft that had just been typed. */
	@Test("The first press of Up at a full buffer returns the last entry, not the draft")
	func fullBufferDoesNotReturnTheDraft() {
		withGlobalHistory { history in
			fill(history, count: Self.maximumCount)

			let first = history.up(NSAttributedString(string: "draft"))

			#expect(first?.string == "line 100")
		}
	}

	@Test("Walking back from a full buffer stays in step")
	func fullBufferWalksBackInOrder() {
		withGlobalHistory { history in
			fill(history, count: Self.maximumCount)

			#expect(history.up(NSAttributedString(string: "draft"))?.string == "line 100")
			#expect(history.up(NSAttributedString(string: "line 100"))?.string == "line 99")
			#expect(history.up(NSAttributedString(string: "line 99"))?.string == "line 98")
		}
	}

	/// A buffer that never overflowed was always correct; the fix must not
	/// change it.
	@Test("A buffer below the cap is unchanged")
	func shortBufferWalksBackInOrder() {
		withGlobalHistory { history in
			fill(history, count: 3)

			#expect(history.up(NSAttributedString(string: "draft"))?.string == "line 3")
			#expect(history.up(NSAttributedString(string: "line 3"))?.string == "line 2")
		}
	}

	/// Down from the stashed draft walks forward again rather than repeating
	/// the entry Up just handed over.
	@Test("Down returns to the draft that Up stashed")
	func downReturnsToTheDraft() {
		withGlobalHistory { history in
			fill(history, count: Self.maximumCount)

			#expect(history.up(NSAttributedString(string: "draft"))?.string == "line 100")
			#expect(history.down(NSAttributedString(string: "line 100"))?.string == "draft")
		}
	}
}
