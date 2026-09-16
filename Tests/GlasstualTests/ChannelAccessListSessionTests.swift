/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel access list")
struct ChannelAccessListSessionTests {
	private func entry(mask: String, author: String, created: Date?) -> ChannelBanListSheetEntry {
		var entry = ChannelBanListSheetEntry()
		entry.entryMask = mask
		entry.entryAuthor = author
		entry.entryCreationDate = created
		return entry
	}

	/// `MAXLIST` is whatever the server put in `ISUPPORT`, and a limit that
	/// did not fit an `Int` used to end the process while opening the list.
	@Test("A ban limit too large for the list is saturated rather than fatal")
	func oversizedListLimitIsSaturated() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData(
			"CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ MAXLIST=b:18446744073709551615"
		)
		let channel = try #require(client.findChannelOrCreate("#limits"))
		channel.activate()

		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))

		#expect(session.model.maximumEntries == .max)
	}

	/** The list is a window now, and a window that is open across a refresh has
	 to show one reply at a time: the rows the previous one left are held until
	 the next reply starts arriving, so a refresh never blanks the table before
	 the new list lands. */
	@Test("A reply arriving after the last one finished replaces the rows")
	func aNewReplyReplacesTheRows() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#refresh"))
		channel.activate()
		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))

		session.receiveEntry(mask: "*!*@first.example", setBy: "alice", creationDate: nil)
		session.finishReceiving()
		#expect(session.model.isRefreshing == false)

		session.receiveEntry(mask: "*!*@second.example", setBy: "bob", creationDate: nil)

		#expect(session.model.entries.map(\.entryMask) == ["*!*@second.example"])
		#expect(session.model.isRefreshing)
	}

	/** Removing entries used to close the sheet, so removing two meant opening
	 the list twice. The window drops the rows it asked the server to unset and
	 stays open for the next removal. */
	@Test("Removing the selected masks drops their rows and keeps the list")
	func removingSelectedMasksKeepsTheList() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#removal"))
		channel.activate()
		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))
		session.receiveEntry(mask: "*!*@kept.example", setBy: "alice", creationDate: nil)
		session.receiveEntry(mask: "*!*@gone.example", setBy: "bob", creationDate: nil)
		let doomed = try #require(session.model.entries.first { $0.entryMask == "*!*@gone.example" })
		session.model.selection = [doomed.id]

		session.removeSelectedEntries()

		#expect(session.model.entries.map(\.entryMask) == ["*!*@kept.example"])
		#expect(session.model.selection.isEmpty)
	}

	/** A server can withdraw an ISUPPORT token mid-session with a `-` prefixed
	 one, and a reconnect resets the set wholesale — either can happen while the
	 window is open. The session names no mode then, and asking the client to
	 change one compiles to nothing rather than ending the process. */
	@Test("A list mode the server stops advertising leaves the session with no symbol")
	func withdrawnListModeLeavesNoSymbol() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(client.findChannelOrCreate("#withdrawn"))
		channel.activate()
		let session = try #require(ChannelAccessListSession(entryType: .banException, in: channel))

		#expect(session.modeSymbol?.description == "e")

		client.supportInfo.processConfigurationData("-EXCEPTS")

		#expect(session.modeSymbol == nil)

		let changes = client.compileListOfModeChanges(
			forModeSymbol: session.modeSymbol?.description ?? "",
			modeIsSet: false,
			modeParameters: ["*!*@example.test"]
		)

		#expect(changes.isEmpty)
		#expect(session.matches(client: client, channelName: "#withdrawn", modeSymbol: "e") == false)
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

	/** Each arriving entry used to re-sort the whole list, which was quadratic
	 over a reply of up to twenty thousand lines. Inserting in place has to give
	 the same order the sort did, ties included. */
	@Test("Entries arriving out of order land where a full sort would put them")
	func arrivingEntriesAreInsertedInSortedOrder() {
		let model = ChannelBanListModel()
		model.sortOrder = [
			ChannelBanListComparator(field: .author, order: .forward),
			ChannelBanListComparator(field: .creationDate, order: .reverse),
		]
		let arrivals = [
			entry(mask: "a", author: "carol", created: Date(timeIntervalSince1970: 10)),
			entry(mask: "b", author: "alice", created: Date(timeIntervalSince1970: 30)),
			entry(mask: "c", author: "bob", created: nil),
			entry(mask: "d", author: "alice", created: Date(timeIntervalSince1970: 50)),
			entry(mask: "e", author: "bob", created: nil),
			entry(mask: "f", author: "Alice", created: Date(timeIntervalSince1970: 40)),
		]

		for arrival in arrivals {
			model.add(arrival)
		}

		#expect(model.entries.map(\.entryMask) == ["d", "f", "b", "c", "e", "a"])
		#expect(model.entries == arrivals.sorted(using: model.sortOrder))
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

	/** A list nobody has pruned in years is longer than the window will hold,
	 and the count above the table used to read as the whole of it: `20,000 of
	 20,000 entries` for a list the server was still sending. What was dropped
	 was counted and never said. */
	@Test("A list cut at the cap says so instead of claiming to be complete")
	func aTruncatedListSaysSo() {
		let model = ChannelBanListModel()
		model.maximumEntries = 50000

		/* Assigned rather than added one at a time: `add` sorts on every row, and
		 the point here is what the model says once it is full, not how it got
		 there. */
		model.entries = (0 ..< ChannelBanListModel.maximumRetainedEntries).map {
			entry(mask: "*!*@host\($0).example", author: "alice", created: nil)
		}

		for index in 0 ..< 3 {
			model.add(entry(mask: "*!*@overflow\(index).example", author: "alice", created: nil))
		}

		#expect(model.entries.count == ChannelBanListModel.maximumRetainedEntries)
		#expect(model.discardedEntryCount == 3)
		#expect(model.truncationNotice != nil)
		// Naming the server's MAXLIST here would read as the list being all of it.
		#expect(model.entryCountDescription.contains(formattedNumber(50000)) == false)
	}

	/// Nothing was dropped, so nothing warns about it and the count is the
	/// comparison against `MAXLIST` it has always been.
	@Test("A list inside the cap carries no truncation notice")
	func anUntruncatedListCarriesNoNotice() {
		let model = ChannelBanListModel()
		model.maximumEntries = 100
		model.add(entry(mask: "*!*@example", author: "alice", created: nil))

		#expect(model.discardedEntryCount == 0)
		#expect(model.truncationNotice == nil)
		#expect(model.entryCountDescription == "1 of 100 entries")
	}

	/** Asking for the list again used to blank the table and only then send the
	 request, which left the window empty for the round trip -- the very thing
	 holding the rows across a reply was meant to prevent. The rows stay up
	 until the first entry of the new reply arrives. */
	@Test("A refresh keeps the rows up until the new reply starts arriving")
	func refreshingKeepsTheRowsUntilTheReplyStarts() throws {
		let client = TestClient()
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#hold"))
		channel.activate()
		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))
		session.receiveEntry(mask: "*!*@first.example", setBy: "alice", creationDate: nil)
		session.finishReceiving()

		session.updateList()

		#expect(session.model.entries.map(\.entryMask) == ["*!*@first.example"])
		#expect(session.model.isRefreshing)

		session.receiveEntry(mask: "*!*@second.example", setBy: "bob", creationDate: nil)

		#expect(session.model.entries.map(\.entryMask) == ["*!*@second.example"])
	}

	@Test("An empty refresh removes the previous reply's rows and selection")
	func emptyRefreshReplacesPreviousReply() throws {
		let client = TestClient()
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(client.findChannelOrCreate("#empty"))
		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))
		session.receiveEntry(mask: "*!*@old.example", setBy: "alice", creationDate: nil)
		session.finishReceiving()
		session.model.selection = Set(session.model.entries.map(\.id))
		// A duplicate completion must not erase a completed, nonempty reply.
		session.finishReceiving()
		#expect(session.model.entries.count == 1)

		session.updateList()
		#expect(session.model.entries.count == 1)
		session.finishReceiving()

		#expect(session.model.entries.isEmpty)
		#expect(session.model.selection.isEmpty)
		#expect(session.model.isRefreshing == false)
	}

	/** The reply reaches the window through a seam it shares with the transcript
	 and used to carry nothing but the mask, so whichever list was current took
	 it: a window open on `#one`'s bans filled with `#two`'s. The channel and the
	 mode letter travel with the entry now, and a list takes only its own. */
	@Test("A list ignores entries for another channel or another of its modes")
	func entriesForAnotherListAreIgnored() throws {
		let client = TestClient()
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(client.findChannelOrCreate("#Mine"))
		channel.activate()
		let session = try #require(ChannelAccessListSession(entryType: .ban, in: channel))

		#expect(session.matches(client: client, channelName: "#Mine", modeSymbol: "b"))
		// RFC 1459 casemapping is what decides whether two spellings are one channel.
		#expect(session.matches(client: client, channelName: "#mine", modeSymbol: "b"))
		#expect(session.matches(client: client, channelName: "#theirs", modeSymbol: "b") == false)
		#expect(session.matches(client: client, channelName: "#Mine", modeSymbol: "e") == false)
		/* The seam is one object for every connection, so another connection's
		 channel of the same name is not this list's either. */
		let otherClient = TestClient()
		otherClient.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		#expect(session.matches(client: otherClient, channelName: "#Mine", modeSymbol: "b") == false)
	}

	@Test("The legacy access-list nib is no longer bundled")
	func legacyNibIsRemoved() {
		#expect(Bundle.main.path(forResource: "TDCChannelBanListSheet", ofType: "nib") == nil)
	}
}
