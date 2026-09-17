// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Address book entry sheet")
struct AddressBookSheetTests {
	@Test("A new ignore rule starts with every supported message type selected")
	func newIgnoreRuleDefaults() {
		let model = AddressBookEntryModel(entryType: .ignore)

		#expect(model.ignoreClientToClientProtocol)
		#expect(model.ignoreFileTransferRequests)
		#expect(model.ignoreGeneralEventMessages)
		#expect(model.ignoreInlineMedia)
		#expect(model.ignoreNoticeMessages)
		#expect(model.ignorePrivateMessageHighlights)
		#expect(model.ignorePrivateMessages)
		#expect(model.ignorePublicMessageHighlights)
		#expect(model.ignorePublicMessages)
	}

	@Test("Editing the draft does not mutate the source entry")
	func editingIsTransactional() {
		let source = AddressBookEntry.newIgnoreEntry(forHostmask: "old!user@example.com")
		let model = AddressBookEntryModel(entry: source)

		model.hostmask = "new!user@example.com"
		model.ignorePublicMessages = false

		#expect(source.hostmask == "old!user@example.com")
		#expect(source.ignorePublicMessages)
	}

	@Test("Submission keeps only the first token and applies the ignore selections")
	func validatedIgnoreEntry() throws {
		let source = AddressBookEntry.newIgnoreEntry(forHostmask: "old!user@example.com")
		let model = AddressBookEntryModel(entry: source)
		model.hostmask = "nick!*@example.com ignored-text"
		model.ignoreInlineMedia = false

		let entry = try #require(model.validatedEntry())

		#expect(entry.uniqueIdentifier == source.uniqueIdentifier)
		#expect(entry.hostmask == "nick!*@example.com")
		#expect(entry.ignoreInlineMedia == false)
		#expect(model.validationMessage == nil)
	}

	@Test("An invalid ignore mask stays in the editor with a visible error")
	func invalidIgnoreEntry() {
		let model = AddressBookEntryModel(entryType: .ignore)
		model.hostmask = "not-a-hostmask"

		#expect(model.validatedEntry() == nil)
		#expect(model.validationMessage == String(localized: .AddressBook.pleaseEnterAProperlyFormattedIgnore))
	}

	@Test("A tracking rule validates a nickname and preserves its notification choice")
	func trackingEntry() throws {
		let model = AddressBookEntryModel(entryType: .userTracking)
		model.hostmask = "vakesz extra"
		model.trackUserActivity = false

		let entry = try #require(model.validatedEntry())

		#expect(entry.entryType == .userTracking)
		#expect(entry.hostmask == "vakesz")
		#expect(entry.trackUserActivity == false)
	}

	/// A mixed entry both ignores and tracks. It opened as a plain ignore, so
	/// its tracking setting could be neither seen nor changed.
	@Test("A mixed rule edits both what it ignores and whether it tracks")
	func mixedEntryEditsBothHalves() throws {
		var source = AddressBookEntry(entryType: .mixed, hostmask: "*!*@example.com")
		source.trackUserActivity = true
		source.ignorePublicMessages = false
		let model = AddressBookEntryModel(entry: source)

		#expect(model.editsIgnoreSettings)
		#expect(model.editsTracking)

		model.trackUserActivity = false
		model.ignorePublicMessages = true
		let entry = try #require(model.validatedEntry())

		#expect(entry.entryType == .mixed)
		#expect(entry.trackUserActivity == false)
		#expect(entry.ignorePublicMessages)
	}

	@Test("Invalid nickname copy comes from the shared validation catalog")
	func invalidTrackingNickname() {
		let model = AddressBookEntryModel(entryType: .userTracking)
		model.hostmask = "bad@nick"

		#expect(model.validatedEntry() == nil)
		#expect(model.validationMessage == CommonValidationStrings.invalidNickname)
	}

	@Test("The sheet reports the entry it accepted")
	func sheetReportsTheAcceptedEntry() throws {
		var submitted: AddressBookEntry?
		let sheet = AddressBookEntrySheet(entryType: .userTracking) { submitted = $0 }
		sheet.model.hostmask = "vakesz"

		sheet.submit()
		#expect(try #require(submitted).hostmask == "vakesz")
	}
}
