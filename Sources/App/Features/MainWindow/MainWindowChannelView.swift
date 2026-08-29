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

import AppKit
import CocoaExtensions
import Combine

/** The delegate lives in an object of its own rather than on the split view.
 AppKit answers -respondsToSelector: for toggleSidebar: on any NSSplitView by
 putting the same question to that view's delegate, so a split view that is its
 own delegate asks itself forever. Toolbar validation of the sidebar toggle item
 walks the responder chain from the first responder, which passes through this
 view whenever the message area holds focus, and the recursion runs the stack
 out before an answer comes back. */
private final class MainWindowChannelViewDelegate: NSObject, NSSplitViewDelegate {
	func splitView(_: NSSplitView, canCollapseSubview _: NSView) -> Bool {
		false
	}
}

@objc(TVCMainWindowChannelView)
public final class MainWindowChannelView: NSSplitView, AppearanceObserving {
	/* -[NSSplitView delegate] is weak, so the delegate is owned here. */
	private var splitViewDelegate = MainWindowChannelViewDelegate()
	private var itemIndexSelected = NSNotFound

	override public func viewDidMoveToWindow() {
		super.viewDidMoveToWindow()

		/* Was `awakeFromNib`, which is nonisolated. The delegate only has to be
		 in place before the split view lays out, and it is idempotent. */
		if window != nil, delegate == nil {
			delegate = splitViewDelegate
		}

		/* -viewDidMoveToWindow is not guaranteed to alternate between a window
		 and nil. Remove any previous registration first so that moving within
		 the same window does not leave duplicate observers behind. */
		NotificationCenter.default.removeObserver(
			self,
			name: .themeAppearanceChanged,
			object: nil
		)

		guard window != nil else {
			return
		}

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(themeAppearanceChanged(_:)),
			name: .themeAppearanceChanged,
			object: nil
		)
	}

	private func resetSubviews() {
		for subview in Array(subviews) {
			subview.removeFromSuperview()
		}
	}

	@objc
	public func populateSubviews() {
		guard let mainWindow else {
			return
		}

		let selectedItems = mainWindow.selectedItems

		if selectedItems.isEmpty {
			resetSubviews()
			itemIndexSelected = NSNotFound
			return
		}

		/* Make a list of subviews that already exist to compare when adding
		 or removing views so that we do not have to destroy entire backing. */
		var existingSubviews: [String: MainWindowChannelViewSubview] = [:]

		for case let subview as MainWindowChannelViewSubview in subviews {
			existingSubviews[subview.uniqueIdentifier] = subview
		}

		/* Once selectedItems is processed, the value of subviewsUnclaimed will
		 be subviews that are no longer selected */
		var subviewsUnclaimed = existingSubviews
		var itemSelectedIndex = NSNotFound
		let itemSelected = mainWindow.selectedItem
		let hadExistingSubviews = existingSubviews.isEmpty == false

		for (index, item) in selectedItems.enumerated() {
			let uniqueIdentifier = item.uniqueIdentifier

			var subviewIsNew = true
			var subview = existingSubviews[uniqueIdentifier]

			if subview != nil {
				subviewIsNew = false
				subviewsUnclaimed.removeValue(forKey: uniqueIdentifier)
			} else {
				subview = self.subview(for: item)
			}

			guard let subview else {
				continue
			}

			subview.backingView = backingView(for: item)
			subview.itemIndex = index

			if itemSelected === item {
				itemSelectedIndex = index
				subview.isSelected = true
			} else {
				subview.isSelected = false

				/* -isSelected is defaulted to NO which means for new views,
				 -toggleOverlayView must be manually invoked because the
				 setter wont change the value if they are same (NO == NO) */
				if subviewIsNew {
					subview.toggleOverlayView()
				}
			}

			subview.uniqueIdentifier = uniqueIdentifier

			if subviewIsNew {
				addSubview(subview)
			}
		}

		itemIndexSelected = itemSelectedIndex

		for subview in subviewsUnclaimed.values {
			subview.removeFromSuperview()
		}

		if hadExistingSubviews {
			orderSubviewsByItemIndex()
		}

		adjustSubviews()
	}

	/// Puts the subviews back in ascending `itemIndex` order.
	///
	/// `sortSubviews(_:context:)` takes a C function pointer, which cannot carry
	/// isolation, so the comparator had to assume it was on the main actor.
	/// Restacking with `addSubview(_:positioned:relativeTo:)` reaches the same
	/// order from code that is isolated by declaration. Ties keep the order they
	/// already had, which is what a stable sort would have done.
	func orderSubviewsByItemIndex() {
		let ordered = subviews
			.enumerated()
			.compactMap { position, view in
				(view as? MainWindowChannelViewSubview).map { (position: position, view: $0) }
			}
			.sorted { first, second in
				if first.view.itemIndex == second.view.itemIndex {
					return first.position < second.position
				}

				return first.view.itemIndex < second.view.itemIndex
			}

		var previous: NSView?

		for entry in ordered {
			addSubview(entry.view, positioned: .above, relativeTo: previous)
			previous = entry.view
		}
	}

	@objc(selectionChangeTo:)
	func selectionChange(to itemIndex: Int) {
		guard let mainWindow else {
			return
		}

		let selectedItems = mainWindow.selectedItems
		let currentSubviews = subviews

		if currentSubviews.indices.contains(itemIndexSelected),
		   let oldItemView = currentSubviews[itemIndexSelected] as? MainWindowChannelViewSubview
		{
			oldItemView.isSelected = false
			oldItemView.toggleOverlayView()
		}

		guard currentSubviews.indices.contains(itemIndex),
		      selectedItems.indices.contains(itemIndex),
		      let newItemView = currentSubviews[itemIndex] as? MainWindowChannelViewSubview
		else {
			return
		}

		newItemView.isSelected = true
		newItemView.toggleOverlayView()

		itemIndexSelected = itemIndex

		let newItem = selectedItems[itemIndex]
		mainWindow.channelViewSelectionChange(to: newItem)
	}

	private func backingView(for item: IRCTreeItem) -> LogView? {
		item.logController?.backingView
	}

	private func subview(for _: IRCTreeItem) -> MainWindowChannelViewSubview {
		var splitViewFrame = frame
		splitViewFrame.origin.x = 0.0
		splitViewFrame.origin.y = 0.0

		let overlayView = MainWindowChannelViewSubview(frame: splitViewFrame)
		overlayView.parentView = self
		return overlayView
	}

	@objc(holdingPriorityForSubviewAtIndex:)
	override public func holdingPriorityForSubview(at _: Int) -> NSLayoutConstraint.Priority {
		NSLayoutConstraint.Priority(350.0)
	}

	override public var dividerThickness: CGFloat {
		2.0
	}

	override public var dividerColor: NSColor {
		.separatorColor
	}

	@objc
	public func updateArrangement() {
		let arrangement = TextualPreferences.channelViewArrangement()
		isVertical = (arrangement == .vertical)
	}

	@objc
	private func themeAppearanceChanged(_: Notification) {
		/* Clearing the appearance lets the view inherit the window's. */
		appearance = nil
	}

	/// Primary, secondary and tertiary mouse buttons.
	fileprivate static let allMouseButtonsMask = 0x1 | 0x2 | 0x4
}

