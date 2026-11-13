// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI

@Observable
final class AddressBookEntryModel {
	let entryType: AddressBookEntryKind

	/** The entry as it is being edited.

	 The sheet binds into this value, so a field added to `AddressBookEntry`
	 reaches the form without a copy step, and a half of the entry the sheet
	 does not show keeps whatever the entry arrived with. */
	var entry: AddressBookEntry

	/// Why the hostmask cannot be saved, once saving has been tried. After a
	/// refused save it follows what is in the field, so it goes as soon as the
	/// mask is one.
	var validationMessage: String? {
		submission.shown(validationError(for: entry.hostmask.firstToken))
	}

	private var submission = SubmissionGate()

	convenience init(entryType: AddressBookEntryKind) {
		self.init(entry: entryType == .userTracking
			? .newUserTrackingEntry()
			: .newIgnoreEntry())
	}

	init(entry: AddressBookEntry) {
		self.entry = entry
		entryType = entry.entryType
	}

	/// Whether the sheet edits what the entry ignores. A mixed entry, which
	/// older releases could write, both ignores and tracks.
	var editsIgnoreSettings: Bool {
		entryType != .userTracking
	}

	/// Whether the sheet edits activity tracking. A mixed entry used to open as
	/// a plain ignore, so its tracking could not be seen or changed.
	var editsTracking: Bool {
		entryType != .ignore
	}

	func validatedEntry() -> AddressBookEntry? {
		submission.attempt()

		let value = entry.hostmask.firstToken
		/* An empty hostmask is neither a mask nor a nickname, so the validator
		 already refuses it with a message of its own. */
		guard validationError(for: value) == nil else { return nil }

		var submitted = entry
		submitted.hostmask = value
		return submitted
	}

	private func validationError(for value: String) -> String? {
		switch entryType {
		case .ignore, .mixed:
			let valueWithoutWildcard = value.replacingOccurrences(of: "*", with: "-")
			return valueWithoutWildcard.isHostmask
				? nil
				: String(localized: .AddressBook.pleaseEnterAProperlyFormattedIgnore)
		case .userTracking:
			return value.isHostmaskNickname
				? nil
				: CommonValidationStrings.invalidNickname
		}
	}
}

/** The copy that changes with the kind of entry the sheet edits.

 The connection sheet lists the same entries, so its wording for them is here
 too: one feature owns what this enum is called, wherever it is drawn. The list
 row and the sheet title are worded differently on purpose -- a row names the
 kind of entry, a title names what the sheet is about to do -- so they keep a
 key each. */
extension AddressBookEntryKind {
	/// What the connection sheet's Address Book list calls this kind of entry.
	var listTitle: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .AddressBook.userIgnore
		case .userTracking: .AddressBook.userTracking
		@unknown default: .AddressBook.userIgnore
		}
	}

	var sheetTitle: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .AddressBook.ignoreUser
		case .userTracking: .AddressBook.trackUser
		}
	}

	var sheetDescription: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .AddressBook.ignoreDescription
		case .userTracking: .AddressBook.trackingDescription
		}
	}

	var identityLabel: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .AddressBook.hostmask
		case .userTracking: .AddressBook.nickname
		}
	}

	var identityPlaceholder: LocalizedStringResource {
		switch self {
		case .ignore, .mixed: .AddressBook.enterAHostmaskToIgnore
		case .userTracking: .AddressBook.enterAnyNicknameToTrack
		}
	}
}
