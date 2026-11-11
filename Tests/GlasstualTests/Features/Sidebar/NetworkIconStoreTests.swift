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

		store.request(url, route: .system)

		#expect(store.image(for: url) == nil)
		#expect(changes == 0)
	}

	@Test("A non-web address is never fetched")
	func nonWebAddressIsRefused() throws {
		let store = NetworkIconStore()
		let url = try #require(URL(string: "file:///etc/hosts"))

		store.request(url, route: .system)

		#expect(store.image(for: url) == nil)
	}

	@Test("A network whose session's proxy has no address is never fetched")
	func unavailableRouteIsNotFetched() {
		let url = InlineImageTestProtocol.register(.init(chunk: Data("GIF89a".utf8)))
		defer { InlineImageTestProtocol.remove(url) }
		let store = NetworkIconStore(protocolClasses: [InlineImageTestProtocol.self])

		store.request(url, route: .unavailable)

		#expect(store.isFetching(url, route: .unavailable) == false)
		#expect(store.image(for: url) == nil)
		#expect(InlineImageTestProtocol.started(url) == false)
	}

	@Test("A session on the reader's own SOCKS5 or HTTP proxy requests no icon", arguments: [
		InlineImageRoute.ProxyKind.socks5, .httpConnect,
	])
	func proxiedRouteRequestsNoIcon(kind: InlineImageRoute.ProxyKind) {
		let url = InlineImageTestProtocol.register(.init(chunk: Data("GIF89a".utf8)))
		defer { InlineImageTestProtocol.remove(url) }
		let store = NetworkIconStore(protocolClasses: [InlineImageTestProtocol.self])
		let route = InlineImageRoute.proxy(.init(kind: kind, host: "proxy.example.org", port: 1080))

		store.request(url, route: route)

		#expect(store.isFetching(url, route: route) == false)
		#expect(InlineImageTestProtocol.startCount(url) == 0)
	}

	@Test("Tor and the system route request the icon", arguments: [InlineImageRoute.tor, .system])
	func automaticRouteRequestsIcon(route: InlineImageRoute) async throws {
		let url = InlineImageTestProtocol.register(.init(hold: true))
		defer { InlineImageTestProtocol.remove(url) }
		let store = NetworkIconStore(protocolClasses: [InlineImageTestProtocol.self])

		store.request(url, route: route)

		#expect(store.isFetching(url, route: route))
		try await Eventually.until(timeout: .seconds(10), "the request to reach the network") {
			InlineImageTestProtocol.startCount(url) == 1
		}
	}

	@Test("An icon fetched over Tor is not looked up on this Mac", .timeLimit(.minutes(1)))
	func proxiedIconIsNotResolved() async throws {
		let url = try InlineImageTestProtocol.register(.init(
			headers: ["Content-Type": "image/png"],
			chunk: Self.pngData()
		))
		defer { InlineImageTestProtocol.remove(url) }
		let counter = LookupCounter()
		let store = NetworkIconStore(
			protocolClasses: [InlineImageTestProtocol.self],
			hostResolver: InlineImageHostResolver { host in await counter.lookup(host) }
		)
		let route = InlineImageRoute.tor
		var changes = 0
		store.onChange = { changes += 1 }

		store.request(url, route: route)
		#expect(store.isFetching(url, route: route))
		#expect(store.isFetching(url, route: .system) == false)

		try await Eventually.until(timeout: .seconds(10), "the icon to arrive") { changes == 1 }
		#expect(store.image(for: url) != nil)
		#expect(await counter.callCount == 0)
	}

	private static func pngData() throws -> Data {
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		return try #require(bitmap.representation(using: .png, properties: [:]))
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
