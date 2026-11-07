// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Network icons")
struct NetworkIconStoreTests {
	@Test("An address that names a local or private host is never fetched", arguments: [
		"http://127.0.0.1/icon.png",
		"https://localhost/icon.png",
		"https://192.168.1.10/icon.png",
		"https://[::1]/icon.png",
		"https://printer/icon.png",
	])
	func privateHostIsRefused(_ address: String) throws {
		let store = NetworkIconStore()
		var changes = 0
		store.onChange = { changes += 1 }
		let url = try #require(URL(string: address))

		store.request(url)

		#expect(store.image(for: url) == nil)
		#expect(changes == 0)
	}

	@Test("A non-web address is never fetched")
	func nonWebAddressIsRefused() throws {
		let store = NetworkIconStore()
		let url = try #require(URL(string: "file:///etc/hosts"))

		store.request(url)

		#expect(store.image(for: url) == nil)
	}

	@Test("A server row draws the icon its network advertises, and the glyph otherwise")
	func projectionCarriesTheIcon() throws {
		let session = TestServerSession()
		session.conversationList = []
		let chatSession = ChatSession()
		chatSession.sessions = [session]
		let icon = NSImage(size: NSSize(width: 4, height: 4))
		let withoutIcon = SidebarProjection(
			sessions: chatSession.sessions, selectedItemIdentifier: nil, filter: .all, filterText: ""
		)
		session.supportInfo.processConfigurationData("ICON=https://example.org/icon.png")
		let withIcon = SidebarProjection(
			sessions: chatSession.sessions, selectedItemIdentifier: nil, filter: .all, filterText: "",
			networkIcon: { _ in icon }
		)
		let notFetched = SidebarProjection(
			sessions: chatSession.sessions, selectedItemIdentifier: nil, filter: .all, filterText: ""
		)

		#expect(try #require(withoutIcon.rows.first).networkIcon == nil)
		#expect(try #require(withIcon.rows.first).networkIcon === icon)
		#expect(try #require(notFetched.rows.first).networkIcon == nil)
	}
}
