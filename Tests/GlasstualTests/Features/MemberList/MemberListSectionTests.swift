// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Member list sections")
struct MemberListSectionTests {
	private let session: TestServerSession
	private let memberList: MemberList
	private let channel: Conversation

	init() {
		let session = TestServerSession()
		let memberList = MemberList()

		let channel = Conversation(config: ConversationConfig(name: "#members"))
		channel.associatedSession = session
		channel.activate()
		memberList.assign(to: channel)

		self.session = session
		self.memberList = memberList
		self.channel = channel
	}

	@Test("Members of a single rank are shown as a flat list")
	func singleRankIsAFlatList() {
		channel.addMember(makeMember(named: "alice"))
		channel.addMember(makeMember(named: "bob"))

		#expect(memberList.groups.count == 1)
		#expect(memberList.groups.first?.members.count == 2)
		#expect(rowDescriptions == ["alice", "bob"])
	}

	@Test("A second rank gives every section a header row")
	func secondRankAddsHeadersForEverySection() {
		channel.addMember(makeMember(named: "alice"))
		channel.addMember(makeMember(named: "bob"))
		channel.addMember(makeMember(named: "carol", modes: "o"))

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice", "bob"])
		#expect(memberList.groups.map(\.section.rank) == [.normalOperator, .none])
	}

