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
 proxy is never bypassed; a fetch it cannot carry fails.

 The route also decides when a fetch may start at all, in ``inlineImageFetch``
 and ``networkIconFetch``. */
nonisolated enum InlineImageRoute: Sendable, Hashable {
	/// The system's own proxy settings, which URLSession applies by itself.
	case system
	/// The local Tor listener a Tor session connects through.
	case tor
	/// The SOCKS5 or HTTP proxy the reader configured for the session.
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
			return .tor
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

	/// When a fetch on a route may start.
	enum FetchPolicy: Sendable, Hashable {
		/// As soon as the link or the icon is seen.
		case automatic
		/// Only when the reader asks for that one image.
		case onRequest
		/// Not at all.
		case never
	}

	/** When an image a line links to is fetched.

	 A reader's own SOCKS5 or HTTP proxy resolves the host name itself, so this
	 Mac can check only how the name is spelled, and a name that the proxy
	 resolves to an address on its own network passes that check. Whoever
	 posted the link chose that name, so the fetch waits for the reader to ask
	 for the image. A Tor exit refuses private addresses itself, and the system
	 route checks resolved addresses here, so both fetch on sight. A route that
	 cannot carry a fetch offers none. */
	var inlineImageFetch: FetchPolicy {
		switch self {
		case .system, .tor: .automatic
		case .proxy: .onRequest
		case .unavailable: .never
		}
	}

	/** When the icon a network advertises is fetched.

	 The address comes from the server, and nothing in the sidebar asks the
	 reader before fetching it, so a route where only the name's spelling can
	 be checked fetches no icon and the row keeps its glyph. */
	var networkIconFetch: FetchPolicy {
		switch self {
		case .system, .tor: .automatic
		case .proxy, .unavailable: .never
		}
	}

	/** Whether a fetch may follow a redirect to a host other than the one the
	 link named.

	 On a reader's own SOCKS5 or HTTP proxy the reader asked for that one host,
	 and a redirect could name one only that proxy's network resolves, which
	 this Mac cannot check. Tor and the system route hold every hop to the
	 same checks as the link. */
	var followsRedirectsToOtherHosts: Bool {
		switch self {
		case .system, .tor, .unavailable: true
		case .proxy: false
		}
	}

	/// Whether a host name may be looked up on this Mac. Through a proxy it may
	/// not: the lookup itself would tell the resolver what is being fetched.
	var resolvesNamesLocally: Bool {
		switch self {
		case .system, .unavailable: true
		case .tor, .proxy: false
		}
	}

	/// The proxy every fetch on this route goes through, if any.
	private var proxy: Proxy? {
		switch self {
		case .tor: Self.torProxy
		case let .proxy(proxy): proxy
		case .system, .unavailable: nil
		}
	}

	/// The Network proxy a URLSession on this route must use, with no failover
	/// to a direct connection.
	var proxyConfigurations: [ProxyConfiguration] {
		guard let proxy else { return [] }

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
