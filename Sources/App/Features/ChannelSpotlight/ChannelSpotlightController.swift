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

/// What `ChannelSpotlightController` reports back.
@MainActor
public protocol ChannelSpotlightControllerDelegate: AnyObject {
	func channelSpotlightController(_ sender: ChannelSpotlightController, selectChannel channel: IRCChannel)
	func channelSpotlightControllerWillClose(_ sender: ChannelSpotlightController)
}

private nonisolated enum ChannelSpotlightSection: Hashable, Sendable { // nonisolated: value
	case results
}

private typealias ChannelSpotlightDataSource =
	NSTableViewDiffableDataSource<ChannelSpotlightSection, ChannelSpotlightSearchResult.ID>
private typealias ChannelSpotlightSnapshot =
	NSDiffableDataSourceSnapshot<ChannelSpotlightSection, ChannelSpotlightSearchResult.ID>

@objc(TDCChannelSpotlightController)
@MainActor
public final class ChannelSpotlightController: WindowBase, NSTableViewDataSource, NSTableViewDelegate,
	NSControlTextEditingDelegate, NSWindowDelegate
{
	private var spotlightDelegate: (any ChannelSpotlightControllerDelegate)? {
		delegate as? any ChannelSpotlightControllerDelegate
	}

	public private(set) var userInterfaceObjects: ChannelSpotlightAppearance!

	@IBOutlet private var visualEffectView: NSVisualEffectView!
	@IBOutlet private var noResultsLabel: NSTextField!
	@IBOutlet private var noResultsLabelLeadingConstraint: NSLayoutConstraint!
	@IBOutlet private var searchResultsView: NSView!
	@IBOutlet private var searchResultsViewHeightConstraint: NSLayoutConstraint!
	@IBOutlet private var searchField: NSTextField!
	@IBOutlet private var searchResultsTable: NSTableView!

	/// Every channel the spotlight knows about, in the order it found them.
	private var allSearchResults: [ChannelSpotlightSearchResult] = []
	/// The subset the table draws, best match first.
	private var displayedSearchResults: [ChannelSpotlightSearchResult] = []
	private var searchResultsDataSource: ChannelSpotlightDataSource?
	/// The only server to show channels from, or `nil` for every server.
	private var restrictedClientID: String?

	private var mouseEventMonitor: Any?
	private lazy var notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelSpotlightController", owner: self, topLevelObjects: nil)

		searchResultsTable.doubleAction = #selector(delegatePostSelectChannelForDoubleClickedRow(_:))

		let searchResultsDataSource = makeSearchResultsDataSource()
		self.searchResultsDataSource = searchResultsDataSource
		searchResultsTable.dataSource = searchResultsDataSource

		mouseEventMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
			self?.respondToKeyDownEvent(event) ?? event
		}

		notifications.observe(NSNotification.Name("TXApplicationAppearanceChangedNotification")) { [weak self] _ in
			self?.applicationAppearanceChanged()
		}
		notifications.observe(NSNotification.Name("IRCClientChannelListWasModifiedNotification")) { [weak self] _ in
			self?.channelListChanged()
		}
		notifications.observe(NSNotification.Name("IRCWorldClientListWasModifiedNotification")) { [weak self] _ in
			self?.clientListChanged()
		}
		notifications.observe(NSNotification.Name("TVCMainWindowSelectionChangedNotification")) { [weak self] _ in
			self?.mainWindowSelectionChanged()
		}
		notifications
			.observe(.textualUserDefaultsDidChange) { [weak self] notification in
				self?.preferencesChanged(notification)
			}

		populateSearchResults()

		searchField.controlSize = .large

		replaceVisualEffectViewWithGlassEffectView()

		applicationAppearanceChanged()

		noResultsLabelLeadingConstraint.textual_archiveConstant()
		searchResultsViewHeightConstraint.textual_archiveConstant()

		updateClientRestriction()
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

	private func applicationAppearanceChanged() {
		guard window is ChannelSpotlightPanel,
		      let appearance = ChannelSpotlightAppearance()
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
			noResultsLabelLeadingConstraint.textual_zeroOutConstant()
			searchResultsViewHeightConstraint.textual_zeroOutConstant()
			return
		}

		if searchResultsCount == 0 {
			noResultsLabel.stringValue = ChannelSpotlightStrings.noResults
			noResultsLabelLeadingConstraint.textual_restoreArchivedConstant()
			searchResultsViewHeightConstraint.textual_zeroOutConstant()
			return
		}

		noResultsLabel.stringValue = ""
		noResultsLabelLeadingConstraint.textual_zeroOutConstant()
		searchResultsViewHeightConstraint.textual_restoreArchivedConstant()

		selectFirstSearchResultIfNecessary()
	}

	private func updateSearchResultsSelection() {
		searchResultsTable.invalidateSelectionBackground()
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
		let searchResultsCount = searchResultsCount

		if searchResultsCount == 0 {
			return nil
		}

		let selectedRow = searchResultsTable.selectedRow

		// Wrap around table when we reach the top or bottom
		if event.keyCode == 126 || event.keyCode == 116 { // up
			if selectedRow == 0 {
				searchResultsTable.selectItem(at: Int(searchResultsCount - 1))
				return nil
			}
		} else if event.keyCode == 125 || event.keyCode == 121 { // down
			if selectedRow == NSInteger(searchResultsCount - 1) {
				searchResultsTable.selectItem(at: 0)
				return nil
			}
		}

		searchResultsTable.keyDown(with: event)

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
		spotlightDelegate?.channelSpotlightController(self, selectChannel: channel)

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

	@MainActor override public func close() {
		saveWindowFrame()
		window!.close()
	}

	@MainActor override public func show() {
		restoreWindowFrame()
		window!.makeKeyAndOrderFront(nil)
	}

	private func restoreWindowFrame() {
		let window = window!

		window.ce_saveSizeAsDefault()
		window.ce_restoreState(for: Self.self)
	}

	private func saveWindowFrame() {
		/* Reset search back to none before closing so
		 that the frame we save is same we open. */
		resetSearch()

		let window = window!

		/* We call -restoreDefaultSizeAndDisplay: before saving
		 the frame because the window wont register the changes
		 to the constants in -resetSearch until next layout pass. */
		window.ce_restoreDefaultSize(display: false)
		window.ce_saveState(for: Self.self)
	}

	// MARK: - Search Field

	@objc public var searchString: String {
		searchField.stringValue
	}

	// MARK: - Search results

	private func makeSearchResultsDataSource() -> ChannelSpotlightDataSource {
		let dataSource = ChannelSpotlightDataSource(
			tableView: searchResultsTable
		) { [weak self] tableView, column, _, resultID in
			let view = tableView.makeView(withIdentifier: column.identifier, owner: self)

			guard let cell = view as? ChannelSpotlightSearchResultCellView else {
				return view ?? NSView()
			}

			cell.objectValue = self?.searchResult(withID: resultID)

			return cell
		}

		/* The delegate's `rowViewForRow` is not consulted once a diffable data
		 source is installed, so the row view is handed over here instead. */
		dataSource.rowViewProvider = { [weak self] _, _, _ in
			guard let self else {
				return NSTableRowView()
			}

			return ChannelSpotlightSearchResultRowView(controller: self)
		}

		return dataSource
	}

	private func searchResult(
		withID id: ChannelSpotlightSearchResult.ID
	) -> ChannelSpotlightSearchResult? {
		displayedSearchResults.first { $0.id == id }
	}

	/// Re-derives the rows to draw and hands them to the table.
	private func applySearchResults() {
		guard let searchResultsDataSource else {
			return
		}

		displayedSearchResults = ChannelSpotlightSearchResults.displayed(
			allSearchResults,
			restrictedToClient: restrictedClientID,
			distance: \.distance,
			clientID: \.clientId
		)

		/* A channel belongs to one client and appears once, so a repeat would be
		 a bug upstream — but a snapshot holding two equal item identifiers traps,
		 and that is not worth a crash. */
		var admitted: Set<ChannelSpotlightSearchResult.ID> = []
		displayedSearchResults = displayedSearchResults.filter { admitted.insert($0.id).inserted }

		var snapshot = ChannelSpotlightSnapshot()
		snapshot.appendSections([.results])
		snapshot.appendItems(displayedSearchResults.map(\.id), toSection: .results)
		searchResultsDataSource.apply(snapshot, animatingDifferences: false)
	}

	/// Notes which server the list is restricted to, if any.
	///
	/// Channel navigation can be per-server, which the array controller
	/// expressed as a `clientId LIKE[c]` clause on its filter predicate.
	private func updateClientRestriction() {
		if TextualPreferences.channelNavigationIsServerSpecific() {
			restrictedClientID = AppController.shared.mainWindow.selectedClient?.uniqueIdentifier ?? ""
		} else {
			restrictedClientID = nil
		}

		applySearchResults()
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

	public var searchResults: [ChannelSpotlightSearchResult] {
		allSearchResults
	}

	@objc public var searchResultsFiltered: [ChannelSpotlightSearchResult] {
		displayedSearchResults
	}

	@objc public var searchResultsCount: UInt {
		UInt(displayedSearchResults.count)
	}

	@objc public var selectedSearchResult: Int {
		searchResultsTable.selectedRow
	}

	private func recalculateDistanceForSearchResults() {
		let searchString = searchField.stringValue

		for searchResult in allSearchResults {
			searchResult.recalculateDistance(with: searchString)
		}

		/* The scores decide both which rows are shown and their order, so the
		 table has to be told; the array controller used to notice through KVO. */
		applySearchResults()
		updateControlsState()
	}

	private func populateSearchResults() {
		let searchString = searchField.stringValue
		var searchResults: [ChannelSpotlightSearchResult] = []

		let clientList = AppController.shared.world.clientList

		for client in clientList {
			let channelList = client.channelList

			for channel in channelList {
				let searchResult = searchResult(for: channel)
				searchResult.recalculateDistance(with: searchString)
				searchResults.append(searchResult)
			}
		}

		allSearchResults = searchResults

		applySearchResults()
	}

	private func searchResult(for channel: IRCChannel) -> ChannelSpotlightSearchResult {
		ChannelSpotlightSearchResult(channel: channel)
	}

	private func searchStringChanged() {
		recalculateDistanceForSearchResults()
	}

	// MARK: - Notifications

	private func mainWindowSelectionChanged() {
		/* Predicate is updated when selection changes because predicate may be configured
		 to be per-server. This could be made more efficient by checking if it is server
		 specific and comparing the selected client identifier to what is in predicate.
		 That involves a lot more work for something that shouldn't be fired a lot. */
		updateClientRestriction()
	}

	private func preferencesChanged(_ notification: Notification) {
		let changedKey = notification.userInfo?["changedKey"] as? String

		if changedKey == "ChannelNavigationIsServerSpecific" {
			updateClientRestriction()
		}
	}

	private func clientListChanged() {
		populateSearchResults()
		updateControlsState()
	}

	private func channelListChanged() {
		populateSearchResults()
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

		notifications.cancelAll()

		spotlightDelegate?.channelSpotlightControllerWillClose(self)
	}
}
