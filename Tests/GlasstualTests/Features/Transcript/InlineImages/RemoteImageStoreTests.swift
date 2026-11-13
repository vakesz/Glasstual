// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Counts the change messages one store posts.
@MainActor
private final class ChangeCounter {
	private(set) var count = 0
	private let subscriptions = NotificationSubscriptions()

	init(_ store: RemoteImageStore, center: NotificationCenter) {
		subscriptions.observe(RemoteImageStoreDidChange.self, of: store, center: center) { [weak self] _ in
			self?.count += 1
		}
	}
}

@MainActor
@Suite("Remote images", .timeLimit(.minutes(1)))
struct RemoteImageStoreTests {
	private let center = NotificationCenter()

	private func store(
		_ configuration: RemoteImageStore.Configuration = .networkIcons,
		stubbed: Bool = true,
		hostResolver: InlineImageHostResolver? = nil,
		now: @escaping @MainActor () -> ContinuousClock.Instant = { .now }
	) -> RemoteImageStore {
		RemoteImageStore(
			configuration: configuration,
			protocolClasses: stubbed ? [InlineImageTestProtocol.self] : [],
			hostResolver: hostResolver,
			notificationCenter: center,
			now: now
		)
	}

	@Test("An address that names a local or private host is never fetched", arguments: [
		"http://127.0.0.1/icon.png",
		"https://localhost/icon.png",
		"https://192.168.1.10/icon.png",
		"https://[::1]/icon.png",
		"https://printer/icon.png",
	])
	func privateHostIsRefused(_ address: String) throws {
		let store = store(stubbed: false)
		let changes = ChangeCounter(store, center: center)
		let url = try #require(URL(string: address))

		store.request(url, route: .system, owner: "a")

		#expect(store.image(for: url) == nil)
		#expect(store.isFetching(url, route: .system) == false)
		#expect(changes.count == 0)
	}

	@Test("A non-web address is never fetched")
	func nonWebAddressIsRefused() throws {
		let store = store(stubbed: false)
		let url = try #require(URL(string: "file:///etc/hosts"))

		store.request(url, route: .system, owner: "a")

		#expect(store.image(for: url) == nil)
		#expect(store.isFetching(url, route: .system) == false)
	}

	@Test("A session whose proxy has no address fetches nothing")
	func unavailableRouteIsNotFetched() {
		let url = InlineImageTestProtocol.register(.init(chunk: Data("GIF89a".utf8)))
		defer { InlineImageTestProtocol.remove(url) }
		let store = store()

		store.request(url, route: .unavailable, owner: "a")

		#expect(store.isFetching(url, route: .unavailable) == false)
		#expect(InlineImageTestProtocol.started(url) == false)
	}

	@Test(
		"A session on the reader's own SOCKS5 or HTTP proxy fetches no icon and no avatar",
		arguments: [InlineImageRoute.ProxyKind.socks5, .httpConnect]
	)
	func proxiedRouteFetchesNothing(kind: InlineImageRoute.ProxyKind) {
		let url = InlineImageTestProtocol.register(.init(chunk: Data("GIF89a".utf8)))
		defer { InlineImageTestProtocol.remove(url) }
		let route = InlineImageRoute.proxy(.init(kind: kind, host: "proxy.example.org", port: 1080))

		for configuration in [RemoteImageStore.Configuration.networkIcons, .avatars] {
			let store = store(configuration)
			store.request(url, route: route, owner: "a")
			#expect(store.isFetching(url, route: route) == false)
		}
		#expect(InlineImageTestProtocol.startCount(url) == 0)
	}

	@Test("Tor and the system route fetch", arguments: [InlineImageRoute.tor, .system])
	func automaticRouteFetches(route: InlineImageRoute) async throws {
		let url = InlineImageTestProtocol.register(.init(hold: true))
		defer { InlineImageTestProtocol.remove(url) }
		let store = store()

		store.request(url, route: route, owner: "a")

		#expect(store.isFetching(url, route: route))
		try await Eventually.until(timeout: .seconds(10), "the request to reach the network") {
			InlineImageTestProtocol.startCount(url) == 1
		}
	}

