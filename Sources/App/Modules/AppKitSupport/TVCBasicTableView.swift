/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@objc(TVCBasicTableView)
public class BasicTableView: NSTableView {
	@objc public weak var pasteboardDelegate: AnyObject?

	override public func responds(to aSelector: Selector!) -> Bool {
		if aSelector == #selector(copy(_:)) {
			return pasteboardDelegate?.responds(to: #selector(copy(_:))) == true
		}

		return super.responds(to: aSelector)
	}

	@objc public func copy(_ sender: Any?) {
		pasteboardDelegate?.perform(#selector(copy(_:)), with: sender)
	}

	override public func menu(for event: NSEvent) -> NSMenu? {
		let point = convert(event.locationInWindow, from: nil)
		let rowBeneathMouse = row(at: point)

		if rowBeneathMouse >= 0, selectedRowIndexes.contains(rowBeneathMouse) == false {
			selectItem(at: UInt(rowBeneathMouse))
		}

		if selectedRow < 0 {
			return nil
		}

		return menu
	}
}
