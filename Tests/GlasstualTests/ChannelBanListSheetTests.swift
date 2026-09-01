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
