// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Testing

/** An image fetched for a session goes the way that session's connection is
 configured to go, so a proxy chosen to hide the reader's address is not
 undone by a link or a network icon. */
@MainActor
@Suite("Inline image route")
struct InlineImageRouteTests {
	private static func config(
		_ type: ConnectionProxyKind,
		address: String? = "proxy.example.org",
		port: UInt16 = 1080,
		username: String? = nil
	) -> ServerConfig {
		var config = ServerConfig()
		config.proxyType = type
		config.proxyAddress = address
		config.proxyPort = port
		config.proxyUsername = username
		return config
	}

	@Test("No proxy and the system proxy leave the route to URLSession", arguments: [
		ConnectionProxyKind.none, .automatic,
	])
	func systemRoutes(type: ConnectionProxyKind) {
		let route = InlineImageRoute.forConfig(Self.config(type), proxyPassword: "secret")

		#expect(route == .system)
		#expect(route.resolvesNamesLocally)
		#expect(route.proxyConfigurations.isEmpty)
	}

	@Test("Tor goes to the local Tor listener and never carries a credential")
	func torRoute() {
		let route = InlineImageRoute.forConfig(
			Self.config(.tor, address: "elsewhere.example.org", port: 1, username: "user"),
			proxyPassword: "secret"
		)

		#expect(route == .tor)
		#expect(route.resolvesNamesLocally == false)
		#expect(route.proxyConfigurations.count == 1)
	}

	@Test("SOCKS and HTTP proxies carry their address, port and credential", arguments: [
		(ConnectionProxyKind.socks5, InlineImageRoute.ProxyKind.socks5),
		(.HTTP, .httpConnect),
	])
	func configuredProxyRoutes(type: ConnectionProxyKind, kind: InlineImageRoute.ProxyKind) {
		let route = InlineImageRoute.forConfig(
			Self.config(type, address: "proxy.example.org", port: 3128, username: "user"),
			proxyPassword: "secret"
		)

		#expect(route == .proxy(.init(
			kind: kind, host: "proxy.example.org", port: 3128, username: "user", password: "secret"
		)))
		#expect(route.resolvesNamesLocally == false)
	}

	private nonisolated static let partialCredentials: [(String?, String?)] = [
		(nil, "secret"), ("", "secret"), ("user", nil), ("user", ""),
	]

	@Test("A credential is applied only when both its halves are there", arguments: partialCredentials)
	func partialCredentialIsDropped(username: String?, password: String?) {
		let route = InlineImageRoute.forConfig(Self.config(.socks5, username: username), proxyPassword: password)

		#expect(route == .proxy(.init(kind: .socks5, host: "proxy.example.org", port: 1080)))
	}

	@Test("A SOCKS or HTTP proxy with no address fails closed", arguments: [
		(ConnectionProxyKind.socks5, String?.none), (.socks5, ""), (.HTTP, nil), (.HTTP, ""),
	])
	func missingAddressIsUnavailable(type: ConnectionProxyKind, address: String?) {
		let route = InlineImageRoute.forConfig(Self.config(type, address: address), proxyPassword: nil)

		#expect(route == .unavailable)
		#expect(route.proxyConfigurations.isEmpty)
	}

	@Test("A session's route reads the proxy password the session holds")
	func sessionRouteUsesSessionCredentials() {
		var config = Self.config(.HTTP, username: "user")
		config.pendingProxyPassword = .set("pending")
		let session = ServerSession(config: config)

		#expect(InlineImageRoute(session: session) == .proxy(.init(
			kind: .httpConnect, host: "proxy.example.org", port: 1080, username: "user", password: "pending"
		)))
	}

	@Test("A proxied session configuration names the proxy and never fails over")
	func proxiedConfiguration() throws {
		let route = InlineImageRoute.forConfig(Self.config(.socks5, username: "user"), proxyPassword: "secret")
		let configuration = InlineImageTransfer.configuration(for: route)
		let proxy = try #require(configuration.proxyConfigurations.first)

		#expect(configuration.proxyConfigurations.count == 1)
		#expect(proxy.allowFailover == false)
		#expect(configuration.urlCache == nil)
		#expect(configuration.httpCookieStorage == nil)
	}

	private nonisolated static let socks = InlineImageRoute.proxy(.init(kind: .socks5, host: "proxy.example.org", port: 1080))
	private nonisolated static let http = InlineImageRoute.proxy(.init(kind: .httpConnect, host: "proxy.example.org", port: 3128))
	/// A proxy at Tor's own address is still the reader's proxy, not Tor.
	private nonisolated static let socksAtTorAddress = InlineImageRoute.proxy(.init(kind: .socks5, host: "127.0.0.1", port: 9150))

	@Test("Each route decides when an inline image is fetched", arguments: [
		(InlineImageRoute.system, InlineImageRoute.FetchPolicy.automatic),
		(.tor, .automatic),
		(socks, .onRequest),
		(http, .onRequest),
		(socksAtTorAddress, .onRequest),
		(.unavailable, .never),
	])
	func inlineImageFetchDecision(route: InlineImageRoute, policy: InlineImageRoute.FetchPolicy) {
		#expect(route.inlineImageFetch == policy)
	}

	@Test("Each route decides whether a network icon is fetched", arguments: [
		(InlineImageRoute.system, InlineImageRoute.FetchPolicy.automatic),
		(.tor, .automatic),
		(socks, .never),
		(http, .never),
		(socksAtTorAddress, .never),
		(.unavailable, .never),
	])
	func networkIconFetchDecision(route: InlineImageRoute, policy: InlineImageRoute.FetchPolicy) {
		#expect(route.networkIconFetch == policy)
	}

	@Test("A session's proxy setting decides when its images are fetched", arguments: [
		(ConnectionProxyKind.none, InlineImageRoute.FetchPolicy.automatic),
		(.automatic, .automatic),
		(.tor, .automatic),
		(.socks5, .onRequest),
		(.HTTP, .onRequest),
	])
	func configuredFetchDecision(type: ConnectionProxyKind, image: InlineImageRoute.FetchPolicy) {
		let route = InlineImageRoute.forConfig(Self.config(type), proxyPassword: nil)

		#expect(route.inlineImageFetch == image)
	}

	@Test("A system route configures no proxy of its own")
	func systemConfiguration() {
		#expect(InlineImageTransfer.configuration(for: .system).proxyConfigurations.isEmpty)
	}
}