	@Test("Removing the last member of a section drops its header")
	func removingLastMemberOfASectionDropsItsHeader() {
		channel.addMember(makeMember(named: "alice"))
		channel.addMember(makeMember(named: "carol", modes: "o"))
		channel.addMember(makeMember(named: "dave", modes: "v"))

		#expect(rowDescriptions == [
			"[Operators]", "carol", "[Voiced]", "dave", "[Members]", "alice",
		])

		channel.removeMember(withNickname: "dave")

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice"])

		channel.removeMember(withNickname: "carol")

		#expect(rowDescriptions == ["alice"])
		#expect(memberList.groups.first?.members.count == 1)
	}

	@Test("Removing the only member leaves an empty flat list")
	func removingOnlyMemberLeavesAnEmptyFlatList() {
		channel.addMember(makeMember(named: "alice"))

		channel.removeMember(withNickname: "alice")

		#expect(memberList.groups.isEmpty)
		#expect(rowDescriptions.isEmpty)
	}

	@Test("Replacing the contents rebuilds every section")
	func replacingContentsRebuildsSections() {
		replaceContents([
			makeMember(named: "carol", modes: "o"),
			makeMember(named: "alice"),
			makeMember(named: "bob"),
		])

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice", "bob"])

		replaceContents([])

		#expect(memberList.groups.isEmpty)
	}

	@Test("Selection resolves only member identities in presentation order")
	func selectionResolvesMemberIdentities() throws {
		channel.addMember(makeMember(named: "alice"))
		channel.addMember(makeMember(named: "carol", modes: "o"))

		let carol = try #require(channel.findMember("carol"))
		let alice = try #require(channel.findMember("alice"))
		memberList.selectedMemberIDs = [alice.id, carol.id, UUID()]
		#expect(selectedNicknames == ["carol", "alice"])
	}

	// MARK: - Snapshot diffs

	@Test("A join keeps the order and the person who was selected")
	func joinKeepsOrderAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		replaceContents([alice, bob])
		select(bob)

		channel.addMember(makeMember(named: "aaron"))

		#expect(rowDescriptions == ["aaron", "alice", "bob"])
		#expect(selectedNicknames == ["bob"])
	}

	@Test("A part keeps the order and the person who was selected")
	func partKeepsOrderAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")
		let carol = makeMember(named: "carol")

		replaceContents([alice, bob, carol])
		select(carol)

		channel.removeMember(withNickname: "alice")

		#expect(rowDescriptions == ["bob", "carol"])
		#expect(selectedNicknames == ["carol"])
	}

	@Test("A part takes the selection with it when the person selected left")
	func partClearsSelectionOfDepartedMember() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		replaceContents([alice, bob])
		select(alice)

		channel.removeMember(withNickname: "alice")

		#expect(rowDescriptions == ["bob"])
		#expect(selectedNicknames.isEmpty)
	}

	@Test("A rename keeps the row and the selection, because the person is the same")
	func renameKeepsRowAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		replaceContents([alice, bob])
		select(alice)

		session.rename(alice.user, to: "alicia")

		#expect(rowDescriptions == ["alicia", "bob"])
		#expect(selectedNicknames == ["alicia"])
	}

	@Test("A mode change moves the member into its new section and the selection follows")
	func modeChangeMovesMemberAndKeepsSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		replaceContents([alice, bob])
		select(bob)

		/* An op promotion resorts the member list, which reaches the table as one
		 new ordering. */
		channel.changeMember("bob", mode: ChannelModeSymbol(Character("o")), value: true)

		#expect(rowDescriptions == ["[Operators]", "bob", "[Members]", "alice"])
		#expect(selectedNicknames == ["bob"])
	}

	@Test("An edit in place redraws the row without moving it")
	func inPlaceEditKeepsTheRow() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		replaceContents([alice, bob])
		select(bob)

		let revision = memberList.presentationRevision
		session.modify(alice.user) { $0.isAway = true }

		#expect(rowDescriptions == ["alice", "bob"])
		#expect(selectedNicknames == ["bob"])
		#expect(memberList.groups.first?.members.first?.user.isAway == true)
		#expect(memberList.presentationRevision == revision + 1)
	}

	private var rowDescriptions: [String] {
		memberList.groups.flatMap { group in
			let header = memberList.groups.count > 1 ? ["[\(group.section.title)]"] : []
			return header + group.members.map(\.user.nickname)
		}
	}

	@Test("A large protocol unit publishes once while directory lookups stay immediate")
	func bulkPresentationPreservesImmediateState() throws {
		let revision = memberList.presentationRevision
		channel.withMemberPresentationUpdates {
			for index in 0 ..< 2048 {
				channel.addMember(makeMember(named: "member\(index)"))
			}
			#expect(channel.numberOfMembers == 2048)
			#expect(channel.findMember("member2047") != nil)
			#expect(memberList.presentationRevision == revision)
		}
		#expect(memberList.presentationRevision == revision + 1)
		#expect(memberList.groups.flatMap(\.members).count == 2048)

		let member = try #require(channel.findMember("member2047"))
		select(member)
		session.rename(member.user, to: "renamed")
		#expect(selectedNicknames == ["renamed"])
		#expect(memberList.presentationRevision == revision + 2)
		channel.changeMember("renamed", mode: ChannelModeSymbol(Character("o")), value: true)
		#expect(memberList.presentationRevision == revision + 3)

		channel.withMemberPresentationUpdates {
			channel.removeMember(withNickname: "renamed")
			#expect(channel.findMember("renamed") == nil)
			#expect(memberList.selectedMembers.isEmpty)
			channel.withMemberPresentationUpdates {
				channel.addMember(makeMember(named: "next"))
			}
			#expect(memberList.presentationRevision == revision + 3)
		}
		#expect(memberList.presentationRevision == revision + 4)
		#expect(memberList.selectedMemberIDs.isEmpty)
		#expect(channel.findMember("next") != nil)
		channel.withMemberPresentationUpdates {
			channel.recordConversation(with: "next", direction: .mention)
			channel.decayMemberConversations()
		}
		#expect(memberList.presentationRevision == revision + 4)
	}

	@Test("Render snapshots ignore weights and details but refresh names, marks and list identity")
	func renderSnapshotRevisions() throws {
		channel.addMember(makeMember(named: "alice"))
		let cache = TranscriptMemberDirectoryCache()
		let original = cache.members(in: channel)
		#expect(original == [RenderedMember(nickname: "alice")])
		let revision = memberList.presentationRevision
		channel.recordConversation(with: "alice", direction: .incoming)
		channel.decayMemberConversations()
		#expect(cache.members(in: channel) == original)
		#expect(cache.rebuildCount == 1)
		#expect(memberList.presentationRevision == revision)

		let alice = try #require(channel.findMember("alice"))
		select(alice)
		session.modify(alice.user) {
			$0.isAway = true
			$0.account = "account"
			$0.username = "username"
		}
		#expect(memberList.presentationRevision == revision + 1)
		#expect(cache.members(in: channel) == original)
		#expect(cache.rebuildCount == 1)
		let displayed = try #require(memberList.groups.first?.members.first)
		let details = MemberListUserInfoContent(member: displayed, privileges: "")
		#expect(details.awayStatus == MemberListUserInfoContent.awayStatus(isAway: true))
		#expect(details.account == "account")
		#expect(details.username == "username")

		channel.changeMember("alice", mode: ChannelModeSymbol(Character("o")), value: true)
		#expect(cache.members(in: channel) == [RenderedMember(nickname: "alice", mark: "@")])
		#expect(cache.rebuildCount == 2)
		session.renameUser(withNickname: "alice", to: "zoe")
		#expect(cache.members(in: channel) == [RenderedMember(nickname: "zoe", mark: "@")])
		#expect(selectedNicknames == ["zoe"])
		#expect(cache.rebuildCount == 3)

		channel.activate()
		memberList.assign(to: channel)
		channel.addMember(makeMember(named: "bob"))
		#expect(cache.members(in: channel) == [RenderedMember(nickname: "bob")])
		#expect(cache.rebuildCount == 4)
		channel.clearMembers()
		#expect(cache.members(in: channel).isEmpty)
		#expect(cache.members(in: nil).isEmpty)
	}

	@Test("An unchanged or weight-only replacement does not publish or lose its identity index")
	func sameIdentityReplacement() throws {
		channel.addMember(makeMember(named: "alice"))
		channel.addMember(makeMember(named: "bob"))
		let revision = memberList.presentationRevision
		let member = try #require(channel.findMember("bob"))
		var weighted = member
		weighted.incomingConversation()
		channel.memberInfo?.replaceMember(member, with: weighted)
		channel.memberInfo?.replaceMember(weighted, with: weighted, resort: false, replaceInAllChannels: false)
		#expect(memberList.presentationRevision == revision)
		#expect(channel.findMember("bob")?.totalWeight == 100)
		channel.removeMember(withNickname: "alice")
		channel.recordConversation(with: "bob", direction: .outgoing)
		#expect(channel.findMember("bob")?.totalWeight == 120)
		#expect(memberList.presentationRevision == revision + 1)
	}

	/** The presentation hears about a list that has gone away as an empty
	 ordering, which is the same thing it hears when a channel has no members:
	 there is nothing left to draw either way, and a separate "it ended" call
	 only gave the two answers different names. */
	@Test("Detaching from a channel empties the rows and the selection")
	func detachingEmptiesTheList() throws {
		channel.addMember(makeMember(named: "alice"))
		try select(#require(channel.findMember("alice")))

		memberList.assign(to: nil)

		#expect(memberList.groups.isEmpty)
		#expect(memberList.selectedMemberIDs.isEmpty)
		#expect(memberList.selectedMembers.isEmpty)
		#expect(memberList.primaryInteractedMember == nil)
	}

	private func makeMember(named nickname: String, modes: ChannelModeSymbolSet = "") -> Member {
		let user = session.findUserOrCreate(nickname)
		var member = Member(user: user, prefixes: session.currentUserPrefixes)
		member.modes = modes

		return member
	}

	private func replaceContents(_ members: [Member]) {
		channel.withMemberPresentationUpdates {
			channel.clearMembers()
			for member in members {
				channel.addMember(member)
			}
		}
	}

	private var selectedNicknames: [String] {
		memberList.selectedMembers.map(\.user.nickname)
	}

	private func select(_ member: Member) {
		memberList.selectedMemberIDs = [member.id]
	}
}
