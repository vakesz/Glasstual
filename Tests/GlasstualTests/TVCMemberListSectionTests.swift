/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import XCTest

@MainActor
final class TVCMemberListSectionTests: XCTestCase {
	private var client: GLTTestClient!
	private var memberList: MemberList!
	private var controller: IRCChannelMemberListController!

	override func setUp() async throws {
		try await super.setUp()

		client = GLTTestClient()
		memberList = MemberList(frame: NSRect(x: 0, y: 0, width: 150, height: 400))
		memberList.addTableColumn(NSTableColumn(identifier: NSUserInterfaceItemIdentifier("member")))
		memberList.awakeFromNib()

		controller = IRCChannelMemberListController()
		controller.setValue(memberList, forKey: "tableView")
		memberList.setValue(controller, forKey: "contentController")
		controller.replaceContents([])
	}

	override func tearDown() async throws {
		controller = nil
		memberList = nil
		client = nil

		try await super.tearDown()
	}

	func testSingleRankIsAFlatList() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)

		XCTAssertEqual(memberList.numberOfRows, 2)
		XCTAssertFalse(memberList.isGroupRow(0))
		XCTAssertEqual(rowDescriptions, ["alice", "bob"])
	}

	func testObjectiveCRuntimeContractIsPreserved() {
		XCTAssertEqual(NSStringFromClass(type(of: memberList)), "TVCMemberList")
		XCTAssertEqual(NSStringFromClass(MemberListSection.self), "TVCMemberListSection")
		XCTAssertEqual(NSStringFromClass(MemberListCell.self), "TVCMemberListCell")
		XCTAssertEqual(NSStringFromClass(MemberListHeaderCell.self), "TVCMemberListHeaderCell")
		XCTAssertEqual(NSStringFromClass(MemberListRowCell.self), "TVCMemberListRowCell")
		XCTAssertEqual(NSStringFromClass(MemberListUserInfoPopover.self), "TVCMemberListUserInfoPopover")

		let selectors = [
			"assignToChannel:",
			"contentController",
			"isGroupRow:",
			"itemAtRow:",
			"memberInsertedAtIndex:",
			"memberListUserInfoPopover",
			"memberRemovedAtIndex:",
			"membersReplaced",
			"refreshAllDrawings",
			"refreshDrawingForChangesToPreference:",
			"refreshDrawingForMember:",
			"refreshDrawingForRow:",
			"rowForItem:",
			"rowForMemberAtIndex:",
		]

		for selectorName in selectors {
			XCTAssertTrue(
				memberList.responds(to: NSSelectorFromString(selectorName)),
				"Missing Objective-C selector \(selectorName)"
			)
		}
	}

	func testSecondRankAddsHeadersForEverySection() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "bob"), at: 1)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

		XCTAssertEqual(rowDescriptions, ["[Operators]", "carol", "[Members]", "alice", "bob"])
		XCTAssertTrue(memberList.isGroupRow(0))
		XCTAssertTrue(memberList.isGroupRow(2))
		XCTAssertEqual(memberList.rowForMember(at: 0), 1)
		XCTAssertEqual(memberList.rowForMember(at: 1), 3)
		XCTAssertEqual(memberList.rowForMember(at: 2), 4)
		XCTAssertNil(memberList.item(atRow: 2))
	}

	func testRowForItemMatchesItemAtRow() {
		let alice = makeMember(named: "alice")
		let carol = makeMember(named: "carol", modes: "o")
		let dave = makeMember(named: "dave", modes: "v")

		insert(alice, at: 0)
		insert(carol, at: 0)
		insert(dave, at: 1)

		for member in [alice, carol, dave] {
			let row = memberList.row(forItem: member)
			let item = memberList.item(atRow: row) as? ChannelUser

			XCTAssertTrue(item === member)
		}
	}

	func testRemovingLastMemberOfASectionDropsItsHeader() {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)
		insert(makeMember(named: "dave", modes: "v"), at: 1)

		XCTAssertEqual(rowDescriptions, [
			"[Operators]", "carol", "[Voiced]", "dave", "[Members]", "alice",
		])

		controller.remove(atArrangedObjectIndex: 1)

		XCTAssertEqual(rowDescriptions, ["[Operators]", "carol", "[Members]", "alice"])

		controller.remove(atArrangedObjectIndex: 0)

		XCTAssertEqual(rowDescriptions, ["alice"])
		XCTAssertEqual(memberList.numberOfRows, 1)
	}

	func testRemovingOnlyMemberLeavesAnEmptyFlatList() {
		insert(makeMember(named: "alice"), at: 0)

		controller.remove(atArrangedObjectIndex: 0)

		XCTAssertEqual(memberList.numberOfRows, 0)
		XCTAssertEqual(rowDescriptions, [])
	}

	func testReplacingContentsRebuildsSections() {
		controller.replaceContents([
			makeMember(named: "carol", modes: "o"),
			makeMember(named: "alice"),
			makeMember(named: "bob"),
		])

		XCTAssertEqual(rowDescriptions, ["[Operators]", "carol", "[Members]", "alice", "bob"])

		controller.replaceContents([])

		XCTAssertEqual(memberList.numberOfRows, 0)
	}

	func testHeaderRowsAreNeitherSelectableNorTypeSelectable() throws {
		insert(makeMember(named: "alice"), at: 0)
		insert(makeMember(named: "carol", modes: "o"), at: 0)

		let delegate = try XCTUnwrap(memberList.delegate)

		XCTAssertFalse(delegate.tableView?(memberList, shouldSelectRow: 0) ?? true)
		XCTAssertTrue(delegate.tableView?(memberList, shouldSelectRow: 1) ?? false)
		XCTAssertNil(delegate.tableView?(memberList, typeSelectStringFor: nil, row: 0))
		XCTAssertEqual(delegate.tableView?(memberList, typeSelectStringFor: nil, row: 1), "carol")
	}

	func testMemberCellUsesSingleLineTailTruncation() {
		let cell = MemberListCell(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
		let nicknameField = NSTextField(labelWithString: "")
		cell.setValue(nicknameField, forKey: "cellTextField")
		cell.awakeFromNib()

		XCTAssertTrue(nicknameField.usesSingleLineMode)
		XCTAssertEqual(nicknameField.maximumNumberOfLines, 1)
		XCTAssertEqual(nicknameField.lineBreakMode, .byTruncatingTail)
	}

	func testMemberCellCollapsesUnusedStatusImage() {
		let cell = MemberListCell(frame: NSRect(x: 0, y: 0, width: 150, height: 28))
		let statusImageView = NSImageView()
		let statusWidthConstraint = statusImageView.widthAnchor.constraint(equalToConstant: 16)
		cell.setValue(statusImageView, forKey: "statusImageView")
		cell.setValue(statusWidthConstraint, forKey: "statusImageWidthConstraint")

		cell.setValue(false, forKey: "statusImageVisible")

		XCTAssertTrue(statusImageView.isHidden)
		XCTAssertEqual(statusWidthConstraint.constant, 0)

		cell.setValue(true, forKey: "statusImageVisible")

		XCTAssertFalse(statusImageView.isHidden)
		XCTAssertEqual(statusWidthConstraint.constant, 16)
	}

	private var rowDescriptions: [String] {
		(0 ..< memberList.numberOfRows).compactMap { row in
			if memberList.isGroupRow(row) {
				let section = memberList.dataSource?.tableView?(
					memberList,
					objectValueFor: nil,
					row: row
				) as? MemberListSection

				return section.map { "[\($0.title)]" }
			}

			return (memberList.item(atRow: row) as? ChannelUser)?.user.nickname
		}
	}

	private func makeMember(named nickname: String, modes: ChannelModeSymbolSet = "") -> ChannelUser {
		let user = User(nickname: nickname, on: client)
		let member = ChannelUserMutable(user: user)
		member.modes = modes

		guard let copiedMember = member.copy() as? ChannelUser else {
			preconditionFailure("Channel member copies must preserve their model type")
		}

		return copiedMember
	}

	private func insert(_ member: ChannelUser, at index: Int) {
		controller.insert(member, atArrangedObjectIndex: index)
	}
}
