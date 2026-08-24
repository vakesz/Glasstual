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

@objc(TDCNicknameColorSheet)
@MainActor
public final class NicknameColorSheet: SheetBase {
	private var nickname = ""
	private var nicknameColorIsReset = false

	@IBOutlet private var nicknameColorWell: NSColorWell!
	@IBOutlet private var useDefaultColorCheck: NSButton!

	@objc(initWithNickname:)
	public init(nickname: String) {
		super.init(window: nil)
		self.nickname = nickname
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCNicknameColorSheet", owner: self, topLevelObjects: nil)

		let nicknameColor = UserNicknameColorStyleGenerator.nicknameColorStyleOverride(forKey: nickname)
		nicknameColorIsReset = (nicknameColor == nil)

		if let nicknameColor {
			nicknameColorWell.color = nicknameColor
		}

		nicknameColorWell.target = self
		nicknameColorWell.action = #selector(nicknameColorChanged(_:))

		updateControls()
	}

	private func updateControls() {
		useDefaultColorCheck.state = nicknameColorIsReset ? .on : .off
		nicknameColorWell.isEnabled = !nicknameColorIsReset
	}

	@objc public func start() {
		startSheet()
	}

	@IBAction override public func ok(_: Any?) {
		var nicknameColor: NSColor? = nicknameColorWell.color

		if nicknameColorIsReset {
			nicknameColor = nil
		}

		UserNicknameColorStyleGenerator.setNicknameColorStyleOverride(nicknameColor, forKey: nickname)

		let selector = NSSelectorFromString("nicknameColorSheetOnOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}

		super.ok(nil)
	}

	@IBAction public func useDefaultColorToggled(_: Any?) {
		nicknameColorIsReset = (useDefaultColorCheck.state == .on)

		if nicknameColorIsReset, NSColorPanel.sharedColorPanelExists {
			NSColorPanel.shared.close()
		}

		updateControls()
	}

	@IBAction public func nicknameColorChanged(_: Any?) {
		nicknameColorIsReset = false
		updateControls()
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("nicknameColorSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
