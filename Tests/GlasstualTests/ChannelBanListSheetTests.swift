/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel access list")
struct ChannelBanListSheetTests {
	private func entry(mask: String, author: String, created: Date?) -> ChannelBanListSheetEntry {
		var entry = ChannelBanListSheetEntry()
		entry.entryMask = mask
		entry.entryAuthor = author
		entry.entryCreationDate = created
		return entry
	}

	/// `MAXLIST` is whatever the server put in `ISUPPORT`, and a limit that
	/// did not fit an `Int` used to end the process while opening the sheet.
	@Test("A ban limit too large for the sheet is saturated rather than fatal")
	func oversizedListLimitIsSaturated() throws {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData(
			"CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ MAXLIST=b:18446744073709551615"
		)
		let channel = try #require(client.findChannelOrCreate("#limits"))
		channel.activate()

		let sheet = try #require(ChannelBanListSheet(entryType: .ban, inChannel: channel))

		#expect(sheet.model.maximumEntries == .max)
	}

	/** A server can withdraw an ISUPPORT token mid-session with a `-` prefixed
	 one, and a reconnect resets the set wholesale — either can happen while the
	 sheet is open. The sheet names no mode then, and asking the client to
	 change one compiles to nothing rather than ending the process. */
	@Test("A list mode the server stops advertising leaves the sheet with no symbol")
	func withdrawnListModeLeavesNoSymbol() throws {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(client.findChannelOrCreate("#withdrawn"))
		channel.activate()
		let sheet = try #require(ChannelBanListSheet(entryType: .banException, inChannel: channel))

		#expect(sheet.modeSymbol?.description == "e")

		client.supportInfo.processConfigurationData("-EXCEPTS")

		#expect(sheet.modeSymbol == nil)

		let changes = client.compileListOfModeChanges(
			forModeSymbol: sheet.modeSymbol?.description ?? "",
			modeIsSet: false,
			modeParameters: ["*!*@example.test"]
		)

		#expect(changes.isEmpty)
	}

	@Test("The native table starts with the newest entry first")
	func newestEntryIsFirst() {
		let model = ChannelBanListModel()
		let older = entry(mask: "*!*@old.example", author: "alice", created: Date(timeIntervalSince1970: 100))
		let newer = entry(mask: "*!*@new.example", author: "bob", created: Date(timeIntervalSince1970: 200))

		model.add(older)
		model.add(newer)

		#expect(model.entries.map(\.entryMask) == ["*!*@new.example", "*!*@old.example"])
	}

	@Test("The selected masks follow the visible table order")
	func selectedMasksFollowVisibleOrder() {
		let model = ChannelBanListModel()
		let first = entry(mask: "*!*@one.example", author: "alice", created: nil)
		let second = entry(mask: "*!*@two.example", author: "bob", created: nil)
		model.entries = [first, second]
		model.selection = [first.id, second.id]

		#expect(model.selectedMasks == ["*!*@one.example", "*!*@two.example"])
	}

	@Test("The count includes the server's maximum when one is advertised")
	func countIncludesMaximum() {
		let model = ChannelBanListModel()
		model.maximumEntries = 100
		model.entries = [entry(mask: "*!*@example", author: "alice", created: nil)]

		#expect(model.entryCountDescription == "1 of 100 entries")
	}

	@Test("Clearing removes entries and selection without ending a refresh")
	func clearPreservesRefreshState() {
		let model = ChannelBanListModel()
		let value = entry(mask: "*!*@example", author: "alice", created: nil)
		model.entries = [value]
		model.selection = [value.id]
		model.isRefreshing = true

		model.clear()

		#expect(model.entries.isEmpty)
		#expect(model.selection.isEmpty)
		#expect(model.isRefreshing)
	}

	@Test("The legacy access-list nib is no longer bundled")
	func legacyNibIsRemoved() {
		#expect(Bundle.main.path(forResource: "TDCChannelBanListSheet", ofType: "nib") == nil)
	}
}
