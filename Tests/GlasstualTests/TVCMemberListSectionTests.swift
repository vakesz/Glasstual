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
import Testing

@MainActor
@Suite("Member list sections")
struct TVCMemberListSectionTests {
	private let client: GLTTestClient
	private let memberList: MemberList
	private let controller: IRCChannelMemberListController

	init() {
		let client = GLTTestClient()
		let memberList = MemberList(frame: NSRect(x: 0, y: 0, width: 150, height: 400))
		memberList.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member")))
		memberList.configure()

		let controller = memberList.contentController!
		controller.replaceContents([])

		self.client = client
		self.memberList = memberList
		self.controller = controller
	}

	@Test("Members of a single rank are shown as a flat list")
	func singleRankIsAFlatList() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)

		#expect(memberList.numberOfRows == 2)
		#expect(memberList.isGroupRow(0) == false)
		#expect(rowDescriptions == ["alice", "bob"])
	}

	@Test("A second rank gives every section a header row")
	func secondRankAddsHeadersForEverySection() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice", "bob"])
		#expect(memberList.isGroupRow(0))
		#expect(memberList.isGroupRow(2))
		#expect(memberList.rowForMember(at: 0) == 1)
		#expect(memberList.rowForMember(at: 1) == 3)
		#expect(memberList.rowForMember(at: 2) == 4)
		#expect(memberList.item(atRow: 2) == nil)
	}

	@Test("A member's row round trips back to the member")
	func rowForItemMatchesItemAtRow() {
		let alice = makeMember(named: "alice")
		let carol = makeMember(named: "carol", modes: "o")
		let dave = makeMember(named: "dave", modes: "v")

		insert(alice, at: 0)
		insert(carol, at: 0)
		insert(dave, at: 1)

		for member in [alice, carol, dave] {
			let row = memberList.row(forItem: member)
			let item = memberList.item(atRow: row) as? ChannelUser

			#expect(item == member)
		}
	}

	@Test("Removing the last member of a section drops its header")
	func removingLastMemberOfASectionDropsItsHeader() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)
		insert(makeMember(named: "dave", modes: "v"), at: 1)

		#expect(rowDescriptions == [
			"[Operators]", "carol", "[Voiced]", "dave", "[Members]", "alice",
		])

		controller.remove(atArrangedObjectIndex: 1)

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice"])

		controller.remove(atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["alice"])
		#expect(memberList.numberOfRows == 1)
	}

	@Test("Removing the only member leaves an empty flat list")
	func removingOnlyMemberLeavesAnEmptyFlatList() {
		insert(makeMember(named: "alice"), at: 0)

		controller.remove(atArrangedObjectIndex: 0)

		#expect(memberList.numberOfRows == 0)
		#expect(rowDescriptions.isEmpty)
	}

	@Test("Replacing the contents rebuilds every section")
	func replacingContentsRebuildsSections() {
		controller.replaceContents([
			makeMember(named: "carol", modes: "o"),
			makeMember(named: "alice"),
			makeMember(named: "bob"),
		])

		#expect(rowDescriptions == ["[Operators]", "carol", "[Members]", "alice", "bob"])

		controller.replaceContents([])

		#expect(memberList.numberOfRows == 0)
	}

	@Test("A header row can be neither selected nor typed to")
	func headerRowsAreNeitherSelectableNorTypeSelectable() throws {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

		let delegate = try #require(memberList.delegate)

		#expect((delegate.tableView?(memberList, shouldSelectRow: 0) ?? true) == false)
		#expect(delegate.tableView?(memberList, shouldSelectRow: 1) ?? false)
		#expect(delegate.tableView?(memberList, typeSelectStringFor: nil, row: 0) == nil)
		#expect(delegate.tableView?(memberList, typeSelectStringFor: nil, row: 1) == "carol")
	}

	// MARK: - Snapshot diffs

	@Test("A join keeps the order and the person who was selected")
	func joinKeepsOrderAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		controller.replaceContents([alice, bob])
		select(bob)

		controller.insert(makeMember(named: "aaron"), atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["aaron", "alice", "bob"])
		#expect(selectedNicknames == ["bob"])
	}

	@Test("A part keeps the order and the person who was selected")
	func partKeepsOrderAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")
		let carol = makeMember(named: "carol")

		controller.replaceContents([alice, bob, carol])
		select(carol)

		controller.remove(atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["bob", "carol"])
		#expect(selectedNicknames == ["carol"])
	}

	@Test("A part takes the selection with it when the person selected left")
	func partClearsSelectionOfDepartedMember() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		controller.replaceContents([alice, bob])
		select(alice)

		controller.remove(atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["bob"])
		#expect(selectedNicknames.isEmpty)
	}

	@Test("A rename keeps the row and the selection, because the person is the same")
	func renameKeepsRowAndSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		controller.replaceContents([alice, bob])
		select(alice)

		var renamed = alice
		renamed.user.nickname = "alicia"
		controller.replace(renamed, atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["alicia", "bob"])
		#expect(selectedNicknames == ["alicia"])
	}

	@Test("A mode change moves the member into its new section and the selection follows")
	func modeChangeMovesMemberAndKeepsSelection() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		controller.replaceContents([alice, bob])
		select(bob)

		/* An op promotion resorts the member list, which reaches the table as one
		 new ordering. */
		var promoted = bob
		promoted.modes = "o"
		controller.replaceContents([promoted, alice])

		#expect(rowDescriptions == ["[Operators]", "bob", "[Members]", "alice"])
		#expect(selectedNicknames == ["bob"])
	}

	@Test("An edit in place redraws the row without moving it")
	func inPlaceEditKeepsTheRow() {
		let alice = makeMember(named: "alice")
		let bob = makeMember(named: "bob")

		controller.replaceContents([alice, bob])
		select(bob)

		var away = alice
		away.user.isAway = true
		controller.replace(away, atArrangedObjectIndex: 0)

		#expect(rowDescriptions == ["alice", "bob"])
		#expect(selectedNicknames == ["bob"])
		#expect((memberList.item(atRow: 0) as? ChannelUser)?.user.isAway == true)
	}

	@Test("A nickname is drawn on one line and truncated at the tail")
	func memberCellUsesSingleLineTailTruncation() throws {
		let cell = MemberListCell(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
		let nicknameField = try #require(cell.textField)
		cell.configure()

		#expect(nicknameField.usesSingleLineMode)
		#expect(nicknameField.maximumNumberOfLines == 1)
		#expect(nicknameField.lineBreakMode == .byTruncatingTail)
	}

	@Test("An unused status image collapses to no width at all")
	func memberCellCollapsesUnusedStatusImage() throws {
		let cell = MemberListCell(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
		let statusImageView = try #require(cell.subviews.compactMap { $0 as? NSImageView }.last)
		let statusWidthConstraint = try #require(
			statusImageView.constraints.first { $0.firstAttribute == .width }
		)

		cell.setStatusImageVisible(false)

		#expect(statusImageView.isHidden)
		#expect(statusWidthConstraint.constant == 0)

		cell.setStatusImageVisible(true)

		#expect(statusImageView.isHidden == false)
		#expect(statusWidthConstraint.constant == 16)
	}

	private var rowDescriptions: [String] {
		(0 ..< memberList.numberOfRows).compactMap { row in
			if let section = memberList.section(atRow: row) {
				return "[\(section.title)]"
			}

			return (memberList.item(atRow: row) as? ChannelUser)?.user.nickname
		}
	}

	private func makeMember(named nickname: String, modes: ChannelModeSymbolSet = "") -> ChannelUser {
		let user = User(nickname: nickname)
		var member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)
		member.modes = modes

		return member
	}

	private func insert(_ member: ChannelUser, at index: Int) {
		controller.insert(member, atArrangedObjectIndex: index)
	}

	private var selectedNicknames: [String] {
		memberList.selectedRowIndexes.compactMap {
			(memberList.item(atRow: $0) as? ChannelUser)?.user.nickname
		}
	}

	private func select(_ member: ChannelUser) {
		let row = memberList.row(forItem: member)
		memberList.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
	}
}
