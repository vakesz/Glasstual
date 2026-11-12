// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import SwiftUI

/// What closing a window does, as the window's owner last said.
enum WindowClosePolicy: Equatable {
	/// Nothing is lost by closing.
	case closes
	/// Closing would lose something, so the owner asks first.
	case asks
	/// The window is busy finishing something and stays open.
	case refuses
}

/** The AppKit adapter that answers `windowShouldClose(_:)` for a SwiftUI window,
 from the policy its owner keeps up to date.

 SwiftUI keeps a delegate of its own on the window, so this one stands in front
 of it and passes on every delegate message that one answers, and nothing else.
 Every way of closing goes through here: the close button, File ▸ Close and
 anything else that performs a close. When the policy asks, the window stays
 open and the owner raises its question; ``close()`` then closes without asking
 again. */
final class WindowCloseReview: NSObject, NSWindowDelegate {
	/// The owner's answer to whether the window may close, refreshed as it changes.
	var policy: WindowClosePolicy
	/// Raised when closing needs the owner's question; the window stays open.
	var reviewRequested: (() -> Void)?
	private(set) weak var window: NSWindow?
	/// SwiftUI's delegate, which every other message goes to.
	private var standIn: (any NSWindowDelegate)?
	/// The delegate messages the stand-in answers, fixed when the review is
	/// installed, because the window asks which ones are answered when its
	/// delegate is set.
	private let forwardedSelectors: Set<Selector>

	/// Stands in front of `window`'s delegate.
	init(window: NSWindow, policy: WindowClosePolicy) {
		self.policy = policy
		self.window = window
		let standIn = window.delegate
		self.standIn = standIn
		forwardedSelectors = Self.forwardableSelectors.filter { standIn?.responds(to: $0) == true }
		super.init()
		window.delegate = self
	}

	/// Whether this review is still the window's delegate. SwiftUI may set a
	/// delegate of its own again.
	var isInstalled: Bool {
		window?.delegate === self
	}

	/// Gives the window back to its own delegate.
	func uninstall() {
		if let window, window.delegate === self {
			window.delegate = standIn
		}
		standIn = nil
	}

	/// Closes the window without asking, once the owner has its answer.
	func close() {
		window?.close()
	}

	// MARK: - Close

	/// The window's answer: the stand-in decides only when nothing is lost.
	func windowShouldClose(_ sender: NSWindow) -> Bool {
		switch policy {
		case .closes:
			return standIn?.windowShouldClose?(sender) ?? true
		case .asks:
			reviewRequested?()
			return false
		case .refuses:
			NSSound.beep()
			return false
		}
	}

	func windowWillClose(_ notification: Notification) {
		standIn?.windowWillClose?(notification)
		uninstall()
	}

	// MARK: - Forwarding

	/** Answers for exactly the stand-in's messages, so the window treats the
	 messages it does not answer as unanswered, as it would without the review. */
	override nonisolated func responds(to selector: Selector!) -> Bool { // nonisolated: pure
		guard let selector else { return false }
		if Self.forwardableSelectors.contains(selector) {
			return forwardedSelectors.contains(selector)
		}
		return super.responds(to: selector)
	}