// MARK: - Overlay View

/** Internal rather than private so the subview ordering can be tested. */
final class MainWindowChannelViewSubview: NSView {
	var itemIndex: Int = 0
	var overlayVisible = false
	private var backingViewLayoutObservation: Task<Void, Never>?
	var uniqueIdentifier = ""
	weak var parentView: MainWindowChannelView?
	private var overlayView: MainWindowChannelViewSubviewOverlayView?

	var isSelected = false {
		didSet {
			if oldValue != isSelected {
				toggleOverlayView()
			}
		}
	}

	var backingView: LogView? {
		didSet {
			if oldValue !== backingView {
				teardownBackingView(previous: oldValue)
				setupWebView()
			}
		}
	}

	var backingViewIsLoading: Bool {
		backingView?.isLayingOutView ?? false
	}

	override init(frame frameRect: NSRect) {
		super.init(frame: frameRect)
		prepareInitialState()
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	override func viewWillMove(toSuperview newSuperview: NSView?) {
		if newSuperview == nil {
			teardownBackingView(previous: backingView)
		}

		super.viewWillMove(toSuperview: newSuperview)
	}

	private func prepareInitialState() {
		translatesAutoresizingMaskIntoConstraints = false
	}

	override func draw(_ dirtyRect: NSRect) {
		/* The web view stops at the safe area so the input bar does not cover the
		 last lines of the view. Nothing painted the strip that leaves behind, so it
		 showed the window's own background. Fill it with the style's window color
		 to make it continuous with the message area above it. */
		var backgroundColor = SharedApplication.sharedThemeController().settings.underlyingWindowColor

		if backgroundColor == nil {
			backgroundColor = .textBackgroundColor
		}

		backgroundColor?.set()
		NSBezierPath.fill(dirtyRect)
	}

	private func teardownBackingView(previous backingView: LogView?) {
		guard let backingView else {
			return
		}

		backingViewLayoutObservation?.cancel()
		backingViewLayoutObservation = nil

		/* Removing the web view from its superview also removes the
		 constraints that -setupWebView activated between it and us. */
		let webView = backingView.webView

		if webView.superview === self {
			webView.removeFromSuperview()
		}
	}

	private func setupWebView() {
		guard let backingView else {
			return
		}

		if backingViewIsLoading {
			/* `observe(_:options:changeHandler:)` hands back a nonisolated
			 closure; awaiting the same key path's values inside a main-actor
			 task keeps the handler where the view lives. */
			backingViewLayoutObservation = Task { @MainActor [weak self] in
				for await _ in backingView.publisher(for: \.isLayingOutView, options: [.new]).values {
					guard let self else {
						return
					}

					toggleOverlayView()
				}
			}
		}

		let webView = backingView.webView

		if overlayVisible, let overlayView {
			addSubview(webView, positioned: .below, relativeTo: overlayView)
		} else {
			addSubview(webView)
		}

		/* The sides and the bottom are pinned to the safe area rather than to the
		 edges. The server list, the member list and the input bar all float above
		 the channel view instead of taking space from it, which is why this view is
		 handed the full width of the window: the strips they cover are reported
		 through safeAreaInsets and nothing else. Pinning to the edges is what puts
		 the first and last characters of every line underneath them.

		 The top is deliberately left on the edge. The web view is told about the
		 title bar through the same safe area and answers it by insetting its own
		 scroll view, which is what lets messages scroll up behind the toolbar. */
		let safeArea = safeAreaLayoutGuide

		/* Kept below required so that a window narrow or short enough to violate
		 them breaks these rather than the pins above. */
		let minimumWidth = webView.widthAnchor.constraint(greaterThanOrEqualToConstant: 30.0)
		let minimumHeight = webView.heightAnchor.constraint(greaterThanOrEqualToConstant: 30.0)

		minimumWidth.priority = .defaultHigh
		minimumHeight.priority = .defaultHigh

		NSLayoutConstraint.activate([
			webView.topAnchor.constraint(equalTo: topAnchor),
			webView.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
			webView.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor),
			webView.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
			minimumWidth,
			minimumHeight,
		])
	}

