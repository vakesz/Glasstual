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

@objc(TDCWindowBase)
@objcMembers
open class WindowBase: NSObject {
	public weak var delegate: AnyObject?

	@IBOutlet public var window: NSWindow!
	@IBOutlet public weak var okButton: NSButton?
	@IBOutlet public weak var cancelButton: NSButton?

	open func show() {
		window.makeKeyAndOrderFront(nil)
	}

	open func close() {
		window.close()
	}

	@objc(ok:)
	open func ok(_ sender: Any?) {
		close()
	}

	@objc(cancel:)
	open func cancel(_ sender: Any?) {
		close()
	}
}
