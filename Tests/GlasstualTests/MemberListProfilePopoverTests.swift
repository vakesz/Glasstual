/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import GlasstualPluginKit
import Testing

/// The profile a click opens, and the rank the row draws it for. Both used to
/// be answered per row, which is why a click on one member showed another's
/// profile and why the glyph and the label could disagree.
@MainActor
@Suite("Member list profile and rank")
struct MemberListProfilePopoverTests {
	private let client: GLTTestClient
	private let memberList: MemberList
	private let channel: IRCChannel

	init() {
		let client = GLTTestClient()
		let memberList = MemberList()
		let channel = IRCChannel(config: ChannelConfig(channelName: "#profile"))
		channel.associatedClient = client
		channel.activate()
		memberList.assign(to: channel)

		self.client = client
		self.memberList = memberList
		self.channel = channel
	}

	@Test("A click on a second member replaces the first one's wait")
	func aSecondClickReplacesThePendingProfile() async throws {
		let alice = try add("alice")
		let bob = try add("bob")

		memberList.scheduleProfile(for: alice.id, after: .milliseconds(20))
		memberList.scheduleProfile(for: bob.id, after: .milliseconds(20))
		try await Task.sleep(for: .milliseconds(200))

		#expect(memberList.memberShowingProfile == bob.id)
	}

	@Test("A click on another member takes the open popover with it")
	func openingAProfileDismissesTheOneBefore() async throws {
		let alice = try add("alice")
		let bob = try add("bob")

		memberList.showProfile(for: alice.id)
		#expect(memberList.memberShowingProfile == alice.id)

		memberList.scheduleProfile(for: bob.id, after: .milliseconds(20))
		/* Not "when the wait is over": the popover the reader clicked past is
		 gone as soon as they click, or their click lands in it instead. */
		#expect(memberList.memberShowingProfile == nil)

		try await Task.sleep(for: .milliseconds(200))
		#expect(memberList.memberShowingProfile == bob.id)
	}

	@Test("The double click that opens the conversation opens no profile")
	func aDoubleClickCancelsTheWait() async throws {
		let alice = try add("alice")

		memberList.scheduleProfile(for: alice.id, after: .milliseconds(20))
		memberList.cancelPendingProfile()
		try await Task.sleep(for: .milliseconds(200))

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

	/// The glyph honoured the preference and the label did not, so a server
	/// operator was drawn as staff and described as an ordinary member.
	@Test("One rank answers for the glyph, the tooltip and the popover")
	func staffPreferenceReachesEveryDescription() {
		/* Written and read back through the same detached handle the rows use,
		 so the test is not asking one handle whether another's write landed. */
		let key = Preferences.Appearance.memberListSortFavorsServerStaff
		let previous = key.detachedStoredValue
		defer { key.detachedStoredValue = previous }

		var user = User(nickname: "carol")
		user.isIRCop = true
		let member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)

		key.detachedValue = true
		#expect(MemberListPresentation.displayRank(for: member) == .irCopByMode)
		#expect(MemberListPresentation.privilegesDescription(for: member)
			== MemberListStrings.privilegeDescription(for: .irCopByMode))

		key.detachedValue = false
		#expect(MemberListPresentation.displayRank(for: member) == member.rank)
		#expect(MemberListPresentation.privilegesDescription(for: member)
			== MemberListStrings.privilegeDescription(for: member.rank))
	}

	/// "Use an x to indicate a user with no mode set" had no reader at all.
	@Test("The no-mode mark is drawn only when the preference asks for it")
	func noModeSymbolFollowsThePreference() {
		let key = Preferences.Appearance.memberListNoModeSymbol
		let previous = key.detachedStoredValue
		defer { key.detachedStoredValue = previous }

		key.detachedValue = true
		#expect(MemberListPresentation.symbolName(for: UserRank.none) != nil)
		#expect(MemberListPresentation.symbolName(for: .voiced) == "mic.fill")

		key.detachedValue = false
		#expect(MemberListPresentation.symbolName(for: UserRank.none) == nil)
		#expect(MemberListPresentation.symbolName(for: .voiced) == "mic.fill")
	}

	@discardableResult
	private func add(_ nickname: String) throws -> ChannelUser {
		let user = client.findUserOrCreate(nickname)
		channel.addMember(ChannelUser(user: user, prefixes: client.currentUserPrefixes))

		return try #require(channel.findMember(nickname))
	}
}
