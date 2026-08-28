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

@objc(TVCChannelSelectionOutlineCellView)
public final class ChannelSelectionOutlineCellView: NSTableCellView {
	@objc public weak var parentController: ChannelSelectionViewController?

	@IBOutlet public var selectedCheckbox: NSButton!

	@objc
	public func prepareInitialState() {
		guard let outlineView = parentController?.outlineView, let cellItem else {
			return
		}

		let isGroupItem = outlineView.isGroupItem(cellItem)

		textField?.stringValue = cellItem.name

		selectedCheckbox.allowsMixedState = isGroupItem
		selectedCheckbox.setAccessibilityTitle(cellItem.name)
	}

	@IBAction @objc(selectionCheckboxClicked:)
	public func selectionCheckboxClicked(_: Any?) {
		parentController?.selectionCheckboxClicked(inCell: self)
	}

	private var cellItem: IRCTreeItem? {
		objectValue as? IRCTreeItem
	}
}
