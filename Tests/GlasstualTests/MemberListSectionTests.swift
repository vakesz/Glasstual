/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Member list sections")
struct MemberListSectionTests {
	private let client: GLTTestClient
	private let memberList: MemberList
	private let channel: IRCChannel

	init() {
		let client = GLTTestClient()
		let memberList = MemberList()

		let channel = IRCChannel(config: ChannelConfig(channelName: "#members"))
		channel.associatedClient = client
		channel.activate()
		memberList.assign(to: channel)

		self.client = client
		self.memberList = memberList
		self.channel = channel
	}

	@Test("Members of a single rank are shown as a flat list")
	func singleRankIsAFlatList() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)

		#expect(memberList.groups.count == 1)
		#expect(memberList.groups.first?.members.count == 2)
		#expect(rowDescriptions == ["alice", "bob"])
	}

	@Test("A second rank gives every section a header row")
	func secondRankAddsHeadersForEverySection() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice", "bob"])
		#expect(memberList.groups.map(\.section.rank) == [.normalOperator, .none])
	}

	@Test("Removing the last member of a section drops its header")
	func removingLastMemberOfASectionDropsItsHeader() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)
		insert(makeMember(named: "dave", modes: "v"), at: 1)

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
		insert(makeMember(named: "alice"), at: 0)

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
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

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

		client.rename(alice.user, to: "alicia")

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
		client.modify(alice.user) { $0.isAway = true }

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
		client.rename(member.user, to: "renamed")
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
		let cache = MemberListRenderCache()
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
		client.modify(alice.user) {
			$0.isAway = true
			$0.account = "account"
			$0.username = "username"
		}
		#expect(memberList.presentationRevision == revision + 1)
		#expect(cache.members(in: channel) == original)
		#expect(cache.rebuildCount == 1)
		let displayed = try #require(memberList.groups.first?.members.first)
		let details = MemberListUserInfoContent(member: displayed, privileges: "")
		#expect(details.awayStatus == MemberListStrings.userIsAway)
		#expect(details.account == "account")
		#expect(details.username == "username")

		channel.changeMember("alice", mode: ChannelModeSymbol(Character("o")), value: true)
		#expect(cache.members(in: channel) == [RenderedMember(nickname: "alice", mark: "@")])
		#expect(cache.rebuildCount == 2)
		client.renameUser(withNickname: "alice", to: "zoe")
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
		channel.memberInfo?.replaceMember(weighted, with: weighted, resort: false)
		#expect(memberList.presentationRevision == revision)
		#expect(channel.findMember("bob")?.totalWeight == 100)
		channel.removeMember(withNickname: "alice")
		channel.recordConversation(with: "bob", direction: .outgoing)
		#expect(channel.findMember("bob")?.totalWeight == 120)
		#expect(memberList.presentationRevision == revision + 1)
	}

	private func makeMember(named nickname: String, modes: ChannelModeSymbolSet = "") -> ChannelUser {
		let user = client.findUserOrCreate(nickname)
		var member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)
		member.modes = modes

		return member
	}

	private func insert(_ member: ChannelUser, at _: Int) {
		channel.addMember(member)
	}

	private func replaceContents(_ members: [ChannelUser]) {
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

	private func select(_ member: ChannelUser) {
		memberList.selectedMemberIDs = [member.id]
	}
}
