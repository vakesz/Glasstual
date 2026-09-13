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
		// Whatever AppKit writes back, the answer is overlay.
		set { super.scrollerStyle = newValue == .overlay ? newValue : .overlay }
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
 watched and the style re-applied. */
private struct OverlayScrollersAdapter: NSViewRepresentable {
	func makeNSView(context _: Context) -> OverlayScrollersProbeView {
		OverlayScrollersProbeView()
	}

	func updateNSView(_ view: OverlayScrollersProbeView, context _: Context) {
		view.scheduleOverlayStyle()
	}
}

private final class OverlayScrollersProbeView: NSView {
	private let notifications = NotificationSubscriptions()
	/// Set while a style application is already queued for the next turn, so a
	/// burst of invalidations resolves the scroll views once.
	private var styleTask: Task<Void, Never>?
	/** The scroll views this probe stands for.

	 Finding them walks four ancestors by three levels of subviews with a
	 coordinate conversion per candidate, and `updateNSView` runs on every
	 SwiftUI invalidation of the list this decorates. Where they are cannot
	 change without the probe moving, so the walk runs once per placement. */
	private weak var enclosing: NSScrollView?
	private weak var neighbour: NSScrollView?
	private var hasResolvedScrollViews = false

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		notifications.observe(NSScroller.preferredScrollerStyleDidChangeNotification) { [weak self] _ in
			self?.scheduleOverlayStyle()
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
		invalidateResolvedScrollViews()
	}

	override func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()
		invalidateResolvedScrollViews()
	}

	private func invalidateResolvedScrollViews() {
		hasResolvedScrollViews = false
		enclosing = nil
		neighbour = nil
		scheduleOverlayStyle()
	}

	/** Styles the scroll views on the next main-actor turn, never inline.

	 Writing `scrollerStyle` is a write AppKit answers by tiling the scroll
	 view, and every caller here arrives from inside a SwiftUI update:
	 `updateNSView` runs in the graph's own update pass, and the two
	 `viewDidMoveTo…` callbacks in the layout pass that installs the view.
	 Tiling there re-enters the list that is being updated -- the scroll view
	 resizes the list's rows, one of them lays out, and its hosting view renders
	 while the graph is still updating, which aborts the process with
	 "AttributeGraph precondition failure: setting value during update" and the
	 reentrant-delegate warning that precedes it. A turn later the list has
	 finished and the same write is an ordinary resize.

	 The scroller-preference notification needed the same hop for its own
	 reason: AppKit writes the preferred style onto every scroll view while
	 that notification is being posted, so a style applied inline is
	 overwritten. */
	func scheduleOverlayStyle() {
		guard styleTask == nil else { return }
		styleTask = Task { [weak self] in
			self?.styleTask = nil
			self?.applyOverlayStyle()
		}
	}

	/** Both candidates are styled, not the first one found.

	 The probe is a background of the list, which SwiftUI may place inside the
	 list's own scroll view or beside it, and the two answers are different
	 scroll views. Taking `enclosingScrollView` and stopping because it was
	 already overlay left the list -- the view this modifier was asked about --
	 with the system's legacy scrollers. */
	private func applyOverlayStyle() {
		if hasResolvedScrollViews == false {
			enclosing = enclosingScrollView
			neighbour = neighbouringScrollView()
			/* Neither exists until the list has built its own scroll view, so
			 an empty answer is retried rather than remembered. */
			hasResolvedScrollViews = enclosing != nil || neighbour != nil
		}

		for scrollView in [enclosing, neighbour].compactMap(\.self)
			where scrollView.scrollerStyle != .overlay
		{
			scrollView.scrollerStyle = .overlay
		}
	}

	/** The scroll view this probe is standing in for.

	 Containment is the discriminant: the member list's ancestors reach the
	 conversation column, so the first scroll view under any of them can be the
	 transcript's rather than the list's. A candidate has to be drawn where the
	 probe is. */
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
