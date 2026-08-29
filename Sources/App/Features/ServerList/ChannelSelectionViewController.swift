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
import GlasstualPluginKit

@objc(TVCChannelSelectionViewController)
@MainActor
public final class ChannelSelectionViewController: NSObject, PluginChannelSelection, NSOutlineViewDataSource,
	NSOutlineViewDelegate
{
	@IBOutlet private var outlineViewScrollView: NSScrollView!
	/// Name must match the outlet connection in TVCChannelSelectionView.xib;
	/// the nib sets it through setValue(_:forKey:).
	@IBOutlet public private(set) var outlineView: NSOutlineView!

	private weak var attachedView: NSView?
	private var cachedSelectedClientIdsStorage: [String] = []
	private var cachedSelectedChannelIdsStorage: [String] = []
	private var cachedClientList: [IRCClient] = []
	private var cachedChannelList: [ObjectIdentifier: [IRCChannel]] = [:]
	private var expandOutlineViewWorkItem: DispatchWorkItem?
	/// The world and client channel-list notifications this view answers.
	private let notifications = NotificationSubscriptions()

	override public init() {
		super.init()
		prepareInitialState()
	}

	isolated deinit {
		notifications.cancelAll()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TVCChannelSelectionView", owner: self, topLevelObjects: nil)

		addObserverForChannelListUpdates()
		rebuildCachedChannelList()
	}

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

	private func item(from cellView: ChannelSelectionOutlineCellView) -> IRCTreeItem? {
		let row = outlineView.row(for: cellView)

		if row < 0 {
			return nil
		}

		return outlineView.item(atRow: row) as? IRCTreeItem
	}

	public func selectionCheckboxClicked(inCell clickedCell: ChannelSelectionOutlineCellView) {
		guard let item = item(from: clickedCell) else {
			return
		}

		let isGroupItem = outlineView.isGroupItem(item)
		let checkboxState = clickedCell.selectedCheckbox.state
		let isEnablingItem = checkboxState == .on || checkboxState == .mixed

		if isGroupItem {
			if isEnablingItem {
				if cachedSelectedClientIdsStorage.contains(item.uniqueIdentifier) == false {
					cachedSelectedClientIdsStorage.append(item.uniqueIdentifier)
				}
			} else {
				cachedSelectedClientIdsStorage.removeAll { $0 == item.uniqueIdentifier }
			}
		} else {
			if isEnablingItem {
				if cachedSelectedChannelIdsStorage.contains(item.uniqueIdentifier) == false {
					cachedSelectedChannelIdsStorage.append(item.uniqueIdentifier)
				}
			} else {
				cachedSelectedChannelIdsStorage.removeAll { $0 == item.uniqueIdentifier }
			}
		}

		if isGroupItem, isEnablingItem {
			let childrenItems = outlineView.items(inContainingGroupOf: item) as? [IRCTreeItem] ?? []

			for childItem in childrenItems {
				cachedSelectedChannelIdsStorage.removeAll { $0 == childItem.uniqueIdentifier }
			}
		}

		updateSelectedState(for: item)
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

			if let channels = cachedChannelList[ObjectIdentifier(item)] {
				for channel in channels where cachedSelectedChannelIdsStorage.contains(channel.uniqueIdentifier) {
					cellView.selectedCheckbox.state = .mixed
					return
				}
			}

			cellView.selectedCheckbox.state = .off
			return
		}

		let parentItemInFilter = item.associatedClient.map {
			cachedSelectedClientIdsStorage.contains($0.uniqueIdentifier)
		} ?? false

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
		let childrenItems = outlineView.items(inGroup: parentItem) as? [IRCTreeItem] ?? []

		for childItem in childrenItems {
			let childItemRow = outlineView.row(forItem: childItem)
			let childItemView = outlineView.view(
				atColumn: 0,
				row: childItemRow,
				makeIfNecessary: false
			) as? ChannelSelectionOutlineCellView

			applySelectedState(to: childItemView, for: childItem)
		}

		let parentItemRow = outlineView.row(forItem: parentItem)
		let parentItemView = outlineView.view(
			atColumn: 0,
			row: parentItemRow,
			makeIfNecessary: false
		) as? ChannelSelectionOutlineCellView

		applySelectedState(to: parentItemView, for: parentItem)
	}

	// MARK: - Properties

	public var selectedClientIds: [String] {
		get { cachedSelectedClientIdsStorage }
		set {
			cachedSelectedClientIdsStorage = newValue
			reloadOutlineView()
		}
	}

	public var selectedChannelIds: [String] {
		get { cachedSelectedChannelIdsStorage }
		set {
			cachedSelectedChannelIdsStorage = newValue
			reloadOutlineView()
		}
	}

	// MARK: - Cache Management

	private func addObserverForChannelListUpdates() {
		notifications
			.observe(NSNotification.Name("IRCWorldClientListWasModifiedNotification")) { [weak self] notification in
				self?.channelListChanged(notification)
			}

		notifications
			.observe(NSNotification.Name("IRCClientChannelListWasModifiedNotification")) { [weak self] notification in
				self?.channelListChanged(notification)
			}
	}

	private func reloadOutlineView() {
		outlineView.reloadData()
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

			outlineView.expandItem(nil, expandChildren: true)
			expandOutlineViewWorkItem = nil
		}

		expandOutlineViewWorkItem = workItem
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: workItem)
	}

	private func channelListChanged(_: Any?) {
		/* Cancel before reloading, not after: the reload is what schedules the
		 expand through outlineView(_:didAdd:forRow:), and cancelling
		 afterwards leaves the tree collapsed. */
		expandOutlineViewItemsCancelTimer()
		rebuildCachedChannelList()
		reloadOutlineView()
	}

	private func rebuildCachedChannelList() {
		let clientList = AppController.shared.world.clientList
		var channelList: [ObjectIdentifier: [IRCChannel]] = [:]

		for client in clientList {
			var channels: [IRCChannel] = []

			for channel in client.channelList {
				if channel.isChannel == false {
					continue
				}

				channels.append(channel)
			}

			channelList[ObjectIdentifier(client)] = channels
		}

		cachedClientList = clientList
		cachedChannelList = channelList
	}

	// MARK: - Outline View

	private func cachedChannels(for item: Any?) -> [IRCChannel] {
		guard let client = item as? IRCClient else {
			return []
		}

		return cachedChannelList[ObjectIdentifier(client)] ?? []
	}

	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item {
			return cachedChannels(for: item).count
		}

		return cachedClientList.count
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let item {
			return cachedChannels(for: item)[index]
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
