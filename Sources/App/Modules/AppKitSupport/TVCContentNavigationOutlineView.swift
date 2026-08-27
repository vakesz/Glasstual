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
import CocoaExtensions

@objc(TVCContentNavigationOutlineViewItem)
public final class ContentNavigationOutlineViewItem: NSObject {
	@objc public private(set) var label = ""
	@objc public private(set) var identifier: UInt = 0
	@objc public private(set) weak var view: NSView?
	@objc public private(set) weak var firstResponder: NSControl?
	@objc public private(set) var children: [ContentNavigationOutlineViewItem]?

	@objc public var isGroupItem: Bool {
		children != nil
	}

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(label:identifier:view:firstResponder:)")
	}

	@objc(initWithLabel:identifier:view:firstResponder:)
	public init(
		label: String,
		identifier: UInt,
		view: NSView,
		firstResponder: NSControl?
	) {
		self.label = label
		self.identifier = identifier
		self.view = view
		self.firstResponder = firstResponder

		super.init()
	}

	@objc(initWithLabel:identifier:view:firstResponder:children:)
	public init(
		label: String,
		identifier: UInt,
		view: NSView?,
		firstResponder: NSControl?,
		children: [ContentNavigationOutlineViewItem]?
	) {
		precondition(view != nil || children != nil)

		self.label = label
		self.identifier = identifier
		self.view = view
		self.firstResponder = firstResponder
		self.children = children

		super.init()
	}
}

@objc(TVCContentNavigationOutlineView)
public final class ContentNavigationOutlineView: NSOutlineView {
	@objc public var contentViewPreferredWidth: UInt = 0
	@objc public var contentViewPreferredHeight: UInt = 0

	private var navigationTreeMatrixStorage = NSArray()

	@objc public var navigationTreeMatrix: [ContentNavigationOutlineViewItem] {
		get {
			navigationTreeMatrixStorage as? [ContentNavigationOutlineViewItem] ?? []
		}
		set {
			let newArray = newValue as NSArray
			guard newArray !== navigationTreeMatrixStorage else {
				return
			}

			navigationTreeMatrixStorage = newArray
			resetOutlineView()
		}
	}

	@objc public var expandParentOnDoubleClick = false
	@objc public private(set) weak var selectedItem: ContentNavigationOutlineViewItem?

	@IBOutlet private var contentView: NSView!
	private weak var lastSelection: ContentNavigationOutlineViewItem?

	private var parentOfLastSelection: ContentNavigationOutlineViewItem? {
		guard let lastSelection else {
			return nil
		}

		return parent(forItem: lastSelection) as? ContentNavigationOutlineViewItem
	}

	override public func awakeFromNib() {
		MainActor.assumeIsolated {
			super.awakeFromNib()

			dataSource = self
			delegate = self
			style = .sourceList
			doubleAction = #selector(outlineViewDoubleClicked(_:))
		}
	}

	@objc(navigateToItemWithIdentifier:)
	public func navigateToItem(withIdentifier identifier: UInt) {
		for groupItem in groupItems as? [ContentNavigationOutlineViewItem] ?? [] {
			if groupItem.identifier == identifier {
				selectItem(at: row(forItem: groupItem))
				return
			}

			for childItem in groupItem.children ?? [] where childItem.identifier == identifier {
				selectItem(at: row(forItem: childItem))
				return
			}
		}
	}

	private func resetOutlineView() {
		lastSelection = nil
		selectedItem = nil
		reloadData()
	}

	@objc private func outlineViewDoubleClicked(_: Any?) {
		guard expandParentOnDoubleClick else {
			return
		}

		let clickedRow = clickedRow

		guard clickedRow >= 0 else {
			return
		}

		guard let itemAtRow = item(atRow: clickedRow) as? ContentNavigationOutlineViewItem,
		      itemAtRow.isGroupItem
		else {
			return
		}

		expandItem(itemAtRow)
	}

	private func presentView(_ newView: NSView) {
		contentView.replaceFirstSubview(newView)
	}
}

extension ContentNavigationOutlineView: NSOutlineViewDataSource {
	public func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
		if let item = item as? ContentNavigationOutlineViewItem, item.isGroupItem {
			return item.children?.count ?? 0
		}

		return navigationTreeMatrix.count
	}

	public func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
		if let item = item as? ContentNavigationOutlineViewItem, item.isGroupItem {
			return item.children![index]
		}

		return navigationTreeMatrix[index]
	}

	public func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
		(item as? ContentNavigationOutlineViewItem)?.isGroupItem ?? false
	}
}

extension ContentNavigationOutlineView: NSOutlineViewDelegate {
	public func outlineView(_: NSOutlineView, shouldCollapseItem _: Any) -> Bool {
		true
	}

	public func outlineViewItemDidExpand(_ notification: Notification) {
		guard
			let parentItem = parentOfLastSelection,
			let itemExpanded = notification.userInfo?["NSObject"] as? ContentNavigationOutlineViewItem,
			parentItem === itemExpanded,
			let lastSelection
		else {
			return
		}

		let childIndex = row(forItem: lastSelection)

		if childIndex >= 0 {
			selectItem(at: childIndex)
		}
	}

	public func outlineView(
		_: NSOutlineView,
		objectValueFor _: NSTableColumn?,
		byItem item: Any?
	) -> Any? {
		(item as? ContentNavigationOutlineViewItem)?.label
	}

	public func outlineView(_: NSOutlineView, shouldSelectItem item: Any) -> Bool {
		(item as? ContentNavigationOutlineViewItem)?.view != nil
	}

	public func outlineView(
		_: NSOutlineView,
		viewFor _: NSTableColumn?,
		item _: Any
	) -> NSView? {
		makeView(withIdentifier: NSUserInterfaceItemIdentifier("navEntry"), owner: self)
	}

	public func outlineViewSelectionDidChange(_: Notification) {
		let selectedRow = selectedRow

		guard selectedRow >= 0 else {
			selectedItem = nil
			return
		}

		guard let item = item(atRow: selectedRow) as? ContentNavigationOutlineViewItem else {
			return
		}

		selectedItem = item
		lastSelection = item

		if let view = item.view {
			presentView(view)
		}

		if let firstResponder = item.firstResponder {
			window?.makeFirstResponder(firstResponder)
		}
	}
}
