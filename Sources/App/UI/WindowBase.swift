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

open class WindowBase: NSObject {
	public weak var delegate: AnyObject?

	@IBOutlet public var window: NSWindow!
	@IBOutlet public var okButton: NSButton?
	@IBOutlet public var cancelButton: NSButton?

	@MainActor open func show() {
		window.makeKeyAndOrderFront(nil)
	}

	@MainActor open func close() {
		window?.close()
	}

	@MainActor open func ok(_: Any?) {
		close()
	}

	@MainActor open func cancel(_: Any?) {
		close()
	}
}
