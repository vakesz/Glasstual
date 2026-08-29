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

/// What `AddressBookSheet` reports back. The entry is a value type, so it
/// cannot travel through `perform(_:with:with:)`.
@MainActor
public protocol AddressBookSheetDelegate: AnyObject {
	func addressBookSheet(_ sender: AddressBookSheet, onOk entry: AddressBookEntry)
	func addressBookSheetWillClose(_ sender: AddressBookSheet)
}

@objc(TDCAddressBookSheet)
@MainActor
public final class AddressBookSheet: SheetBase {
	private var config: AddressBookEntry
	private var entryType: IRCAddressBookEntryType

	@IBOutlet private var ignoreClientToClientProtocolCheck: NSButton!
	@IBOutlet private var ignoreFileTransferRequestsCheck: NSButton!
	@IBOutlet private var ignoreGeneralEventMessagesCheck: NSButton!
	@IBOutlet private var ignoreInlineMediaCheck: NSButton!
	@IBOutlet private var ignoreNoticeMessagesCheck: NSButton!
	@IBOutlet private var ignorePrivateMessageHighlightsCheck: NSButton!
	@IBOutlet private var ignorePrivateMessagesCheck: NSButton!
	@IBOutlet private var ignorePublicMessageHighlightsCheck: NSButton!
	@IBOutlet private var ignorePublicMessagesCheck: NSButton!
	@IBOutlet private var trackUserActivityCheck: NSButton!
	@IBOutlet private var ignoreEntrySaveButton: NSButton!
	@IBOutlet private var userTrackingEntrySaveButton: NSButton!
	@IBOutlet private var ignoreEntryHostmaskTextField: ValidatedTextField!
	@IBOutlet private var userTrackingEntryNicknameTextField: ValidatedTextField!
	@IBOutlet private var ignoreEntryView: NSWindow!
	@IBOutlet private var userTrackingEntryView: NSWindow!

	public init(entryType: IRCAddressBookEntryType) {
		config = entryType == .userTracking
			? AddressBookEntry.newUserTrackingEntry()
			: AddressBookEntry.newIgnoreEntry()
		self.entryType = entryType

		super.init(window: nil)

		prepareInitialState()
		loadConfig()
	}

	public init(config: AddressBookEntry) {
		self.config = config
		entryType = config.entryType

		super.init(window: nil)

		prepareInitialState()
		loadConfig()
	}

	private var entryDelegate: (any AddressBookSheetDelegate)? {
		delegate as? any AddressBookSheetDelegate
	}

	private func prepareInitialState() {
		Bundle.main.loadNibNamed("TDCAddressBookSheet", owner: self, topLevelObjects: nil)

		ignoreEntryHostmaskTextField.stringValueIsInvalidOnEmpty = true
		ignoreEntryHostmaskTextField.stringValueUsesOnlyFirstToken = true
		ignoreEntryHostmaskTextField.validationBlock = { currentValue in
			let valueWithoutWildcard = currentValue.replacingOccurrences(of: "*", with: "-")

			if (valueWithoutWildcard as NSString).isHostmask == false {
				return AddressBookStrings.invalidIgnoreMask
			}

			return nil
		}

		userTrackingEntryNicknameTextField.stringValueIsInvalidOnEmpty = true
		userTrackingEntryNicknameTextField.stringValueUsesOnlyFirstToken = true
		userTrackingEntryNicknameTextField.validationBlock = { currentValue in
			if (currentValue as NSString).isHostmaskNickname == false {
				return CommonValidationStrings.invalidNickname
			}

			return nil
		}
	}

	private func loadConfig() {
		if entryType == .ignore {
			ignoreEntryHostmaskTextField.stringValue = config.hostmask

			ignoreClientToClientProtocolCheck.state = config.ignoreClientToClientProtocol ? .on : .off
			ignoreFileTransferRequestsCheck.state = config.ignoreFileTransferRequests ? .on : .off
			ignoreGeneralEventMessagesCheck.state = config.ignoreGeneralEventMessages ? .on : .off
			ignoreInlineMediaCheck.state = config.ignoreInlineMedia ? .on : .off
			ignoreNoticeMessagesCheck.state = config.ignoreNoticeMessages ? .on : .off
			ignorePrivateMessageHighlightsCheck.state = config.ignorePrivateMessageHighlights ? .on : .off
			ignorePrivateMessagesCheck.state = config.ignorePrivateMessages ? .on : .off
			ignorePublicMessageHighlightsCheck.state = config.ignorePublicMessageHighlights ? .on : .off
			ignorePublicMessagesCheck.state = config.ignorePublicMessages ? .on : .off
		} else if entryType == .userTracking {
			userTrackingEntryNicknameTextField.stringValue = config.hostmask
			trackUserActivityCheck.state = config.trackUserActivity ? .on : .off
		}
	}

	public func start() {
		if entryType == .ignore {
			sheet = ignoreEntryView
			sheet.makeFirstResponder(ignoreEntryHostmaskTextField)
		} else if entryType == .userTracking {
			sheet = userTrackingEntryView
			sheet.makeFirstResponder(userTrackingEntryNicknameTextField)
		}

		startSheet()
	}

	@IBAction override public func ok(_: Any?) {
		guard okOrError() else {
			return
		}

		if entryType == .ignore {
			config.hostmask = ignoreEntryHostmaskTextField.value

			config.ignoreClientToClientProtocol = ignoreClientToClientProtocolCheck.state == .on
			config.ignoreFileTransferRequests = ignoreFileTransferRequestsCheck.state == .on
			config.ignoreGeneralEventMessages = ignoreGeneralEventMessagesCheck.state == .on
			config.ignoreInlineMedia = ignoreInlineMediaCheck.state == .on
			config.ignoreNoticeMessages = ignoreNoticeMessagesCheck.state == .on
			config.ignorePrivateMessageHighlights = ignorePrivateMessageHighlightsCheck.state == .on
			config.ignorePrivateMessages = ignorePrivateMessagesCheck.state == .on
			config.ignorePublicMessageHighlights = ignorePublicMessageHighlightsCheck.state == .on
			config.ignorePublicMessages = ignorePublicMessagesCheck.state == .on
		} else if entryType == .userTracking {
			config.hostmask = userTrackingEntryNicknameTextField.value
			config.trackUserActivity = trackUserActivityCheck.state == .on
		}

		entryDelegate?.addressBookSheet(self, onOk: config)

		super.ok(nil)
	}

	public func okOrError() -> Bool {
		if entryType == .ignore {
			return okOrError(for: ignoreEntryHostmaskTextField)
		}

		if entryType == .userTracking {
			return okOrError(for: userTrackingEntryNicknameTextField)
		}

		return false
	}

	public func windowWillClose(_: Notification) {
		entryDelegate?.addressBookSheetWillClose(self)
	}
}
