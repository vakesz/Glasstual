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

@objc(TVCChannelSelectionViewController)
@MainActor
public final class ChannelSelectionViewController: NSObject, NSOutlineViewDataSource, NSOutlineViewDelegate {
	@objc public weak var delegate: AnyObject?

	@IBOutlet private var outlineViewScrollView: NSScrollView!
	@IBOutlet private var outlineViewOutlet: NSOutlineView!

	private weak var attachedView: NSView?
	private var cachedSelectedClientIdsStorage = NSMutableArray()
	private var cachedSelectedChannelIdsStorage = NSMutableArray()
	private var cachedClientList: [IRCClient] = []
	private var cachedChannelList: NSMutableDictionary = [:]
	private var expandOutlineViewWorkItem: DispatchWorkItem?

	override public init() {
		super.init()
		prepareInitialState()
	}

	deinit {
		NotificationCenter.default.removeObserver(self)
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TVCChannelSelectionView", owner: self, topLevelObjects: nil)

		addObserverForChannelListUpdates()
		rebuildCachedChannelList()
	}

	@objc(attachToView:)
	public func attach(to view: NSView) {
		precondition(attachedView == nil, "Table view is already attached to a view")

		attachedView = view

		let outlineViewScroller = outlineViewScrollView!
		view.addSubview(outlineViewScroller)

		view.addConstraints(
			NSLayoutConstraint.constraints(
				withVisualFormat: "H:|-0-[outlineViewScroller]-0-|",
				options: .directionLeadingToTrailing,
				metrics: nil,
				views: ["outlineViewScroller": outlineViewScroller]
			)
		)

		view.addConstraints(
			NSLayoutConstraint.constraints(
				withVisualFormat: "V:|-0-[outlineViewScroller]-0-|",
				options: .directionLeadingToTrailing,
				metrics: nil,
				views: ["outlineViewScroller": outlineViewScroller]
			)
		)
	}

	@objc public func outlineView() -> NSOutlineView {
		outlineViewOutlet
	}

	private func item(from cellView: ChannelSelectionOutlineCellView) -> IRCTreeItem? {
		let row = outlineViewOutlet.row(for: cellView)

		if row < 0 {
			return nil
		}

		return outlineViewOutlet.item(atRow: row) as? IRCTreeItem
	}

