// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Native member list", .serialized)
struct MemberListTableTests {
	@Test("Selection is native, supports multiple members, and never opens a profile")
	func selectionDoesNotPresentProfile() {
		let fixture = Fixture(count: 4)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		table.selectRowIndexes(IndexSet([1, 2]), byExtendingSelection: false)
		#expect(fixture.model.selectedMemberIDs == Set(fixture.members.prefix(2).map(\.id)))
		#expect(fixture.model.memberShowingProfile == nil)
		#expect(fixture.controller.tableView(table, shouldSelectRow: 0) == false)
		#expect(fixture.model.selectedProfileMember == nil)
	}

	@Test("An open profile follows the member under the pointer without moving selection")
	func scrollingRetargetsOnlyAnOpenProfile() {
		let fixture = Fixture(count: 4)
		defer { fixture.window.close() }
		let first = fixture.members[0]
		let second = fixture.members[1]
		fixture.model.selectedMemberIDs = [first.id]
		let point = fixture.point(on: 2)

		fixture.controller.followProfile(at: point)
		#expect(fixture.model.memberShowingProfile == nil)
		fixture.model.showProfile(for: first.id)
		fixture.controller.followProfile(at: point)
		#expect(fixture.model.memberShowingProfile == second.id)
		#expect(fixture.model.selectedMemberIDs == [first.id])

		fixture.controller.followProfile(at: fixture.point(on: 0))
		#expect(fixture.model.memberShowingProfile == second.id)
		fixture.controller.followProfile(at: NSPoint(x: -10, y: 40))
		#expect(fixture.model.memberShowingProfile == second.id)

		fixture.controller.followsProfileOnScroll = false
		fixture.controller.followProfile(at: fixture.point(on: 3))
		#expect(fixture.model.memberShowingProfile == second.id)
	}

	@Test("Changing selection dismisses an explicitly opened profile")
	func changingSelectionDismissesProfile() {
		let fixture = Fixture(count: 3)
		defer { fixture.window.close() }
		fixture.model.selectedMemberIDs = [fixture.members[0].id]
		fixture.model.showProfile(for: fixture.members[0].id)
		fixture.model.selectedMemberIDs = [fixture.members[1].id]
		#expect(fixture.model.memberShowingProfile == nil)
	}

	@Test("A rename keeps identity, selection and profile content current")
	func rowUpdatesPreserveIdentity() throws {
		let fixture = Fixture(count: 3)
		defer { fixture.window.close() }
		let identifier = fixture.members[1].id
		fixture.model.selectedMemberIDs = [identifier]
		fixture.model.showProfile(for: identifier)
		var members = fixture.members
		members[1].user.nickname = "renamed"
		fixture.model.membersDidChange(members)
		fixture.controller.update(revision: fixture.model.presentationRevision, selection: [identifier])
		#expect(fixture.model.profileMember?.user.nickname == "renamed")
		#expect(fixture.controller.row(for: identifier) == 2)
		#expect(fixture.controller.tableView.selectedRowIndexes == IndexSet(integer: 2))
		let view = try #require(fixture.controller.tableView.rowView(atRow: 2, makeIfNecessary: true))
		#expect(view.accessibilityLabel()?.contains("renamed") == true)
		#expect(view.accessibilityCustomActions()?.first?.name == String(localized: .MemberList.showProfileAction))
	}

	@Test("Double click dispatches the configured action for the actual member")
	func doubleClickDispatchesMember() {
		let fixture = Fixture(count: 3)
		defer { fixture.window.close() }
		var actedOn: User.ID?
		fixture.controller.performDoubleClick = { actedOn = fixture.model.primaryInteractedMember?.id }
		fixture.model.showProfile(for: fixture.members[0].id)
		fixture.controller.activateMember(at: 2)
		#expect(actedOn == fixture.members[1].id)
		#expect(fixture.model.memberShowingProfile == nil)
		actedOn = nil
		fixture.controller.activateMember(at: 0)
		#expect(actedOn == nil)
	}

	@Test("File drops and context menus use the clicked member without selecting them")
	func clickedTargetsStaySeparateFromSelection() throws {
		let fixture = Fixture(count: 3)
		defer { fixture.window.close() }
		fixture.model.selectedMemberIDs = [fixture.members[0].id]
		let menu = try #require(fixture.controller.contextMenu(at: 2))
		#expect(menu.items.first?.representedObject as? User.ID == fixture.members[1].id)
		#expect(fixture.model.selectedMemberIDs == [fixture.members[0].id])
		var droppedOn: String?
		fixture.controller.sendFiles = { _, nickname in droppedOn = nickname }
		#expect(fixture.controller.acceptFiles(["/tmp/offered.txt"], at: 2))
		#expect(droppedOn == fixture.members[1].user.nickname)
		#expect(fixture.controller.acceptFiles(["/tmp/offered.txt"], at: 0) == false)
		#expect(fixture.model.selectedMemberIDs == [fixture.members[0].id])
	}

	@Test("A large list creates visible cells and scrolling never rebuilds its rows")
	func largeListKeepsScrollingBounded() {
		let fixture = Fixture(count: 1367)
		defer { fixture.window.close() }
		#expect(fixture.controller.tableView.numberOfRows == 1368)
		_ = fixture.controller.tableView.rowView(atRow: 1, makeIfNecessary: true)
		var availableRows = 0
		fixture.controller.tableView.enumerateAvailableRowViews { _, _ in availableRows += 1 }
		#expect(availableRows > 0)
		#expect(availableRows < 100)
		fixture.model.showProfile(for: fixture.members[0].id)
		let revision = fixture.model.presentationRevision
		let updates = fixture.controller.updateCount
		for _ in 0 ..< 100 {
			fixture.controller.followProfile(at: fixture.point(on: 3))
		}
		#expect(fixture.controller.updateCount == updates)
		#expect(fixture.model.presentationRevision == revision)
		#expect(fixture.model.memberShowingProfile == fixture.members[2].id)
	}

	@Test("Keyboard and accessibility menus target the selected row")
	func selectionContextMenuUsesSelectedMember() throws {
		let fixture = Fixture(count: 3)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		#expect(table.selectionContextMenu() == nil)
		table.selectRowIndexes(IndexSet(integer: 3), byExtendingSelection: false)
		let menu = try #require(table.selectionContextMenu())
		#expect(menu.items.first?.representedObject as? User.ID == fixture.members[2].id)
		#expect(fixture.model.selectedMemberIDs == [fixture.members[2].id])
		#expect(fixture.model.memberShowingProfile == nil)
	}

	private struct Fixture {
		let model: MemberList
		let controller: MemberListTableController
		let window: NSWindow
		let members: [Member]

		init(count: Int) {
			members = (0 ..< count).map { Member(user: User(nickname: "member\($0)")) }
			model = MemberList()
			model.membersDidChange(members)
			controller = MemberListTableController(model: model)
			window = NSWindow(
				contentRect: NSRect(x: 0, y: 0, width: 240, height: 320),
				styleMask: .borderless, backing: .buffered, defer: false
			)
			window.isReleasedWhenClosed = false
			window.contentView = controller.scrollView
			controller.update(revision: model.presentationRevision, selection: [])
			window.contentView?.layoutSubtreeIfNeeded()
		}

		func point(on row: Int) -> NSPoint {
			let rect = controller.tableView.rect(ofRow: row)
			return NSPoint(x: rect.midX, y: rect.midY)
		}
	}
}
