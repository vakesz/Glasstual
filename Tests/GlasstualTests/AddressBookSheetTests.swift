/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

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
		#expect(model.validationMessage == AddressBookStrings.invalidIgnoreMask)
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

	@Test("Invalid nickname copy comes from the shared validation catalog")
	func invalidTrackingNickname() {
		let model = AddressBookEntryModel(entryType: .userTracking)
		model.hostmask = "bad@nick"

		#expect(model.validatedEntry() == nil)
		#expect(model.validationMessage == CommonValidationStrings.invalidNickname)
	}

	@Test("The sheet submits through its typed delegate and bundles no nib")
	func nativeSheetAndDelegate() throws {
		let delegate = Delegate()
		let sheet = AddressBookSheet(entryType: .userTracking)
		sheet.delegate = delegate
		sheet.model.hostmask = "vakesz"

		#expect(Bundle.main.path(forResource: "TDCAddressBookSheet", ofType: "nib") == nil)

		sheet.ok(nil)
		let submitted = try #require(delegate.submittedEntry)
		#expect(submitted.hostmask == "vakesz")
	}

	private final class Delegate: NSObject, AddressBookSheetDelegate {
		var submittedEntry: AddressBookEntry?

		func addressBookSheet(_: AddressBookSheet, onOk entry: AddressBookEntry) {
			submittedEntry = entry
		}

		func addressBookSheetWillClose(_: AddressBookSheet) {}
	}
}