	private func constructOverlayView() {
		let overlayView = MainWindowChannelViewSubviewOverlayView(frame: frame)
		overlayView.translatesAutoresizingMaskIntoConstraints = false

		/* Any button pressed on the overlay selects the pane beneath it.
		 A gesture recognizer replaces the -mouseDown: family of overrides.
		 Primary button events are not delayed so that the click is not
		 held back from the view while the recognizer decides. */
		let clickRecognizer = NSClickGestureRecognizer(target: self, action: #selector(overlayViewClicked(_:)))
		clickRecognizer.buttonMask = MainWindowChannelView.allMouseButtonsMask
		clickRecognizer.numberOfClicksRequired = 1
		clickRecognizer.delaysPrimaryMouseButtonEvents = false
		overlayView.addGestureRecognizer(clickRecognizer)

		self.overlayView = overlayView
	}

	@objc
	private func overlayViewClicked(_: NSClickGestureRecognizer) {
		guard overlayVisible else {
			return
		}

		mouseDownSelectionChange()
	}

	private func addOverlayView() {
		if overlayVisible {
			overlayView?.needsDisplay = true
			return
		}

		if overlayView == nil {
			constructOverlayView()
		}

		guard let overlayView else {
			return
		}

		addSubview(overlayView)

		NSLayoutConstraint.activate([
			overlayView.leadingAnchor.constraint(equalTo: leadingAnchor),
			overlayView.trailingAnchor.constraint(equalTo: trailingAnchor),
			overlayView.topAnchor.constraint(equalTo: topAnchor),
			overlayView.bottomAnchor.constraint(equalTo: bottomAnchor),
		])

		overlayVisible = true
	}

	func toggleOverlayView() {
		if backingViewIsLoading || isSelected == false {
			addOverlayView()
		} else if let overlayView {
			overlayView.removeFromSuperview()
			overlayVisible = false
		}
	}

	private func mouseDownSelectionChange() {
		guard backingViewIsLoading == false else {
			return
		}

		parentView?.selectionChange(to: itemIndex)
	}

	override func hitTest(_ point: NSPoint) -> NSView? {
		guard frame.contains(point) else {
			return nil
		}

		/* While the overlay is shown it swallows every event so that an
		 unselected web view cannot be interacted with. This is a hit
		 testing concern, not an event override, and is kept as such. */
		if overlayVisible {
			return overlayView
		}

		return super.hitTest(point)
	}
}

// MARK: -

private final class MainWindowChannelViewSubviewOverlayView: NSView {
	override func draw(_ dirtyRect: NSRect) {
		guard needsToDraw(dirtyRect) else {
			return
		}

		guard let subview = superview as? MainWindowChannelViewSubview else {
			return
		}

		var backgroundColor: NSColor? = if subview.backingViewIsLoading {
			SharedApplication.sharedThemeController().settings.underlyingWindowColor
		} else {
			SharedApplication.sharedThemeController().settings.channelViewOverlayColor
		}

		if backgroundColor == nil {
			backgroundColor = defaultBackgroundColor()
		}

		backgroundColor?.set()
		NSBezierPath.fill(dirtyRect)
	}

	private func defaultBackgroundColor() -> NSColor {
		guard let mainWindow else {
			return .textBackgroundColor
		}

		let appearance = mainWindow.userInterfaceObjects

		if mainWindow.ceIsActiveForDrawing {
			return appearance.channelViewOverlayDefaultBackgroundColorActiveWindow
				?? .textBackgroundColor
		}

		return appearance.channelViewOverlayDefaultBackgroundColorInactiveWindow
			?? .textBackgroundColor
	}

	override func hitTest(_: NSPoint) -> NSView? {
		self
	}
}
