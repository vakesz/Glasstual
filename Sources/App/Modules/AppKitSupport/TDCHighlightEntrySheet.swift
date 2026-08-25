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

@objc(TDCHighlightEntrySheet)
@MainActor
public final class HighlightEntrySheet: SheetBase {
	private var config: MutableHighlightMatchCondition!
	private var channelList: [ChannelConfig] = []

	@IBOutlet private var matchKeywordTextField: TVCValidatedTextField!
	@IBOutlet private var matchTypePopupButton: NSPopUpButton!
	@IBOutlet private var matchChannelPopupButton: NSPopUpButton!

	@objc(initWithConfig:)
	public init(config: HighlightMatchCondition?) {
		super.init(window: nil)

		if let config {
			self.config = config.mutableCopy() as? MutableHighlightMatchCondition
		} else {
			self.config = MutableHighlightMatchCondition()
		}

		prepareInitialState()
		loadConfig()
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCHighlightEntrySheet", owner: self, topLevelObjects: nil)

		matchKeywordTextField.stringValueUsesOnlyFirstToken = false
		matchKeywordTextField.stringValueIsInvalidOnEmpty = true
		matchKeywordTextField.stringValueIsTrimmed = true
		matchKeywordTextField.textDidChangeCallback = self
	}

	private func loadConfig() {
		matchKeywordTextField.stringValue = config.matchKeyword

		if config.matchIsExcluded == false {
			matchTypePopupButton.selectItem(withTag: 1)
		} else {
			matchTypePopupButton.selectItem(withTag: 2)
		}
	}

	@objc(startWithChannels:)
	public func start(with channels: [ChannelConfig]) {
		channelList = channels

		let matchChannelId = config.matchChannelId
		var channelCount = 0

		let channelMenu = matchChannelPopupButton.menu

		for channel in channelList {
			let item = NSMenuItem(title: channel.channelName, action: nil, keyEquivalent: "")
			item.representedObject = channel.uniqueIdentifier
			channelMenu?.addItem(item)

			if channel.uniqueIdentifier == matchChannelId {
				matchChannelPopupButton.select(item)
			}

			channelCount += 1
		}

		if channelCount == 0 {
			matchChannelPopupButton.removeItem(at: 1)
		}

		startSheet()
		sheet.makeFirstResponder(matchKeywordTextField)
	}

	@IBAction override public func ok(_ sender: Any?) {
		guard okOrError() else {
			return
		}

		config.matchIsExcluded = (matchTypePopupButton.selectedTag() == 2)
		config.matchKeyword = matchKeywordTextField.value

		if let selectedChannelId = matchChannelPopupButton.selectedItem?.representedObject as? String {
			config.matchChannelId = selectedChannelId
		} else {
			config.matchChannelId = nil
		}

		let selector = NSSelectorFromString("highlightEntrySheet:onOk:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self, with: config.copy())
		}

		super.ok(sender)
	}

	@objc public func okOrError() -> Bool {
		okOrError(for: matchKeywordTextField)
	}

	@objc public func windowWillClose(_: Notification) {
		let selector = NSSelectorFromString("highlightEntrySheetWillClose:")
		if let delegate, delegate.responds(to: selector) {
			_ = delegate.perform(selector, with: self)
		}
	}
}
