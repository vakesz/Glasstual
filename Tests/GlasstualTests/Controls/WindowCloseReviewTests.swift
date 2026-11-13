// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** The close review stands in front of the delegate SwiftUI keeps on a window:
 it decides closing from its owner's policy and passes every other message on
 to that delegate, and only the messages that delegate answers. */
@MainActor
@Suite("Window close review")
struct WindowCloseReviewTests {
	/// A delegate that answers closing, resizing and becoming key, as SwiftUI's does.
	private final class StandIn: NSObject, NSWindowDelegate {
		var shouldClose = true
		var closeQuestions = 0
		var resizes = 0
		var willClose = 0

		func windowShouldClose(_: NSWindow) -> Bool {
			closeQuestions += 1
			return shouldClose
		}

		func windowDidResize(_: Notification) {
			resizes += 1
		}

		func windowWillClose(_: Notification) {
			willClose += 1
		}
	}

	private static func window() -> NSWindow {
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
			styleMask: [.titled, .closable],
			backing: .buffered,
			defer: true
		)
		window.isReleasedWhenClosed = false
		return window
	}

	@Test("With nothing to lose, the window's own delegate decides")
	func closesAsksTheStandIn() {
		let window = Self.window()
		let standIn = StandIn()
		window.delegate = standIn
		let review = WindowCloseReview(window: window, policy: .closes)
		defer { review.uninstall() }
		var reviews = 0
		review.reviewRequested = { reviews += 1 }

		#expect(window.delegate === review)
		#expect(review.windowShouldClose(window))
		standIn.shouldClose = false
		#expect(review.windowShouldClose(window) == false)
		#expect(standIn.closeQuestions == 2)
		#expect(reviews == 0)
	}

	@Test("Edits keep the window open and raise the owner's question")
	func asksRaisesTheReview() {
		let window = Self.window()
		let standIn = StandIn()
		window.delegate = standIn
		let review = WindowCloseReview(window: window, policy: .asks)
		defer { review.uninstall() }
		var reviews = 0
		review.reviewRequested = { reviews += 1 }

		#expect(review.windowShouldClose(window) == false)
		#expect(reviews == 1)
		#expect(standIn.closeQuestions == 0)

		review.policy = .refuses
		#expect(review.windowShouldClose(window) == false)
		#expect(reviews == 1)
	}

	@Test("Only the messages the window's delegate answers are answered, and passed on")
	func forwardsWhatTheStandInAnswers() {
		let window = Self.window()
		let standIn = StandIn()
		window.delegate = standIn
		let review = WindowCloseReview(window: window, policy: .closes)
		defer { review.uninstall() }

		#expect(review.responds(to: #selector(NSWindowDelegate.windowDidResize(_:))))
		#expect(review.responds(to: #selector(NSWindowDelegate.windowShouldClose(_:))))
		/* An undo manager answered as nil would take undo away from the window's fields. */
		#expect(review.responds(to: #selector(NSWindowDelegate.windowWillReturnUndoManager(_:))) == false)
		#expect(review.responds(to: #selector(NSWindowDelegate.windowWillResize(_:to:))) == false)

		review.windowDidResize(Notification(name: NSWindow.didResizeNotification, object: window))
		#expect(standIn.resizes == 1)
	}

	@Test("Every message the review may pass on has a method to pass it")
	func everyForwardableMessageIsImplemented() {
		for selector in WindowCloseReview.forwardableSelectors {
			#expect(WindowCloseReview.instancesRespond(to: selector), "\(selector)")
		}
	}

	@Test("Closing gives the window back to its own delegate")
	func closingUninstalls() {
		let window = Self.window()
		let standIn = StandIn()
		window.delegate = standIn
		let review = WindowCloseReview(window: window, policy: .closes)

		review.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: window))

		#expect(standIn.willClose == 1)
		#expect(window.delegate === standIn)
		#expect(review.isInstalled == false)
	}
}
