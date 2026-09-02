/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Observation

@Observable
final class AddressBookEntryModel {
	let entryType: IRCAddressBookEntryType

	var hostmask: String {
		didSet { validationMessage = nil }
	}

	var ignoreClientToClientProtocol: Bool
	var ignoreFileTransferRequests: Bool
	var ignoreGeneralEventMessages: Bool
	var ignoreInlineMedia: Bool
	var ignoreNoticeMessages: Bool
	var ignorePrivateMessageHighlights: Bool
	var ignorePrivateMessages: Bool
	var ignorePublicMessageHighlights: Bool
	var ignorePublicMessages: Bool
	var trackUserActivity: Bool

	private(set) var validationMessage: String?
	private let source: AddressBookEntry

	convenience init(entryType: IRCAddressBookEntryType) {
		self.init(entry: entryType == .userTracking
			? .newUserTrackingEntry()
			: .newIgnoreEntry())
	}

	init(entry: AddressBookEntry) {
		source = entry
		entryType = entry.entryType
		hostmask = entry.hostmask
		ignoreClientToClientProtocol = entry.ignoreClientToClientProtocol
		ignoreFileTransferRequests = entry.ignoreFileTransferRequests
		ignoreGeneralEventMessages = entry.ignoreGeneralEventMessages
		ignoreInlineMedia = entry.ignoreInlineMedia
		ignoreNoticeMessages = entry.ignoreNoticeMessages
		ignorePrivateMessageHighlights = entry.ignorePrivateMessageHighlights
		ignorePrivateMessages = entry.ignorePrivateMessages
		ignorePublicMessageHighlights = entry.ignorePublicMessageHighlights
		ignorePublicMessages = entry.ignorePublicMessages
		trackUserActivity = entry.trackUserActivity
	}

	var title: String {
		switch entryType {
		case .ignore, .mixed: AddressBookStrings.ignoreUser
		case .userTracking: AddressBookStrings.trackUser
		}
	}

	func validatedEntry() -> AddressBookEntry? {
		let value = hostmask.firstToken
		/* An empty hostmask is neither a mask nor a nickname, so the validator
		 already refuses it with a message of its own. */
		if let error = validationError(for: value) {
			validationMessage = error
			return nil
		}

		var entry = source
		entry.hostmask = value

		switch entryType {
		case .ignore, .mixed:
			entry.ignoreClientToClientProtocol = ignoreClientToClientProtocol
			entry.ignoreFileTransferRequests = ignoreFileTransferRequests
			entry.ignoreGeneralEventMessages = ignoreGeneralEventMessages
			entry.ignoreInlineMedia = ignoreInlineMedia
			entry.ignoreNoticeMessages = ignoreNoticeMessages
			entry.ignorePrivateMessageHighlights = ignorePrivateMessageHighlights
			entry.ignorePrivateMessages = ignorePrivateMessages
			entry.ignorePublicMessageHighlights = ignorePublicMessageHighlights
			entry.ignorePublicMessages = ignorePublicMessages
		case .userTracking:
			entry.trackUserActivity = trackUserActivity
		}

		validationMessage = nil
		return entry
	}

	private func validationError(for value: String) -> String? {
		switch entryType {
		case .ignore, .mixed:
			let valueWithoutWildcard = value.replacingOccurrences(of: "*", with: "-")
			return (valueWithoutWildcard as NSString).isHostmask
				? nil
				: AddressBookStrings.invalidIgnoreMask
		case .userTracking:
			return (value as NSString).isHostmaskNickname
				? nil
				: CommonValidationStrings.invalidNickname
		}
	}
}
