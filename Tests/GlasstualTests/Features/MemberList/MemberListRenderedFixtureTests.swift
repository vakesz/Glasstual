// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

@MainActor
@Suite("Rendered native member fixtures", .serialized)
struct MemberListRenderedFixtureTests {
	@Test("Large member lists render with long German and Hungarian names", arguments: ["de", "hu"], [false, true])
	func renderLargeMemberList(language: String, dark: Bool) throws {
		let members = members(language: language)
		let model = MemberList()
		model.membersDidChange(members)
		model.selectedMemberIDs = [members[1].id]
		let root = MemberListView(model: model, redirectTyping: { _ in })
			.environment(\.locale, Locale(identifier: language))
			.background(Color(nsColor: .windowBackgroundColor))
			.frame(width: 240, height: 640)
		let host = NSHostingView(rootView: root)
		let window = NSWindow(
			contentRect: NSRect(x: 0, y: 0, width: 240, height: 640),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		defer { window.close() }
		window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
		window.contentView = host
		// Realize native row layers without covering the user's windows. A hidden
		// outer hosting view can snapshot table children before their first layout.
		window.setFrameOrigin(NSPoint(x: -4000, y: -4000))
		window.order(.below, relativeTo: 0)
		host.layoutSubtreeIfNeeded()
		let table = try #require(descendantTable(in: host))
		_ = table.rowView(atRow: 1, makeIfNecessary: true)
		table.layoutSubtreeIfNeeded()
		window.displayIfNeeded()
		let cell = try #require(table.view(atColumn: 0, row: 1, makeIfNecessary: false) as? MemberListTableCell)
		let content = try #require(cell.subviews.first)
		#expect(content.frame.width == cell.bounds.width - 12)
		#expect(content.frame.height == cell.bounds.height)
		#expect(cell.bounds.contains(content.frame))
		#expect(table.numberOfRows >= 1367)
		#expect(table.frame.width <= host.frame.width)
		#expect(table.frame.height > host.frame.height)
		#expect(model.memberShowingProfile == nil)
		let bitmap = try #require(host.bitmapImageRepForCachingDisplay(in: host.bounds))
		host.cacheDisplay(in: host.bounds, to: bitmap)
		let png = try #require(bitmap.representation(using: .png, properties: [:]))
		#expect(png.count > 1000)
		// The hosted test is sandboxed. The review runner can copy these artifacts
		// from its disposable application-support directory into build/review-fixtures.
		let support = try #require(ApplicationPaths.applicationSupportURL)
		let directory = support.appendingPathComponent("review-fixtures", isDirectory: true)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let appearance = dark ? "dark" : "light"
		try png.write(to: directory.appendingPathComponent("members-1367-\(language)-\(appearance).png"), options: .atomic)
	}

	private func descendantTable(in view: NSView) -> MemberListNativeTable? {
		if let table = view as? MemberListNativeTable {
			return table
		}
		for child in view.subviews {
			if let table = descendantTable(in: child) {
				return table
			}
		}
		return nil
	}

	private func members(language: String) -> [Member] {
		let names = language == "de"
			? ["Donaudampfschifffahrtsgesellschaft", "Überraschungsbesucher", "Nachrichtenübertragung", "ÄußerstLangerMitgliedsname"]
			: ["ÁrvíztűrőTükörfúrógép", "Megszentségteleníthetetlenségeskedés", "BeszélgetésRésztvevője", "KülönlegesBecenév"]
		return (0 ..< 1367).map { index in
			var user = User(nickname: "\(names[index % names.count])-\(index)")
			user.isAway = index % 4 == 2
			user.isBot = index % 7 == 3
			var member = Member(user: user)
			if index < 3 {
				member.modes = "o"
			} else if index < 7 {
				member.modes = "v"
			}
			return member
		}
	}
}