	@Test("An image fetched over Tor is not looked up on this Mac")
	func proxiedImageIsNotResolved() async throws {
		let url = try Self.registerPNG()
		defer { InlineImageTestProtocol.remove(url) }
		let counter = LookupCounter()
		let store = store(hostResolver: InlineImageHostResolver { host in await counter.lookup(host) })
		let changes = ChangeCounter(store, center: center)

		store.request(url, route: .tor, owner: "a")
		#expect(store.isFetching(url, route: .tor))
		#expect(store.isFetching(url, route: .system) == false)

		try await Eventually.until(timeout: .seconds(10), "the image to arrive") { changes.count == 1 }
		#expect(store.image(for: url) != nil)
		#expect(await counter.callCount == 0)
	}

	@Test("Each configuration keeps its own ceilings")
	func limitsPerConfiguration() {
		let icons = RemoteImageStore.Configuration.networkIcons
		let avatars = RemoteImageStore.Configuration.avatars

		#expect(icons.capacity == 32)
		#expect(icons.failureRetryInterval == nil)
		#expect(avatars.capacity == 512)
		#expect(avatars.maximumConcurrentFetches == 4)
		#expect(avatars.limits.maximumEncodedBytes == 256 * 1024)
		#expect(avatars.limits.maximumFrames == 1)
		#expect(avatars.limits.maximumDimension == 1024)
		#expect(avatars.limits.maximumDecodedBytes == 16 * 1024 * 1024)
		#expect(avatars.failureRetryInterval == .seconds(600))
	}

	@Test("Fetches past the concurrency limit wait, and past the queue they are dropped")
	func concurrencyGate() {
		var configuration = RemoteImageStore.Configuration.avatars
		configuration.maximumConcurrentFetches = 1
		configuration.maximumQueuedFetches = 1
		let urls = (0 ..< 3).map { _ in InlineImageTestProtocol.register(.init(hold: true)) }
		defer { urls.forEach(InlineImageTestProtocol.remove) }
		let store = store(configuration)

		for url in urls {
			store.request(url, route: .system, owner: "a")
		}

		#expect(store.isFetching(urls[0], route: .system))
		#expect(store.isQueued(urls[1], route: .system))
		#expect(store.isFetching(urls[2], route: .system) == false)
		#expect(store.isQueued(urls[2], route: .system) == false)

		store.release(owner: "a")
		#expect(store.isFetching(urls[0], route: .system) == false)
		#expect(store.isQueued(urls[1], route: .system) == false)
	}

	@Test("Releasing one owner keeps an image another owner still names")
	func releaseKeepsSharedImages() async throws {
		let url = try Self.registerPNG()
		defer { InlineImageTestProtocol.remove(url) }
		let store = store(.avatars)
		let changes = ChangeCounter(store, center: center)

		store.request(url, route: .system, owner: "a")
		store.request(url, route: .system, owner: "b")
		try await Eventually.until(timeout: .seconds(10), "the image to arrive") { changes.count == 1 }

		store.release(owner: "a")
		#expect(store.image(for: url) != nil)

		store.release(owner: "b")
		#expect(store.image(for: url) == nil)
	}

	@Test("A failed fetch is retried only after the configured interval")
	func failureRetryInterval() async throws {
		let url = InlineImageTestProtocol.register(.init(status: 404))
		defer { InlineImageTestProtocol.remove(url) }
		var instant = ContinuousClock.now
		let store = store(.avatars, now: { instant })

		store.request(url, route: .system, owner: "a")
		try await Eventually.until(timeout: .seconds(10), "the failure") {
			store.isFetching(url, route: .system) == false
		}

		store.request(url, route: .system, owner: "a")
		#expect(store.isFetching(url, route: .system) == false)

		instant = instant.advanced(by: .seconds(601))
		store.request(url, route: .system, owner: "a")
		#expect(store.isFetching(url, route: .system))
		try await Eventually.until(timeout: .seconds(10), "the second request") {
			InlineImageTestProtocol.startCount(url) == 2
		}
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

		#expect(try #require(withoutIcon.rows.first).networkIcon == nil)
		#expect(try #require(withIcon.rows.first).networkIcon === icon)
	}

	private static func registerPNG() throws -> URL {
		let bitmap = try #require(NSBitmapImageRep(
			bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
			hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
		))
		let data = try #require(bitmap.representation(using: .png, properties: [:]))

		return InlineImageTestProtocol.register(.init(headers: ["Content-Type": "image/png"], chunk: data))
	}
}
