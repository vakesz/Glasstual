// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

/** How an image fetched on behalf of one session reaches the network.

 A session configured for a SOCKS, HTTP or Tor proxy hides the reader's address
 from its IRC network, and an image a line links to, or the icon the network
 advertises, must not undo that. The route follows the session's configuration,
 not its live connection: an image is fetched through the configured proxy even
 while disconnected, or after the user connected once without it. A configured
 proxy is never bypassed; a fetch it cannot carry fails. */
nonisolated enum InlineImageRoute: Sendable, Hashable {
	/// The system's own proxy settings, which URLSession applies by itself.
	case system
	/// The proxy the session is configured to use.
	case proxy(Proxy)
	/// A proxy is configured but has no address, so nothing may be fetched.
	case unavailable

	enum ProxyKind: Sendable, Hashable {
		case socks5
		case httpConnect
	}

	struct Proxy: Sendable, Hashable {
		var kind: ProxyKind
		var host: String
		var port: UInt16
		var username: String?
		var password: String?
	}

	/// The Tor Browser's SOCKS listener, which `ConnectionParameters` in the
	/// connection host dials for a Tor session as well.
	static let torProxy = Proxy(kind: .socks5, host: "127.0.0.1", port: 9150)

	/// The route a session with `config` takes, given its proxy password.
	static func forConfig(_ config: ServerConfig, proxyPassword: String?) -> InlineImageRoute {
		let kind: ProxyKind
		switch config.proxyType {
		case .none, .automatic:
			return .system
		case .tor:
			// Tor separates circuits by credential; the connection host sends none either.
			return .proxy(torProxy)
		case .socks5:
			kind = .socks5
		case .HTTP:
			kind = .httpConnect
		}

		guard let host = config.proxyAddress, host.isEmpty == false else {
			return .unavailable
		}

		var proxy = Proxy(kind: kind, host: host, port: config.proxyPort)

		if let username = config.proxyUsername, username.isEmpty == false,
		   let proxyPassword, proxyPassword.isEmpty == false
		{
			proxy.username = username
			proxy.password = proxyPassword
		}

		return .proxy(proxy)
	}

	/** The route images fetched for `session` take.

	 The password is the one the session's credentials hold, read the same way
	 `connect()` reads it and never from the keychain here. Before the session
	 has loaded its credentials there is none, and a proxy that needs one
	 refuses the fetch rather than the fetch going around it. */
	@MainActor
	init(session: ServerSession) {
		let config = session.config
		let password = config.pendingProxyPassword.value(
			orStored: session.sessionCredentials.password(for: config.proxyPasswordKeychainItem)
		)
		self = Self.forConfig(config, proxyPassword: password)
	}

	/// Whether a host name may be looked up on this Mac. Through a proxy it may
	/// not: the lookup itself would tell the resolver what is being fetched.
	var resolvesNamesLocally: Bool {
		switch self {
		case .system, .unavailable: true
		case .proxy: false
		}
	}

	/// The Network proxy a URLSession on this route must use, with no failover
	/// to a direct connection.
	var proxyConfigurations: [ProxyConfiguration] {
		guard case let .proxy(proxy) = self else { return [] }

		let endpoint = NWEndpoint.hostPort(
			host: NWEndpoint.Host(proxy.host),
			port: NWEndpoint.Port(integerLiteral: proxy.port)
		)

		var configuration = switch proxy.kind {
		case .socks5: ProxyConfiguration(socksv5Proxy: endpoint)
		case .httpConnect: ProxyConfiguration(httpCONNECTProxy: endpoint)
		}

		configuration.allowFailover = false

		if let username = proxy.username, let password = proxy.password {
			configuration.applyCredential(username: username, password: password)
		}

		return [configuration]
	}
}
