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

@objc(TDCChannelModifyModesSheet)
@MainActor
public final class ChannelModifyModesSheet: SheetBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var channel: IRCChannel!
	@objc public private(set) var clientId = ""
	@objc public private(set) var channelId = ""

	private var modes: ChannelModeContainer!

	@IBOutlet private var sCheck: NSButton!
	@IBOutlet private var pCheck: NSButton!
	@IBOutlet private var nCheck: NSButton!
	@IBOutlet private var tCheck: NSButton!
	@IBOutlet private var iCheck: NSButton!
	@IBOutlet private var mCheck: NSButton!
	@IBOutlet private var kCheck: NSButton!
	@IBOutlet private var lCheck: NSButton!
	@IBOutlet private var kText: NSTextField!
	@IBOutlet private var lText: NSTextField!

	@objc dynamic var channelUserLimitMode = ""
	private var secretKeyLengthAlertDisplayed = false

	@objc(initWithChannel:)
	public init(channel: IRCChannel) {
		super.init(window: nil)

		client = channel.associatedClient
		clientId = channel.associatedClient!.uniqueIdentifier
		self.channel = channel
		channelId = channel.uniqueIdentifier
		modes = channel.modeInfo!.modes.copy() as! ChannelModeContainer

		prepareInitialState()
		loadConfig()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelModifyModesSheet", owner: self, topLevelObjects: nil)
	}

	private func loadConfig() {
		iCheck.state = modes.modeInfo(for: "i")!.modeIsSet ? .on : .off
		mCheck.state = modes.modeInfo(for: "m")!.modeIsSet ? .on : .off
		nCheck.state = modes.modeInfo(for: "n")!.modeIsSet ? .on : .off
		pCheck.state = modes.modeInfo(for: "p")!.modeIsSet ? .on : .off
		sCheck.state = modes.modeInfo(for: "s")!.modeIsSet ? .on : .off
		tCheck.state = modes.modeInfo(for: "t")!.modeIsSet ? .on : .off

		let kModeInfo = modes.modeInfo(for: "k")!
		kCheck.state = kModeInfo.modeIsSet ? .on : .off

		if kModeInfo.modeIsSet {
			kText.stringValue = kModeInfo.modeParameter ?? ""
		}

		let lModeInfo = modes.modeInfo(for: "l")!
		lCheck.state = lModeInfo.modeIsSet ? .on : .off

		if lModeInfo.modeIsSet {
			channelUserLimitMode = lModeInfo.modeParameter ?? ""
		}

		updateTextFields()
	}

	@objc public func start() {
		startSheet()
	}

	override public func validateValue(_ ioValue: AutoreleasingUnsafeMutablePointer<AnyObject?>, forKey inKey: String)
		throws
	{
		if inKey == "channelUserLimitMode" {
			let stringValue: String = if let value = ioValue.pointee as? String {
				value
			} else if let value = ioValue.pointee as? NSString {
				value as String
			} else {
				""
			}

			var valueInteger = Int(stringValue) ?? 0

			if valueInteger < 0 {
				valueInteger = 0
			} else if valueInteger > 99999 {
				valueInteger = 99999
			}

			ioValue.pointee = "\(valueInteger)" as NSString
		}
	}

	private func updateTextFields() {
		kText.isEnabled = kCheck.state == .on
		lText.isEnabled = lCheck.state == .on
	}

	@IBAction private func onChangeCheck(_ sender: Any?) {
		updateTextFields()

		if sCheck.state == .on, pCheck.state == .on {
			if sender as AnyObject? === sCheck {
				pCheck.state = .off
			} else {
				sCheck.state = .off
			}
		}
	}

	@objc public func controlTextDidChange(_ notification: Notification) {
		if notification.object as AnyObject? === kText {
			updateSecretKeyLengthAlert()
		}
	}

	private func updateSecretKeyLengthAlert() {
		let maximumKeyLength = client.supportInfo.maximumKeyLength

		if maximumKeyLength == 0 {
			return
		}

		let currentKeyLength = kText.stringValue.count

		if currentKeyLength <= maximumKeyLength {
			return
		}

		if secretKeyLengthAlertDisplayed == false {
			secretKeyLengthAlertDisplayed = true
		} else {
			return
		}

		TDCAlert.alertSheet(
			with: sheet,
			body: LocalizedKey("TDCChannelModifyModesSheet[lir-ra]"),
			title: LocalizedKey(
				"TDCChannelModifyModesSheet[7m9-39]",
				client.networkNameAlt,
				maximumKeyLength
			),
			defaultButton: LocalizedKey("Prompts[c7s-dq]"),
			alternateButton: nil,
			otherButton: nil,
			suppressionKey: "maximum_secret_key_length",
			suppressionText: nil,
			completionBlock: nil
		)
	}

	@IBAction override public func ok(_: Any?) {
		modes.changeMode("i", modeIsSet: iCheck.state == .on)
		modes.changeMode("m", modeIsSet: mCheck.state == .on)
		modes.changeMode("n", modeIsSet: nCheck.state == .on)
		modes.changeMode("p", modeIsSet: pCheck.state == .on)
		modes.changeMode("s", modeIsSet: sCheck.state == .on)
		modes.changeMode("t", modeIsSet: tCheck.state == .on)
		modes.changeMode("k", modeIsSet: kCheck.state == .on, modeParameter: kText.stringValue)
		modes.changeMode("l", modeIsSet: lCheck.state == .on, modeParameter: lText.stringValue)

		let selector = NSSelectorFromString("channelModifyModesSheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: modes)
		}

		super.ok(nil)
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("channelModifyModesSheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
