/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TDCChannelSpotlightController)
public final class ChannelSpotlightController: TDCWindowBase, NSTableViewDataSource, NSTableViewDelegate,
	NSControlTextEditingDelegate, NSWindowDelegate
{
	@objc public private(set) var userInterfaceObjects: ChannelSpotlightAppearance!

	@IBOutlet private weak var visualEffectView: NSVisualEffectView!
	@IBOutlet private weak var noResultsLabel: NSTextField!
	@IBOutlet private weak var noResultsLabelLeadingConstraint: NSLayoutConstraint!
	@IBOutlet private weak var searchResultsView: NSView!
	@IBOutlet private weak var searchResultsViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet private weak var searchField: NSTextField!
	@IBOutlet private weak var searchResultsTable: NSTableView!
	@IBOutlet private var searchResultsController: NSArrayController!

	private var mouseEventMonitor: Any?

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelSpotlightController", owner: self, topLevelObjects: nil)

		searchResultsTable.doubleAction = #selector(delegatePostSelectChannelForDoubleClickedRow(_:))

		mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			self?.respondToKeyDownEvent(event) ?? event
		}

		searchResultsController.sortDescriptors = [
			NSSortDescriptor(key: "distance", ascending: false, selector: #selector(NSNumber.compare(_:))),
		]

		let center = NotificationCenter.default

		center.addObserver(
			self,
			selector: #selector(applicationAppearanceChanged(_:)),
			name: NSNotification.Name("TXApplicationAppearanceChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(channelListChanged(_:)),
			name: NSNotification.Name("IRCClientChannelListWasModifiedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(clientListChanged(_:)),
			name: NSNotification.Name("IRCWorldClientListWasModifiedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(mainWindowSelectionChanged(_:)),
			name: NSNotification.Name("TVCMainWindowSelectionChangedNotification"),
			object: nil
		)
		center.addObserver(
			self,
			selector: #selector(preferencesChanged(_:)),
			name: NSNotification.Name("TPCPreferencesUserDefaultsDidChangeNotification"),
			object: nil
		)

		populateArrayController()

		searchField.controlSize = .large

		replaceVisualEffectViewWithGlassEffectView()

		applicationAppearanceChanged()

		noResultsLabelLeadingConstraint.archiveConstant()
		searchResultsViewHeightConstraint.archiveConstant()

		updatePredicate()
	}

	// MARK: - Glass Effect

	private func replaceVisualEffectViewWithGlassEffectView() {
		guard let visualEffectView, let parentView = visualEffectView.superview else {
			return
		}

		/* The visual effect view is declared in the xib. Interface Builder
		 does not yet offer NSGlassEffectView, so swap it in at runtime.
		 Every subview and every constraint that the effect view owned is
		 moved onto a plain container which becomes the glass view's
		 content. Constraints that referenced the effect view itself are
		 rebuilt against the container. */
		let subviews = visualEffectView.subviews
		let constraints = visualEffectView.constraints

		let containerView = NSView(frame: visualEffectView.bounds)
		containerView.translatesAutoresizingMaskIntoConstraints = false

		for subview in subviews {
			subview.removeFromSuperview()
			containerView.addSubview(subview)
		}

		var rebuiltConstraints: [NSLayoutConstraint] = []
		rebuiltConstraints.reserveCapacity(constraints.count)

		for constraint in constraints {
			var firstItem = constraint.firstItem
			var secondItem = constraint.secondItem

			if firstItem as AnyObject? === visualEffectView {
				firstItem = containerView
			}

			if secondItem as AnyObject? === visualEffectView {
				secondItem = containerView
			}

			let rebuiltConstraint = NSLayoutConstraint(
				item: firstItem as Any,
				attribute: constraint.firstAttribute,
				relatedBy: constraint.relation,
				toItem: secondItem,
				attribute: constraint.secondAttribute,
				multiplier: constraint.multiplier,
				constant: constraint.constant
			)

			rebuiltConstraint.priority = constraint.priority
			rebuiltConstraint.identifier = constraint.identifier

			rebuiltConstraints.append(rebuiltConstraint)
		}

		containerView.addConstraints(rebuiltConstraints)

		let glassView = NSGlassEffectView(frame: visualEffectView.frame)
		glassView.translatesAutoresizingMaskIntoConstraints = false
		glassView.cornerRadius = 22.0
		glassView.contentView = containerView

		/* Removing the effect view also removes the edge constraints that
		 pinned it to the window content view. Pin the glass view the same
		 way: leading, trailing, top, and bottom. */
		parentView.replaceSubview(visualEffectView, with: glassView)

		NSLayoutConstraint.activate([
			glassView.leadingAnchor.constraint(equalTo: parentView.leadingAnchor),
			glassView.trailingAnchor.constraint(equalTo: parentView.trailingAnchor),
			glassView.topAnchor.constraint(equalTo: parentView.topAnchor),
			glassView.bottomAnchor.constraint(equalTo: parentView.bottomAnchor),
		])
	}

	// MARK: - Appearance

	@objc private func applicationAppearanceChanged(_: Notification) {
		applicationAppearanceChanged()
	}

	private func applicationAppearanceChanged() {
		guard let panel = window as? ChannelSpotlightPanel,
			let appearance = ChannelSpotlightAppearance(window: panel)
		else {
			return
		}

		userInterfaceObjects = appearance

		updateVibrancy(with: appearance)
		updateControls(with: appearance)
		updateSearchResultsSelection()
	}

	private func updateVibrancy(with appearance: ChannelSpotlightAppearance) {
		let appKitAppearance = appearance.appKitAppearance

		switch appearance.appKitAppearanceTarget {
		case .window:
			window.appearance = appKitAppearance
		default:
			break
		}
	}

	private func updateControls(with appearance: ChannelSpotlightAppearance) {
		searchField.textColor = appearance.searchFieldTextColor
		noResultsLabel.textColor = appearance.searchFieldNoResultsTextColor
	}

	private func updateControlsState() {
		let searchString = searchField.stringValue

		if searchString.isEmpty {
			noResultsLabel.stringValue = ""
			noResultsLabelLeadingConstraint.zeroOutConstant()
			searchResultsViewHeightConstraint.zeroOutConstant()
			return
		}

		if searchResultsCount == 0 {
			noResultsLabel.stringValue = LocalizedKey("TDCChannelSpotlightController[tyv-p6]")
			noResultsLabelLeadingConstraint.restoreArchivedConstant()
			searchResultsViewHeightConstraint.zeroOutConstant()
			return
		}

		noResultsLabel.stringValue = ""
		noResultsLabelLeadingConstraint.zeroOutConstant()
		searchResultsViewHeightConstraint.restoreArchivedConstant()

		selectFirstSearchResultIfNecessary()
	}

	private func updateSearchResultsSelection() {
		searchResultsTable.invalidateBackgroundForSelection()
	}

	// MARK: - Events

	private func respondToKeyDownEvent(_ event: NSEvent) -> NSEvent? {
		guard window.isKeyWindow else {
			return event
		}

		switch event.keyCode {
		case 18, 19, 20, 21, 22, 23, 25, 26, 28, 29,
			82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92:
			var keyboardKeys = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
			keyboardKeys.remove(.numericPad)

			if keyboardKeys == .command {
				return handleCommandNumberEvent(event)
			}

			return event

		case 36, 76: // return, enter
			delegatePostSelectChannelForSelectedRow()
			return nil

		case 53: // escape
			clearSearchStringOrClose()
			return nil

		case 126, 125, 116, 121: // arrow up/down, page up/down
			return handlePageUpDownEvent(event)

		default:
			return event
		}
	}

	private func handlePageUpDownEvent(_ event: NSEvent) -> NSEvent? {
		let searchResultsCount = self.searchResultsCount

		if searchResultsCount == 0 {
			return nil
		}

		let selectedRow = searchResultsTable.selectedRow

		// Wrap around table when we reach the top or bottom
		if event.keyCode == 126 || event.keyCode == 116 { // up
			if selectedRow == 0 {
				searchResultsTable.selectItem(at: searchResultsCount - 1)
				return nil
			}
		} else if event.keyCode == 125 || event.keyCode == 121 { // down
			if selectedRow == NSInteger(searchResultsCount - 1) {
				searchResultsTable.selectItem(at: 0)
				return nil
			}
		}

		searchResultsTable.perform(NSSelectorFromString("keyDown:"), with: event)

		return nil
	}

	private func handleCommandNumberEvent(_ event: NSEvent) -> NSEvent? {
		let numberPressed = Int(event.characters ?? "") ?? -1

		guard (0 ... 9).contains(numberPressed) else {
			return event
		}

		var arrayIndex = numberPressed - 1

		if arrayIndex < 0 {
			arrayIndex = 9
		}

		delegatePostSelectChannelForSearchResult(at: arrayIndex)

		return nil
	}

	@objc private func delegatePostSelectChannelForDoubleClickedRow(_: Any?) {
		delegatePostSelectChannelForSearchResult(at: searchResultsTable.clickedRow)
	}

	private func delegatePostSelectChannelForSelectedRow() {
		delegatePostSelectChannelForSearchResult(at: searchResultsTable.selectedRow)
	}

	private func delegatePostSelectChannelForSearchResult(at searchResultIndex: Int) {
		let searchResults = searchResultsFiltered

		guard searchResultIndex >= 0, searchResultIndex < searchResults.count else {
			return
		}

		guard let channel = searchResults[searchResultIndex].channel else {
			return
		}

		delegatePostSelectChannel(channel)
	}

	private func delegatePostSelectChannel(_ channel: IRCChannel) {
		let selector = NSSelectorFromString("channelSpotlightController:selectChannel:")

		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: channel)
		}

		close()
	}

	// MARK: - Window Management

	private func clearSearchStringOrClose() {
		/* Mimic Spotlight behavior by clearing search string
		 on first escape and closing on second escape. */
		if searchField.stringValue.isEmpty == false {
			searchField.stringValue = ""
			searchStringChanged()
			return
		}

		close()
	}

	override public func close() {
		saveWindowFrame()
		window.close()
	}

	override public func show() {
		restoreWindowFrame()
		window.makeKeyAndOrderFront(nil)
	}

	private func restoreWindowFrame() {
		let window = self.window

		window.saveSizeAsDefault()
		window.perform(NSSelectorFromString("restoreWindowStateForClass:"), with: type(of: self))
	}

	private func saveWindowFrame() {
		/* Reset search back to none before closing so
		 that the frame we save is same we open. */
		resetSearch()

		let window = self.window

		/* We call -restoreDefaultSizeAndDisplay: before saving
		 the frame because the window wont register the changes
		 to the constants in -resetSearch until next layout pass. */
		window.restoreDefaultSizeAndDisplay(false)
		window.perform(NSSelectorFromString("saveWindowStateForClass:"), with: type(of: self))
	}

	// MARK: - Search Field

	@objc public var searchString: String {
		searchField.stringValue
	}

	// MARK: - Search Results

	private func updatePredicate() {
		if TPCPreferences.channelNavigationIsServerSpecific() {
			let clientId = NSObject.masterController().mainWindow.selectedClient?.uniqueIdentifier ?? ""

			searchResultsController.filterPredicate = NSPredicate(
				format: "distance >= 0.5 && clientId LIKE[c] %@",
				clientId
			)
		} else {
			searchResultsController.filterPredicate = NSPredicate(format: "distance >= 0.5")
		}

		updateControlsState()
	}

	private func resetSearch() {
		searchField.stringValue = ""
		searchStringChanged()
	}

	private func selectFirstSearchResultIfNecessary() {
		if searchResultsTable.selectedRow < 0 {
			searchResultsTable.selectItem(at: 0)
		}
	}

	@objc public var searchResults: [ChannelSpotlightSearchResult] {
		searchResultsController.content as? [ChannelSpotlightSearchResult] ?? []
	}

	@objc public var searchResultsFiltered: [ChannelSpotlightSearchResult] {
		searchResultsController.arrangedObjects as? [ChannelSpotlightSearchResult] ?? []
	}

	@objc public var searchResultsCount: UInt {
		UInt(searchResultsFiltered.count)
	}

	@objc public var selectedSearchResult: Int {
		searchResultsTable.selectedRow
	}

	private func recalculateDistanceForSearchResults() {
		let searchString = searchField.stringValue

		for searchResult in searchResults {
			searchResult.recalculateDistance(with: searchString)
		}

		updateControlsState()
	}

	private func populateArrayController() {
		let filterPredicate = searchResultsController.filterPredicate

		searchResultsController.filterPredicate = nil

		let searchString = searchField.stringValue
		var searchResults: [ChannelSpotlightSearchResult] = []

		let clientList = NSObject.masterController().world.clientList as? [IRCClient] ?? []

		for client in clientList {
			let channelList = client.channelList as? [IRCChannel] ?? []

			for channel in channelList {
				let searchResult = searchResult(for: channel)
				searchResult.recalculateDistance(with: searchString)
				searchResults.append(searchResult)
			}
		}

		searchResultsController.removeAllArrangedObjects()
		searchResultsController.add(contentsOf: searchResults)
		searchResultsController.filterPredicate = filterPredicate
	}

	private func searchResult(for channel: IRCChannel) -> ChannelSpotlightSearchResult {
		ChannelSpotlightSearchResult(channel: channel)
	}

	private func searchStringChanged() {
		recalculateDistanceForSearchResults()
	}

	// MARK: - Table View Delegate

	public func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
		ChannelSpotlightSearchResultRowView(controller: self)
	}

	// MARK: - Notifications

	@objc private func mainWindowSelectionChanged(_: Notification) {
		/* Predicate is updated when selection changes because predicate may be configured
		 to be per-server. This could be made more efficient by checking if it is server
		 specific and comparing the selected client identifier to what is in predicate.
		 That involves a lot more work for something that shouldn't be fired a lot. */
		updatePredicate()
	}

	@objc private func preferencesChanged(_ notification: Notification) {
		let changedKey = notification.userInfo?["changedKey"] as? String

		if changedKey == "ChannelNavigationIsServerSpecific" {
			updatePredicate()
		}
	}

	@objc private func clientListChanged(_: Any?) {
		populateArrayController()
		updateControlsState()
	}

	@objc private func channelListChanged(_: Any?) {
		populateArrayController()
		updateControlsState()
	}

	public func controlTextDidChange(_ obj: Notification) {
		if obj.object as AnyObject? === searchField {
			searchStringChanged()
		}
	}

	public func windowWillClose(_: Notification) {
		if let mouseEventMonitor {
			NSEvent.removeMonitor(mouseEventMonitor)
		}

		mouseEventMonitor = nil

		NotificationCenter.default.removeObserver(self)

		let selector = NSSelectorFromString("channelSpotlightControllerWillClose:")

		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
