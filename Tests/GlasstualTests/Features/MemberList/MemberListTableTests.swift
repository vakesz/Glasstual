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
		fixture.presentOffscreen()
		let row = NativeTableAccessibility.rows(in: fixture.controller.tableView)[2]
		let entry = try #require(NativeTableAccessibility.descendants(of: row).first { $0.accessibilityRole() == .staticText })
		#expect(entry.accessibilityLabel()?.contains("renamed") == true)
		#expect(entry.accessibilityCustomActions()?.first?.name == String(localized: .MemberList.showProfileAction))
	}

	@Test("Exported accessibility rows expose one member description and a working profile action")
	func exportedMemberAccessibility() throws {
		var members = (0 ..< 3).map { Member(user: User(nickname: "member\($0)")) }
		members[1].user.isAway = true
		members[1].user.isBot = true
		members[1].user.account = "registered-account"
		let fixture = Fixture(members: members)
		defer { fixture.window.close() }
		fixture.presentOffscreen()
		let table = fixture.controller.tableView
		table.selectRowIndexes(IndexSet(integer: 1), byExtendingSelection: false)
		let rows = NativeTableAccessibility.rows(in: table)
		try #require(rows.count == 4)
		let entries = NativeTableAccessibility.descendants(of: rows[2]).filter { $0.accessibilityRole() == .staticText }
		try #require(entries.count == 1)
		let entry = try #require(entries.first)
		#expect(entry.accessibilityLabel() == MemberListTableRow.member(members[1]).accessibilityDescription(
			style: fixture.model.presentationStyle
		))
		#expect(entry.accessibilityChildren()?.isEmpty != false)
		let action = try #require(entry.accessibilityCustomActions()?.first)
		#expect(action.name == String(localized: .MemberList.showProfileAction))
		#expect(try NSApp.sendAction(#require(action.selector), to: action.target, from: nil))
		#expect(fixture.model.memberShowingProfile == members[1].id)
		#expect(fixture.model.selectedMemberIDs == [members[0].id])
		#expect(NativeTableAccessibility.isSelected(rows[1]))
		#expect(NativeTableAccessibility.isSelected(rows[2]) == false)
		let headings = NativeTableAccessibility.descendants(of: rows[0]).filter { $0.accessibilityRole() == .staticText }
		try #require(headings.count == 1)
		#expect(headings[0].accessibilityLabel()?.isEmpty == false)
		#expect(headings[0].accessibilityCustomActions()?.isEmpty != false)
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

	@Test("Switching large conversations replaces their member lists without computing join and part differences")
	func largeConversationSwitchesReplaceRows() throws {
		let session = TestServerSession()
		let first = makeConversation(named: "#first", count: 1367, session: session)
		let second = makeConversation(named: "#second", count: 1367, session: session)
		let fixture = Fixture(count: 0)
		defer {
			fixture.model.assign(to: nil)
			fixture.window.close()
		}
		fixture.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		fixture.window.order(.below, relativeTo: 0)
		fixture.assign(to: first)
		let firstMember = try #require(fixture.controller.member(at: 1))
		fixture.model.selectedMemberIDs = [firstMember.id]
		fixture.controller.update(revision: fixture.model.presentationRevision, selection: [firstMember.id])
		fixture.model.showProfile(for: firstMember.id)
		fixture.controller.tableView.scrollRowToVisible(900)
		fixture.assign(to: second)
		#expect(fixture.model.sourceIdentifier == second.uniqueIdentifier)
		#expect(fixture.model.selectedMemberIDs.isEmpty)
		#expect(fixture.controller.tableView.selectedRowIndexes.isEmpty)
		#expect(fixture.model.memberShowingProfile == nil)
		#expect(fixture.controller.row(for: firstMember.id) == nil)
		#expect(fixture.controller.scrollView.contentView.bounds.minY == 0)

		let replacements = fixture.controller.replacementCount
		let clock = ContinuousClock()
		var samples: [Double] = []
		for index in 0 ..< 10 {
			let conversation = index.isMultiple(of: 2) ? first : second
			let start = clock.now
			fixture.assign(to: conversation)
			fixture.window.displayIfNeeded()
			let elapsed = start.duration(to: clock.now).components
			samples.append(Double(elapsed.seconds) * 1000 + Double(elapsed.attoseconds) / 1e15)
			#expect(fixture.model.sourceIdentifier == conversation.uniqueIdentifier)
			#expect(fixture.controller.tableView.numberOfRows == 1368)
			#expect(fixture.controller.replacementCount == replacements + index + 1)
		}
		samples.sort()
		let report = "Member table: 1367 disjoint members, 10 warm channel switches including layout and display; "
			+ "median \(samples[5]) ms; min \(samples[0]) ms; max \(samples[9]) ms."
		Attachment.record(report, named: "member-channel-switch-benchmark.txt")
		print(report)
		var availableRows = 0
		fixture.controller.tableView.enumerateAvailableRowViews { _, _ in availableRows += 1 }
		#expect(availableRows > 0 && availableRows < 100)
	}

	@Test("Joins and parts in the same conversation preserve selection, profile and the visible member")
	func membershipChangesKeepTheViewport() throws {
		let fixture = Fixture(count: 80)
		defer { fixture.window.close() }
		let table = fixture.controller.tableView
		let clip = fixture.controller.scrollView.contentView
		let member = fixture.members[19]
		fixture.model.selectedMemberIDs = [member.id]
		fixture.model.showProfile(for: member.id)
		clip.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: 20).minY + 7))
		fixture.controller.scrollView.reflectScrolledClipView(clip)
		let replacements = fixture.controller.replacementCount
		let joined = Member(user: User(nickname: "joined"))

		for members in [[joined] + fixture.members, fixture.members] {
			fixture.model.membersDidChange(members)
			fixture.controller.update(revision: fixture.model.presentationRevision, selection: [member.id])
			let row = try #require(fixture.controller.row(for: member.id))
			#expect(fixture.controller.replacementCount == replacements)
			#expect(table.selectedRowIndexes == IndexSet(integer: row))
			#expect(abs(clip.bounds.minY - table.rect(ofRow: row).minY - 7) < 0.5)
			#expect(fixture.model.memberShowingProfile == member.id)
		}
	}

	@Test("Rank headings scroll with their members instead of gaining a floating background and separator")
	func rankHeadingsDoNotFloat() throws {
		var members = (0 ..< 80).map { Member(user: User(nickname: "member\($0)")) }
		for index in 0 ..< 40 {
			members[index].modes = "o"
		}
		let fixture = Fixture(members: members)
		defer { fixture.window.close() }
		fixture.window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		fixture.window.order(.below, relativeTo: 0)
		let table = fixture.controller.tableView
		#expect(table.floatsGroupRows == false)
		for headingIndex in [0, 41] {
			let heading = try #require(table.rowView(atRow: headingIndex, makeIfNecessary: true))
			#expect(heading.isGroupRowStyle)
			let clip = fixture.controller.scrollView.contentView
			clip.scroll(to: NSPoint(x: 0, y: table.rect(ofRow: headingIndex + 2).minY))
			fixture.controller.scrollView.reflectScrolledClipView(clip)
			table.layoutSubtreeIfNeeded()
			fixture.window.displayIfNeeded()
			#expect(table.rect(ofRow: headingIndex).maxY < table.visibleRect.minY)
			if let displayedHeading = table.rowView(atRow: headingIndex, makeIfNecessary: false) {
				#expect(displayedHeading.isFloating == false)
				#expect(displayedHeading.convert(displayedHeading.bounds, to: table).maxY < table.visibleRect.minY)
			}
		}
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
			self.init(members: (0 ..< count).map { Member(user: User(nickname: "member\($0)")) })
		}

		init(members: [Member]) {
			self.members = members
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

		func assign(to conversation: Conversation) {
			model.assign(to: conversation)
			controller.update(revision: model.presentationRevision, selection: model.selectedMemberIDs)
			window.contentView?.layoutSubtreeIfNeeded()
		}

		func presentOffscreen() {
			window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
			window.order(.below, relativeTo: 0)
			controller.tableView.layoutSubtreeIfNeeded()
			window.displayIfNeeded()
		}

		func point(on row: Int) -> NSPoint {
			let rect = controller.tableView.rect(ofRow: row)
			return NSPoint(x: rect.midX, y: rect.midY)
		}
	}

	private func makeConversation(named name: String, count: Int, session: TestServerSession) -> Conversation {
		let conversation = Conversation(config: ConversationConfig(name: name))
		conversation.associatedSession = session
		conversation.activate()
		conversation.withMemberPresentationUpdates {
			for index in 0 ..< count {
				conversation.addMember(Member(user: User(nickname: "\(name.dropFirst())-\(index)"), prefixes: session.currentUserPrefixes))
			}
		}
		return conversation
	}
}
