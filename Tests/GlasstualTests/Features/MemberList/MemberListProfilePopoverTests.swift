// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// The profile a click opens, and the rank the row draws it for. Both used to
/// be answered per row, which is why a click on one member showed another's
/// profile and why the glyph and the label could disagree.
@MainActor
@Suite("Member list profile and rank")
struct MemberListProfilePopoverTests {
	private let session: TestServerSession
	private let memberList: MemberList
	private let channel: Conversation

	init() {
		let session = TestServerSession()
		let memberList = MemberList()
		let channel = Conversation(config: ConversationConfig(name: "#profile"))
		channel.associatedSession = session
		channel.activate()
		memberList.assign(to: channel)

		self.session = session
		self.memberList = memberList
		self.channel = channel
	}

	/// The profile used to wait out the double-click interval, which follows
	/// the reader's Double-click speed and can be seconds.
	@Test("A click opens the profile at once, and a click on another member replaces it")
	func aClickOpensTheProfileAtOnce() throws {
		let alice = try add("alice")
		let bob = try add("bob")

		memberList.showProfile(for: alice.id)
		#expect(memberList.memberShowingProfile == alice.id)

		memberList.showProfile(for: bob.id)
		#expect(memberList.memberShowingProfile == bob.id)
	}

	@Test("The double click that opens the conversation takes the profile down")
	func aDoubleClickHidesTheProfile() throws {
		let alice = try add("alice")

		memberList.showProfile(for: alice.id)
		memberList.hideProfile()

		#expect(memberList.memberShowingProfile == nil)
	}

	@Test("Dismissing one member's profile leaves another's alone")
	func dismissingIsAddressedToOneMember() throws {
		let alice = try add("alice")
		let bob = try add("bob")

		memberList.showProfile(for: alice.id)
		memberList.endProfileInteraction(with: bob.id)
		#expect(memberList.memberShowingProfile == alice.id)

		memberList.endProfileInteraction(with: alice.id)
		#expect(memberList.memberShowingProfile == nil)
	}

	@Test("A member who leaves takes their profile with them")
	func leavingClosesTheProfile() throws {
		let alice = try add("alice")

		memberList.showProfile(for: alice.id)
		channel.removeMember(withNickname: "alice")

		#expect(memberList.memberShowingProfile == nil)
	}

	/// The glyph honoured the setting and the label did not, so a server
	/// operator was drawn as staff and described as an ordinary member.
	@Test("One rank answers for the glyph, the tooltip and the popover")
	func staffPreferenceReachesEveryDescription() {
		/* Written and read back through the same detached handle the rows use,
		 so the test is not asking one handle whether another's write landed. */
		let key = SettingsKeys.Appearance.memberListSortFavorsServerStaff
		let previous = key.detachedStoredValue
		defer { key.detachedStoredValue = previous }

		var user = User(nickname: "carol")
		user.isIRCop = true
		let member = Member(user: user, prefixes: session.currentUserPrefixes)

		key.detachedValue = true
		#expect(MemberListRanks.displayRank(for: member) == .irCopByMode)
		#expect(MemberListRanks.privilegeDescription(for: member)
			== MemberListRanks.privilegeDescription(for: .irCopByMode))

		key.detachedValue = false
		#expect(MemberListRanks.displayRank(for: member) == member.rank)
		#expect(MemberListRanks.privilegeDescription(for: member)
			== MemberListRanks.privilegeDescription(for: member.rank))
	}

	/// "Use an x to indicate a user with no mode set" had no reader at all.
	@Test("The no-mode mark is drawn only when the preference asks for it")
	func noModeSymbolFollowsThePreference() {
		let key = SettingsKeys.Appearance.memberListNoModeSymbol
		let previous = key.detachedStoredValue
		defer { key.detachedStoredValue = previous }

		key.detachedValue = true
		#expect(MemberListPresentationStyle.current().symbolName(for: UserRank.none) != nil)
		#expect(MemberListPresentationStyle.current().symbolName(for: .voiced) == "mic.fill")

		key.detachedValue = false
		#expect(MemberListPresentationStyle.current().symbolName(for: UserRank.none) == nil)
		#expect(MemberListPresentationStyle.current().symbolName(for: .voiced) == "mic.fill")
	}

	/** The rows read their settings once, out of a snapshot the list hands
	 down. Three reads per row per redraw — glyph, tooltip, label — each built
	 its own handle on the defaults suite, on every row of a channel that
	 rebuilds on each join, part and mode change. */
	@Test("One snapshot answers for every row, and it changes when the preferences do")
	func presentationStyleIsOneSnapshotOfThePreferences() {
		let staff = SettingsKeys.Appearance.memberListSortFavorsServerStaff
		let noMode = SettingsKeys.Appearance.memberListNoModeSymbol
		let previousStaff = staff.detachedStoredValue
		let previousNoMode = noMode.detachedStoredValue
		defer {
			staff.detachedStoredValue = previousStaff
			noMode.detachedStoredValue = previousNoMode
		}

		staff.detachedValue = true
		noMode.detachedValue = true
		let favouring = MemberListPresentationStyle.current()
		#expect(favouring.favorsServerStaff)
		#expect(favouring.marksMembersWithNoMode)
		#expect(favouring.displayRank(isIRCOperator: true, channelRank: .voiced) == .irCopByMode)
		#expect(favouring.displayRank(isIRCOperator: false, channelRank: .voiced) == .voiced)

		staff.detachedValue = false
		noMode.detachedValue = false
		let plain = MemberListPresentationStyle.current()
		#expect(plain.displayRank(isIRCOperator: true, channelRank: .voiced) == .voiced)
		#expect(plain.symbolName(for: UserRank.none) == nil)
		#expect(plain != favouring)
	}

	@discardableResult
	private func add(_ nickname: String) throws -> Member {
		let user = session.findUserOrCreate(nickname)
		channel.addMember(Member(user: user, prefixes: session.currentUserPrefixes))

		return try #require(channel.findMember(nickname))
	}
}
