/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

@MainActor
open class SheetBase: NSObject {
	public weak var delegate: AnyObject?
	public weak var window: NSWindow?
	@IBOutlet public var sheet: NSWindow!
	@IBOutlet public var okButton: NSButton!
	@IBOutlet public var cancelButton: NSButton!

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(window:)")
	}

	public init(window: NSWindow?) {
		self.window = window
		super.init()
	}

	public func startSheet() {
		guard let window else {
			return
		}

		startSheet(with: window)
	}

	public func startSheet(with window: NSWindow) {
		window.beginSheet(sheet) { [weak self] returnCode in
			self?.sheetDidEnd(withReturnCode: returnCode.rawValue)
		}
	}

	public func endSheet() {
		let parentWindow = sheet.sheetParent ?? window
		parentWindow?.endSheet(sheet)
	}

	open func sheetDidEnd(withReturnCode _: Int) {
		sheet.close()
	}

	@IBAction open func ok(_: Any?) {
		endSheet()
	}

	@IBAction open func cancel(_: Any?) {
		endSheet()
	}

	open func close() {
		cancel(nil)
	}
}
