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

@objc(TDCChannelInviteSheet)
@MainActor
public final class ChannelInviteSheet: SheetBase {
	@objc public private(set) var client: IRCClient!
	@objc public private(set) var clientId: String = ""
	@objc public private(set) var nicknames: [String] = []

	@IBOutlet private var headerTitleTextField: NSTextField!
	@IBOutlet private var channelListPopup: NSPopUpButton!

	@objc(initWithNicknames:onClient:)
	public init(nicknames: [String], on client: IRCClient) {
		super.init(window: nil)
		self.nicknames = nicknames
		self.client = client
		clientId = client.uniqueIdentifier
		prepareInitialState()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCChannelInviteSheet", owner: self, topLevelObjects: nil)

		let nicknameCount = nicknames.count
		let headerTitle: String = if nicknameCount == 1 {
			nicknames[0]
		} else if nicknameCount == 2 {
			LocalizedKey("TDCChannelInviteSheet[7i1-ds]", nicknames[0], nicknames[1])
		} else {
			LocalizedKey("TDCChannelInviteSheet[c8p-sb]", nicknameCount)
		}

		headerTitleTextField.stringValue = LocalizedKey("TDCChannelInviteSheet[0lg-er]", headerTitle)
	}

	@objc(startWithChannels:)
	public func start(withChannels channels: [String]) {
		for channel in channels {
			channelListPopup.addItem(withTitle: channel)
		}

		startSheet()
	}

	@IBAction override public func ok(_: Any?) {
		let selector = NSSelectorFromString("channelInviteSheet:onSelectChannel:")

		if let delegate, delegate.responds(to: selector) {
			let channelName = channelListPopup.titleOfSelectedItem
			_ = delegate.perform(selector, with: self, with: channelName)
		}

		super.ok(nil)
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("channelInviteSheetWillClose:")

		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
