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

@objc(TDCServerChangeNicknameSheet)
@MainActor
public final class ServerChangeNicknameSheet: SheetBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var clientId = ""

	@IBOutlet private var tnewNicknameTextField: TVCValidatedTextField!
	@IBOutlet private var toldNicknameTextField: NSTextField!

	@objc(initWithClient:)
	public init(client: IRCClient) {
		super.init(window: nil)
		self.client = client
		clientId = client.uniqueIdentifier
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCServerChangeNicknameSheet", owner: self, topLevelObjects: nil)

		tnewNicknameTextField.stringValueIsInvalidOnEmpty = true
		tnewNicknameTextField.stringValueUsesOnlyFirstToken = true
		tnewNicknameTextField.textDidChangeCallback = self

		tnewNicknameTextField.validationBlock = { [weak self] currentValue in
			guard let self else {
				return nil
			}

			if (currentValue as NSString).isHostmaskNickname(on: client) == false {
				return LocalizedKey("CommonErrors[och-j5]")
			}

			return nil
		}

		let nickname = client.userNickname
		tnewNicknameTextField.stringValue = nickname
		toldNicknameTextField.stringValue = nickname
	}

	@objc public func start() {
		startSheet()
		sheet.makeFirstResponder(tnewNicknameTextField)
	}

	@IBAction override public func ok(_ sender: Any?) {
		guard okOrError() else {
			return
		}

		let selector = NSSelectorFromString("serverChangeNicknameSheet:didInputNickname:")
		if let delegate, delegate.responds(to: selector) {
			let newNickname = tnewNicknameTextField.value
			_ = delegate.perform(selector, with: self, with: newNickname)
		}

		super.ok(sender)
	}

	@objc public func okOrError() -> Bool {
		okOrError(for: tnewNicknameTextField)
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("serverChangeNicknameSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