	/// The delegate messages the review passes on. Each one has a method below.
	nonisolated static let forwardableSelectors: Set<Selector> = [
		#selector(NSWindowDelegate.windowWillReturnFieldEditor(_:to:)),
		#selector(NSWindowDelegate.windowWillResize(_:to:)),
		#selector(NSWindowDelegate.windowWillUseStandardFrame(_:defaultFrame:)),
		#selector(NSWindowDelegate.windowShouldZoom(_:toFrame:)),
		#selector(NSWindowDelegate.windowWillReturnUndoManager(_:)),
		#selector(NSWindowDelegate.window(_:willPositionSheet:using:)),
		#selector(NSWindowDelegate.window(_:willUseFullScreenContentSize:)),
		#selector(NSWindowDelegate.window(_:willUseFullScreenPresentationOptions:)),
		#selector(NSWindowDelegate.window(_:willEncodeRestorableState:)),
		#selector(NSWindowDelegate.window(_:didDecodeRestorableState:)),
		#selector(NSWindowDelegate.windowDidResize(_:)),
		#selector(NSWindowDelegate.windowDidExpose(_:)),
		#selector(NSWindowDelegate.windowWillMove(_:)),
		#selector(NSWindowDelegate.windowDidMove(_:)),
		#selector(NSWindowDelegate.windowDidBecomeKey(_:)),
		#selector(NSWindowDelegate.windowDidResignKey(_:)),
		#selector(NSWindowDelegate.windowDidBecomeMain(_:)),
		#selector(NSWindowDelegate.windowDidResignMain(_:)),
		#selector(NSWindowDelegate.windowWillMiniaturize(_:)),
		#selector(NSWindowDelegate.windowDidMiniaturize(_:)),
		#selector(NSWindowDelegate.windowDidDeminiaturize(_:)),
		#selector(NSWindowDelegate.windowDidUpdate(_:)),
		#selector(NSWindowDelegate.windowDidChangeScreen(_:)),
		#selector(NSWindowDelegate.windowDidChangeBackingProperties(_:)),
		#selector(NSWindowDelegate.windowWillBeginSheet(_:)),
		#selector(NSWindowDelegate.windowDidEndSheet(_:)),
		#selector(NSWindowDelegate.windowWillStartLiveResize(_:)),
		#selector(NSWindowDelegate.windowDidEndLiveResize(_:)),
		#selector(NSWindowDelegate.windowWillEnterFullScreen(_:)),
		#selector(NSWindowDelegate.windowDidEnterFullScreen(_:)),
		#selector(NSWindowDelegate.windowWillExitFullScreen(_:)),
		#selector(NSWindowDelegate.windowDidExitFullScreen(_:)),
		#selector(NSWindowDelegate.windowDidFailToEnterFullScreen(_:)),
		#selector(NSWindowDelegate.windowDidFailToExitFullScreen(_:)),
		#selector(NSWindowDelegate.windowDidChangeOcclusionState(_:)),
	]

	func windowWillReturnFieldEditor(_ sender: NSWindow, to client: Any?) -> Any? {
		standIn?.windowWillReturnFieldEditor?(sender, to: client)
	}

	func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
		standIn?.windowWillResize?(sender, to: frameSize) ?? frameSize
	}

	func windowWillUseStandardFrame(_ window: NSWindow, defaultFrame newFrame: NSRect) -> NSRect {
		standIn?.windowWillUseStandardFrame?(window, defaultFrame: newFrame) ?? newFrame
	}

	func windowShouldZoom(_ window: NSWindow, toFrame newFrame: NSRect) -> Bool {
		standIn?.windowShouldZoom?(window, toFrame: newFrame) ?? true
	}

	func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
		standIn?.windowWillReturnUndoManager?(window)
	}

	func window(_ window: NSWindow, willPositionSheet sheet: NSWindow, using rect: NSRect) -> NSRect {
		standIn?.window?(window, willPositionSheet: sheet, using: rect) ?? rect
	}

	func window(_ window: NSWindow, willUseFullScreenContentSize proposedSize: NSSize) -> NSSize {
		standIn?.window?(window, willUseFullScreenContentSize: proposedSize) ?? proposedSize
	}

	func window(
		_ window: NSWindow,
		willUseFullScreenPresentationOptions proposedOptions: NSApplication.PresentationOptions = []
	) -> NSApplication.PresentationOptions {
		standIn?.window?(window, willUseFullScreenPresentationOptions: proposedOptions) ?? proposedOptions
	}

	func window(_ window: NSWindow, willEncodeRestorableState state: NSCoder) {
		standIn?.window?(window, willEncodeRestorableState: state)
	}

	func window(_ window: NSWindow, didDecodeRestorableState state: NSCoder) {
		standIn?.window?(window, didDecodeRestorableState: state)
	}

	func windowDidResize(_ notification: Notification) {
		standIn?.windowDidResize?(notification)
	}

	func windowDidExpose(_ notification: Notification) {
		standIn?.windowDidExpose?(notification)
	}

	func windowWillMove(_ notification: Notification) {
		standIn?.windowWillMove?(notification)
	}

	func windowDidMove(_ notification: Notification) {
		standIn?.windowDidMove?(notification)
	}

	func windowDidBecomeKey(_ notification: Notification) {
		standIn?.windowDidBecomeKey?(notification)
	}

	func windowDidResignKey(_ notification: Notification) {
		standIn?.windowDidResignKey?(notification)
	}

	func windowDidBecomeMain(_ notification: Notification) {
		standIn?.windowDidBecomeMain?(notification)
	}

	func windowDidResignMain(_ notification: Notification) {
		standIn?.windowDidResignMain?(notification)
	}

	func windowWillMiniaturize(_ notification: Notification) {
		standIn?.windowWillMiniaturize?(notification)
	}

	func windowDidMiniaturize(_ notification: Notification) {
		standIn?.windowDidMiniaturize?(notification)
	}

	func windowDidDeminiaturize(_ notification: Notification) {
		standIn?.windowDidDeminiaturize?(notification)
	}

	func windowDidUpdate(_ notification: Notification) {
		standIn?.windowDidUpdate?(notification)
	}

	func windowDidChangeScreen(_ notification: Notification) {
		standIn?.windowDidChangeScreen?(notification)
	}

	func windowDidChangeBackingProperties(_ notification: Notification) {
		standIn?.windowDidChangeBackingProperties?(notification)
	}

	func windowWillBeginSheet(_ notification: Notification) {
		standIn?.windowWillBeginSheet?(notification)
	}

	func windowDidEndSheet(_ notification: Notification) {
		standIn?.windowDidEndSheet?(notification)
	}

	func windowWillStartLiveResize(_ notification: Notification) {
		standIn?.windowWillStartLiveResize?(notification)
	}

	func windowDidEndLiveResize(_ notification: Notification) {
		standIn?.windowDidEndLiveResize?(notification)
	}

	func windowWillEnterFullScreen(_ notification: Notification) {
		standIn?.windowWillEnterFullScreen?(notification)
	}

	func windowDidEnterFullScreen(_ notification: Notification) {
		standIn?.windowDidEnterFullScreen?(notification)
	}

	func windowWillExitFullScreen(_ notification: Notification) {
		standIn?.windowWillExitFullScreen?(notification)
	}

	func windowDidExitFullScreen(_ notification: Notification) {
		standIn?.windowDidExitFullScreen?(notification)
	}

	func windowDidFailToEnterFullScreen(_ window: NSWindow) {
		standIn?.windowDidFailToEnterFullScreen?(window)
	}

	func windowDidFailToExitFullScreen(_ window: NSWindow) {
		standIn?.windowDidFailToExitFullScreen?(window)
	}

	func windowDidChangeOcclusionState(_ notification: Notification) {
		standIn?.windowDidChangeOcclusionState?(notification)
	}
}