	@objc(selectionCheckboxClickedInCell:)
	public func selectionCheckboxClicked(inCell clickedCell: ChannelSelectionOutlineCellView) {
		guard let item = item(from: clickedCell) else {
			return
		}

		let isGroupItem = outlineViewOutlet.isGroupItem(item)
		let checkboxState = clickedCell.selectedCheckbox.state
		let isEnablingItem = checkboxState == .on || checkboxState == .mixed

		if isGroupItem {
			if isEnablingItem {
				cachedSelectedClientIdsStorage.add(item.uniqueIdentifier)
			} else {
				cachedSelectedClientIdsStorage.remove(item.uniqueIdentifier)
			}
		} else {
			if isEnablingItem {
				cachedSelectedChannelIdsStorage.add(item.uniqueIdentifier)
			} else {
				cachedSelectedChannelIdsStorage.remove(item.uniqueIdentifier)
			}
		}

		if isGroupItem, isEnablingItem {
			let childrenItems = outlineViewOutlet.items(fromParentGroup: item) as? [IRCTreeItem] ?? []

			for childItem in childrenItems {
				cachedSelectedChannelIdsStorage.remove(childItem.uniqueIdentifier)
			}
		}

		updateSelectedState(for: item)

		let selector = NSSelectorFromString("channelSelectionControllerSelectionChanged:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}

	private func applySelectedState(to cellView: ChannelSelectionOutlineCellView?, for item: IRCTreeItem) {
		guard let cellView else {
			return
		}

		if item.isClient {
			if cachedSelectedClientIdsStorage.contains(item.uniqueIdentifier) {
				cellView.selectedCheckbox.state = .on
				return
			}

			if let channels = cachedChannelList[item] as? [IRCChannel] {
				for channel in channels where cachedSelectedChannelIdsStorage.contains(channel.uniqueIdentifier) {
					cellView.selectedCheckbox.state = .mixed
					return
				}
			}

			cellView.selectedCheckbox.state = .off
			return
		}

		let parentItemInFilter = cachedSelectedClientIdsStorage.contains(
			item.associatedClient?.uniqueIdentifier as Any
		)

		if parentItemInFilter || cachedSelectedChannelIdsStorage.contains(item.uniqueIdentifier) {
			cellView.selectedCheckbox.state = .on
		} else {
			cellView.selectedCheckbox.state = .off
		}

		cellView.selectedCheckbox.isEnabled = parentItemInFilter == false
	}

	private func updateSelectedState(for item: IRCTreeItem) {
		guard let parentItem: IRCTreeItem = item.isClient ? item : item.associatedClient else {
			return
		}
		let childrenItems = outlineViewOutlet.items(inGroup: parentItem) as? [IRCTreeItem] ?? []

		for childItem in childrenItems {
			let childItemRow = outlineViewOutlet.row(forItem: childItem)
			let childItemView = outlineViewOutlet.view(
				atColumn: 0,
				row: childItemRow,
				makeIfNecessary: false
			) as? ChannelSelectionOutlineCellView

			applySelectedState(to: childItemView, for: childItem)
		}

		let parentItemRow = outlineViewOutlet.row(forItem: parentItem)
		let parentItemView = outlineViewOutlet.view(
			atColumn: 0,
			row: parentItemRow,
			makeIfNecessary: false
		) as? ChannelSelectionOutlineCellView

		applySelectedState(to: parentItemView, for: parentItem)
	}

	// MARK: - Properties

	@objc public var selectedClientIds: [String] {
		get {
			objc_sync_enter(cachedSelectedClientIdsStorage)
			defer { objc_sync_exit(cachedSelectedClientIdsStorage) }

			return cachedSelectedClientIdsStorage as? [String] ?? []
		}
		set {
			objc_sync_enter(cachedSelectedClientIdsStorage)
			defer { objc_sync_exit(cachedSelectedClientIdsStorage) }

			cachedSelectedClientIdsStorage = NSMutableArray(array: newValue)
			reloadOutlineView()
		}
	}

	@objc public var selectedChannelIds: [String] {
		get {
			objc_sync_enter(cachedSelectedChannelIdsStorage)
			defer { objc_sync_exit(cachedSelectedChannelIdsStorage) }

			return cachedSelectedChannelIdsStorage as? [String] ?? []
		}
		set {
			objc_sync_enter(cachedSelectedChannelIdsStorage)
			defer { objc_sync_exit(cachedSelectedChannelIdsStorage) }

			cachedSelectedChannelIdsStorage = NSMutableArray(array: newValue)
			reloadOutlineView()
		}
	}

	// MARK: - Cache Management

	private func addObserverForChannelListUpdates() {
		NotificationCenter.default.addObserver(
			self,
			selector: #selector(channelListChanged(_:)),
			name: NSNotification.Name("IRCWorldClientListWasModifiedNotification"),
			object: nil
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(channelListChanged(_:)),
			name: NSNotification.Name("IRCClientChannelListWasModifiedNotification"),
			object: nil
		)
	}

	private func reloadOutlineView() {
		outlineViewOutlet.reloadData()
	}

	private func expandOutlineViewItemsCancelTimer() {
		expandOutlineViewWorkItem?.cancel()
		expandOutlineViewWorkItem = nil
	}

	private func expandOutlineViewItemsCreateTimer() {
		if expandOutlineViewWorkItem != nil {
			return
		}

		let workItem = DispatchWorkItem { [weak self] in
			guard let self else {
				return
			}

			outlineViewOutlet.expandItem(nil, expandChildren: true)
			expandOutlineViewWorkItem = nil
		}

		expandOutlineViewWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
	}

	@objc private func channelListChanged(_: Any?) {
		rebuildCachedChannelList()
		reloadOutlineView()
		expandOutlineViewItemsCancelTimer()
	}

	private func rebuildCachedChannelList() {
		let clientList = NSObject.masterController().world.clientList as? [IRCClient] ?? []
		let channelList = NSMutableDictionary()

		for client in clientList {
			var channels: [IRCChannel] = []

			for case let channel as IRCChannel in client.channelList {
				if channel.isChannel == false {
					continue
				}

				channels.append(channel)
			}

			channelList[client] = channels
		}

		cachedClientList = clientList
		cachedChannelList = channelList
	}

	// MARK: - Outline View

	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item {
			return (cachedChannelList[item as Any] as? [Any])?.count ?? 0
		}

		return cachedClientList.count
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let item {
			return (cachedChannelList[item as Any] as? [Any])?[index] as Any
		}

		return cachedClientList[index]
	}

	public func outlineView(
		_: NSOutlineView,
		objectValueFor _: NSTableColumn?,
		byItem item: Any?
	) -> Any? {
		item
	}

	public func outlineView(
		_ outlineView: NSOutlineView,
		viewFor _: NSTableColumn?,
		item: Any
	) -> NSView? {
		guard let treeItem = item as? IRCTreeItem else {
			return nil
		}

		let identifier = treeItem.isClient ? "serverEntry" : "channelEntry"
		let newView = outlineView.makeView(
			withIdentifier: NSUserInterfaceItemIdentifier(identifier),
			owner: self
		) as? ChannelSelectionOutlineCellView

		newView?.parentController = self
		newView?.objectValue = item
		newView?.prepareInitialState()

		if let newView {
			applySelectedState(to: newView, for: treeItem)
		}

		return newView
	}

	public func outlineView(_: NSOutlineView, didAdd _: NSTableRowView, forRow _: Int) {
		expandOutlineViewItemsCreateTimer()
	}

	public func outlineView(_: NSOutlineView, isItemExpandable _: Any) -> Bool {
		true
	}

	public func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		false
	}

	public func outlineView(_: NSOutlineView, isGroupItem _: Any) -> Bool {
		false
	}

	public func outlineView(_: NSOutlineView, shouldShowOutlineCellForItem _: Any) -> Bool {
		false
	}
}
