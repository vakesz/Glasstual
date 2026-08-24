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

@objc(TDCAboutDialog)
public final class AboutDialog: WindowBase {
	@IBOutlet private var versionInfoTextField: NSTextField!

	override public init() {
		super.init()
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCAboutDialog", owner: self, topLevelObjects: nil)

		let bundleVersion = ApplicationInfo.applicationVersionShort()
		versionInfoTextField.stringValue = LocalizedKey("TDCAboutDialog[zjd-al]", bundleVersion)

		window.styleMask.insert(.fullSizeContentView)
		window.titlebarAppearsTransparent = true
		window.titleVisibility = .hidden
	}

	@objc override public func show() {
		window.perform(NSSelectorFromString("restoreWindowStateForClass:"), with: type(of: self))
		super.show()
	}

	@IBAction public func displayAcknowledgements(_ sender: Any?) {
		NSObject.masterController().menuController?.openAcknowledgements(sender)
	}

	@objc public func windowWillClose(_: Notification) {
		window.perform(NSSelectorFromString("saveWindowStateForClass:"), with: type(of: self))

		let selector = NSSelectorFromString("aboutDialogWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
