// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Channel access list")
struct ChannelMaskListSessionTests {
	private func entry(mask: String, author: String, created: Date?) -> ChannelMaskListEntry {
		var entry = ChannelMaskListEntry()
		entry.entryMask = mask
		entry.entryAuthor = author
		entry.entryCreationDate = created
		return entry
	}

	/// `MAXLIST` is whatever the server put in `ISUPPORT`, and a limit that
	/// did not fit an `Int` used to end the process while opening the list.
	@Test("A ban limit too large for the list is saturated rather than fatal")
	func oversizedListLimitIsSaturated() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData(
			"CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ MAXLIST=b:18446744073709551615"
		)
		let channel = try #require(session.findConversationOrCreate("#limits"))
		channel.activate()

		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))

		#expect(list.model.maximumEntries == .max)
	}

	/** The list is a window now, and a window that is open across a refresh has
	 to show one reply at a time: the rows the previous one left are held until
	 the next reply starts arriving, so a refresh never blanks the table before
	 the new list lands. */
	@Test("A reply arriving after the last one finished replaces the rows")
	func aNewReplyReplacesTheRows() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(session.findConversationOrCreate("#refresh"))
		channel.activate()
		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))

		list.receiveEntry(mask: "*!*@first.example", setBy: "alice", creationDate: nil)
		list.finishReceiving()
		#expect(list.model.isRefreshing == false)

		list.receiveEntry(mask: "*!*@second.example", setBy: "bob", creationDate: nil)

		#expect(list.model.entries.map(\.entryMask) == ["*!*@second.example"])
		#expect(list.model.isRefreshing)
	}

	/// A joined channel on a server that advertises the ban list, with the local
	/// user holding `modes`.
	private func makeList(
		modes: String,
		channelName: String,
		kind: ChannelMaskKind = .ban
	) throws -> (TestServerSession, ChannelMaskListSession) {
		let session = TestServerSession()
		session.userNickname = "local"
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(session.findConversationOrCreate(channelName))
		channel.activate()
		var member = Member(user: session.findUserOrCreate(session.userNickname), prefixes: session.currentUserPrefixes)
		member.modes = ChannelModeSymbolSet(letters: modes)
		channel.addMember(member)
		return try (session, #require(ChannelMaskListSession(maskKind: kind, in: channel)))
	}

	private func sentModeLines(_ session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("MODE ") }
	}

	/** Removing entries used to close the sheet, so removing two meant opening
	 the list twice. The window sends the removal and stays open, and keeps the
	 rows until the refresh that follows shows what the server did. */
	@Test("Removing the selected masks sends the change and keeps the rows for the refresh")
	func removingSelectedMasksKeepsTheRows() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#removal")
		list.receiveEntry(mask: "*!*@kept.example", setBy: "alice", creationDate: nil)
		list.receiveEntry(mask: "*!*@gone.example", setBy: "bob", creationDate: nil)
		let doomed = try #require(list.model.entries.first { $0.entryMask == "*!*@gone.example" })
		list.model.selection = [doomed.id]

		list.removeSelectedEntries()

		#expect(sentModeLines(session).contains { $0.contains("-b") && $0.hasSuffix("*!*@gone.example") })
		#expect(list.model.entries.count == 2)
		list.cancelPendingRefresh()
	}

	@Test("Someone who is not an operator cannot change the list")
	func nonOperatorCannotChange() throws {
		let (session, list) = try makeList(modes: "v", channelName: "#plain")
		list.model.draft = "nick"

		list.submitDraft()

		#expect(list.canEdit == false)
		#expect(sentModeLines(session).isEmpty)
	}

	@Test("A half-operator can change the list on a server that advertises half-operators")
	func halfOperatorCanChange() throws {
		let session = TestServerSession()
		session.userNickname = "local"
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ohv)@%+")
		let channel = try #require(session.findConversationOrCreate("#half"))
		channel.activate()
		var member = Member(user: session.findUserOrCreate(session.userNickname), prefixes: session.currentUserPrefixes)
		member.modes = ChannelModeSymbolSet(letters: "h")
		channel.addMember(member)
		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))

		#expect(list.canEdit)
	}

	@Test("Adding a bare nickname sends a ban on its expanded mask and clears the field")
	func addingSendsTheExpandedMask() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#add")
		list.model.draft = "troll"

		list.submitDraft()

		#expect(sentModeLines(session).contains { $0.contains("+b") && $0.hasSuffix("troll!*@*") })
		#expect(list.model.draft.isEmpty)
		#expect(list.model.issue == nil)
		list.cancelPendingRefresh()
	}

	@Test("The list's own letter is used for exceptions")
	func addingUsesTheListLetter() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#exceptions", kind: .banException)
		list.model.draft = "friend!*@trusted.example"

		list.submitDraft()

		#expect(sentModeLines(session).contains { $0.contains("+e") && $0.hasSuffix("friend!*@trusted.example") })
		list.cancelPendingRefresh()
	}

	@Test("An entry already in the list is refused without sending anything")
	func duplicateIsRefused() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#dupes")
		list.receiveEntry(mask: "troll!*@*", setBy: "alice", creationDate: nil)
		list.model.draft = "TROLL"

		list.submitDraft()

		#expect(list.model.issue == .duplicate)
		#expect(sentModeLines(session).isEmpty)
	}

	@Test("An empty or malformed draft sets an issue and sends nothing")
	func invalidDraftIsRefused() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#invalid")
		list.model.draft = "two words"

		list.submitDraft()

		#expect(list.model.issue == .invalid(.containsWhitespace))
		#expect(sentModeLines(session).isEmpty)
	}

	@Test("Editing the selected entry replaces it in one mode change")
	func editingReplacesInOneChange() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#edit")
		list.receiveEntry(mask: "old!*@*", setBy: "alice", creationDate: nil)
		list.model.selection = Set(list.model.entries.map(\.id))

		list.beginEditingSelectedEntry()
		#expect(list.model.editingMask == "old!*@*")
		#expect(list.model.draft == "old!*@*")

		list.model.draft = "new!*@*"
		list.submitDraft()

		let lines = sentModeLines(session)
		#expect(lines.count == 1)
		#expect(lines.first?.contains("-b+b") == true)
		#expect(lines.first?.hasSuffix("old!*@* new!*@*") == true)
		#expect(list.model.editingMask == nil)
		list.cancelPendingRefresh()
	}

	@Test("Submitting an edit that changes nothing sends nothing")
	func unchangedEditSendsNothing() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#same")
		list.receiveEntry(mask: "same!*@*", setBy: "alice", creationDate: nil)
		list.model.selection = Set(list.model.entries.map(\.id))
		list.beginEditingSelectedEntry()

		list.submitDraft()

		#expect(sentModeLines(session).isEmpty)
		#expect(list.model.editingMask == nil)
	}

	@Test("A refusal after a change becomes an inline issue, and one with no change waiting is left alone")
	func refusalsAreShownInline() throws {
		let (session, list) = try makeList(modes: "o", channelName: "#refused")
		let unrelated = list.receiveRefusal(
			session: session,
			channelName: "#refused",
			numeric: ChannelMaskListRefusal.chanOpPrivsNeeded,
			text: "You're not channel operator"
		)
		#expect(unrelated == false)

		list.model.draft = "troll"
		list.submitDraft()

		#expect(list.receiveRefusal(
			session: session,
			channelName: "#REFUSED",
			numeric: ChannelMaskListRefusal.chanOpPrivsNeeded,
			text: "You're not channel operator"
		))
		#expect(list.model.issue == .notOperator)

		#expect(list.receiveRefusal(
			session: session,
			channelName: "#refused",
			numeric: ChannelMaskListRefusal.banListFull,
			text: "Channel list is full"
		))
		#expect(list.model.issue == .listFull)
		#expect(list.receiveRefusal(
			session: session,
			channelName: "#elsewhere",
			numeric: ChannelMaskListRefusal.banListFull,
			text: "Channel list is full"
		) == false)
		list.cancelPendingRefresh()
	}

	/** A server can withdraw an ISUPPORT token mid-session with a `-` prefixed
	 one, and a reconnect resets the set wholesale — either can happen while the
	 window is open. The session names no mode then, and asking the session to
	 change one compiles to nothing rather than ending the process. */
	@Test("A list mode the server stops advertising leaves the session with no symbol")
	func withdrawnListModeLeavesNoSymbol() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(session.findConversationOrCreate("#withdrawn"))
		channel.activate()
		let list = try #require(ChannelMaskListSession(maskKind: .banException, in: channel))

		#expect(list.modeSymbol?.description == "e")

		session.supportInfo.processConfigurationData("-EXCEPTS")

		#expect(list.modeSymbol == nil)

		let changes = session.compileListOfModeChanges(
			forModeSymbol: list.modeSymbol?.description ?? "",
			modeIsSet: false,
			modeParameters: ["*!*@example.test"]
		)

		#expect(changes.isEmpty)
		#expect(list.matches(session: session, channelName: "#withdrawn", modeSymbol: "e") == false)
	}

	@Test("The native table starts with the newest entry first")
	func newestEntryIsFirst() {
		let model = ChannelMaskListModel()
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
		let model = ChannelMaskListModel()
		model.sortOrder = [
			ChannelMaskListComparator(field: .author, order: .forward),
			ChannelMaskListComparator(field: .creationDate, order: .reverse),
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
		let model = ChannelMaskListModel()
		let first = entry(mask: "*!*@one.example", author: "alice", created: nil)
		let second = entry(mask: "*!*@two.example", author: "bob", created: nil)
		model.entries = [first, second]
		model.selection = [first.id, second.id]

		#expect(model.selectedMasks == ["*!*@one.example", "*!*@two.example"])
	}

	/** A list nobody has pruned in years is longer than the window will hold,
	 and the count above the table used to read as the whole of it: `20,000 of
	 20,000 entries` for a list the server was still sending. What was dropped
	 was counted and never said. */
	@Test("A list cut at the cap says so instead of claiming to be complete")
	func aTruncatedListSaysSo() {
		let model = ChannelMaskListModel()
		model.maximumEntries = 50000

		/* Assigned rather than added one at a time: `add` sorts on every row, and
		 the point here is what the model says once it is full, not how it got
		 there. */
		model.entries = (0 ..< ChannelMaskListModel.maximumRetainedEntries).map {
			entry(mask: "*!*@host\($0).example", author: "alice", created: nil)
		}

		for index in 0 ..< 3 {
			model.add(entry(mask: "*!*@overflow\(index).example", author: "alice", created: nil))
		}

		#expect(model.entries.count == ChannelMaskListModel.maximumRetainedEntries)
		#expect(model.discardedEntryCount == 3)
		#expect(model.truncationNotice != nil)
		// Naming the server's MAXLIST here would read as the list being all of it.
		#expect(model.entryCountDescription.contains(50000.formatted(.number)) == false)
	}

	/// Nothing was dropped, so nothing warns about it and the count is the
	/// comparison against `MAXLIST` it has always been.
	@Test("A list inside the cap carries no truncation notice")
	func anUntruncatedListCarriesNoNotice() {
		let model = ChannelMaskListModel()
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
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(session.findConversationOrCreate("#hold"))
		channel.activate()
		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))
		list.receiveEntry(mask: "*!*@first.example", setBy: "alice", creationDate: nil)
		list.finishReceiving()

		list.updateList()

		#expect(list.model.entries.map(\.entryMask) == ["*!*@first.example"])
		#expect(list.model.isRefreshing)

		list.receiveEntry(mask: "*!*@second.example", setBy: "bob", creationDate: nil)

		#expect(list.model.entries.map(\.entryMask) == ["*!*@second.example"])
	}

	@Test("An empty refresh removes the previous reply's rows and selection")
	func emptyRefreshReplacesPreviousReply() throws {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(session.findConversationOrCreate("#empty"))
		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))
		list.receiveEntry(mask: "*!*@old.example", setBy: "alice", creationDate: nil)
		list.finishReceiving()
		list.model.selection = Set(list.model.entries.map(\.id))
		// A duplicate completion must not erase a completed, nonempty reply.
		list.finishReceiving()
		#expect(list.model.entries.count == 1)

		list.updateList()
		#expect(list.model.entries.count == 1)
		list.finishReceiving()

		#expect(list.model.entries.isEmpty)
		#expect(list.model.selection.isEmpty)
		#expect(list.model.isRefreshing == false)
	}

	/** The reply reaches the window through a seam it shares with the transcript
	 and used to carry nothing but the mask, so whichever list was current took
	 it: a window open on `#one`'s bans filled with `#two`'s. The channel and the
	 mode letter travel with the entry now, and a list takes only its own. */
	@Test("A list ignores entries for another channel or another of its modes")
	func entriesForAnotherListAreIgnored() throws {
		let session = TestServerSession()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")
		let channel = try #require(session.findConversationOrCreate("#Mine"))
		channel.activate()
		let list = try #require(ChannelMaskListSession(maskKind: .ban, in: channel))

		#expect(list.matches(session: session, channelName: "#Mine", modeSymbol: "b"))
		// RFC 1459 casemapping is what decides whether two spellings are one channel.
		#expect(list.matches(session: session, channelName: "#mine", modeSymbol: "b"))
		#expect(list.matches(session: session, channelName: "#theirs", modeSymbol: "b") == false)
		#expect(list.matches(session: session, channelName: "#Mine", modeSymbol: "e") == false)
		/* The seam is one object for every connection, so another connection's
		 channel of the same name is not this list's either. */
		let otherSession = TestServerSession()
		otherSession.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")

		#expect(list.matches(session: otherSession, channelName: "#Mine", modeSymbol: "b") == false)
	}
}