extension View {
	/** Asks before the window closes while `policy` says to.

	 `installed` hands the owner the review once the view is in its window, so
	 the owner can raise its question on that window and close it afterwards;
	 `review` is called when someone tries to close the window and the policy
	 asks. */
	func windowCloseReview(
		_ policy: WindowClosePolicy,
		installed: @escaping (WindowCloseReview) -> Void,
		review: @escaping () -> Void
	) -> some View {
		background(WindowCloseReviewAnchor(policy: policy, installed: installed, review: review))
	}
}

/// The view that finds the window the review stands in for.
private struct WindowCloseReviewAnchor: NSViewRepresentable {
	let policy: WindowClosePolicy
	let installed: (WindowCloseReview) -> Void
	let review: () -> Void

	func makeNSView(context _: Context) -> AnchorView {
		AnchorView()
	}

	func updateNSView(_ view: AnchorView, context _: Context) {
		view.policy = policy
		view.installed = installed
		view.review = review
		view.refresh()
	}

	static func dismantleNSView(_ view: AnchorView, coordinator _: ()) {
		view.closeReview?.uninstall()
		view.closeReview = nil
	}

	final class AnchorView: NSView {
		var policy: WindowClosePolicy = .closes
		var installed: ((WindowCloseReview) -> Void)?
		var review: (() -> Void)?
		var closeReview: WindowCloseReview?

		override func viewDidMoveToWindow() {
			super.viewDidMoveToWindow()
			refresh()
		}

		/// Installs the review on the window the view is in, or again if
		/// something else became the window's delegate, and passes on the
		/// owner's current policy.
		func refresh() {
			guard let window else {
				closeReview?.uninstall()
				closeReview = nil
				return
			}
			if let closeReview, closeReview.window === window, closeReview.isInstalled {
				closeReview.policy = policy
				closeReview.reviewRequested = review
				return
			}
			closeReview?.uninstall()
			let closeReview = WindowCloseReview(window: window, policy: policy)
			closeReview.reviewRequested = review
			self.closeReview = closeReview
			installed?(closeReview)
		}
	}
}
