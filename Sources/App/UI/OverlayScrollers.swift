/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import SwiftUI

/** A scroll view whose scrollers only appear while the content is moving,
 whatever the system's scroller preference says. AppKit writes the preferred
 style back on every preference change, so the style is pinned in the setter
 as well as at creation. */
final class OverlayScrollView: NSScrollView {
	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		super.scrollerStyle = .overlay
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("OverlayScrollView is programmatic")
	}

	override var scrollerStyle: NSScroller.Style {
		get { .overlay }
		set {
			/* The value is deliberately ignored; SwiftLint asks for the read. */
			_ = newValue
			super.scrollerStyle = .overlay
		}
	}
}

/** Pins overlay scrollers on the SwiftUI list this sits beside.

 A `List` builds its own `NSScrollView`, which SwiftUI does not expose; this
 adapter joins the view tree as an invisible companion and finds that scroll
 view among its neighbours. It is not inside the scroll view -- SwiftUI places
 a background or overlay beside the platform view, not within it -- so
 `enclosingScrollView` alone would find nothing; the search walks a few levels
 up and looks for the nearest scroll view below each ancestor. AppKit resets
 the style whenever the system preference changes, so the notification is
 watched and the style re-applied. Delivery through `NotificationSubscriptions`
 is asynchronous, and deliberately so: AppKit writes the preferred style onto
 every scroll view while that notification is being posted, so a style applied
 inline is overwritten. Arriving a turn later puts this after AppKit's own
 reset. */
private struct OverlayScrollersAdapter: NSViewRepresentable {
	func makeNSView(context _: Context) -> OverlayScrollersProbeView {
		OverlayScrollersProbeView()
	}

	func updateNSView(_ view: OverlayScrollersProbeView, context _: Context) {
		view.applyOverlayStyle()
	}
}

private final class OverlayScrollersProbeView: NSView {
	private let notifications = NotificationSubscriptions()

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		notifications.observe(NSScroller.preferredScrollerStyleDidChangeNotification) { [weak self] _ in
			self?.applyOverlayStyle()
		}
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("OverlayScrollersProbeView is programmatic")
	}

	override func hitTest(_: NSPoint) -> NSView? {
		nil
	}

	override func viewDidMoveToSuperview() {
		super.viewDidMoveToSuperview()
		applyOverlayStyle()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		applyOverlayStyle()
	}

	/** Both candidates are styled, not the first one found.

	 The probe is a background of the list, which SwiftUI may place inside the
	 list's own scroll view or beside it, and the two answers are different
	 scroll views. Taking `enclosingScrollView` and stopping because it was
	 already overlay left the list -- the view this modifier was asked about --
	 with the system's legacy scrollers. */
	func applyOverlayStyle() {
		for scrollView in [enclosingScrollView, neighbouringScrollView()].compactMap(\.self)
			where scrollView.scrollerStyle != .overlay
		{
			scrollView.scrollerStyle = .overlay
		}
	}

	/** The scroll view this probe is standing in for.

	 The walk used to take the first scroll view it met under any of four
	 ancestors, and in the main window the member list's ancestors reach the
	 conversation column: it found the transcript's `OverlayScrollView`, which is
	 already overlay, declared itself finished, and the list kept the system's
	 legacy scrollers. Containment is the discriminant now: a candidate has to be
	 drawn where the probe is. */
	private func neighbouringScrollView() -> NSScrollView? {
		var ancestor = superview
		for _ in 0 ..< 4 {
			guard let candidate = ancestor else { return nil }
			if let scrollView = firstContainingScrollView(under: candidate, depth: 3) {
				return scrollView
			}
			ancestor = candidate.superview
		}
		return nil
	}

	private func firstContainingScrollView(under view: NSView, depth: Int) -> NSScrollView? {
		for subview in view.subviews {
			if let scrollView = subview as? NSScrollView, containsProbe(scrollView) {
				return scrollView
			}
			if depth > 0, let scrollView = firstContainingScrollView(under: subview, depth: depth - 1) {
				return scrollView
			}
		}
		return nil
	}

	/** Whether `scrollView` is drawn over this probe.

	 An empty probe rect still has a location, and that is the whole test: the
	 list this modifier was applied to is the one drawn where the probe is. No
	 table is looked for -- a `List` builds one, but so does nothing else this
	 probe can be inside, and the transcript's scroll view sits beside the
	 member list rather than around it, so containment alone tells them apart. */
	private func containsProbe(_ scrollView: NSScrollView) -> Bool {
		let probeFrame = convert(bounds, to: scrollView)
		return scrollView.bounds.contains(probeFrame.origin)
			&& scrollView.bounds.contains(CGPoint(x: probeFrame.maxX, y: probeFrame.maxY))
	}
}

extension View {
	/// Overlay scrollers on the list this view is.
	func overlayScrollers() -> some View {
		background(OverlayScrollersAdapter().frame(width: 0, height: 0))
	}
}
