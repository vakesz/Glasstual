// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** How a configured server is reached: IRC over TCP or TLS, or IRC over an
 IRCv3 WebSocket.

 `prefersSecuredConnection` keeps its one meaning beside this — encrypted —
 so a secure WebSocket is `wss` and a plain one is `ws`. */
nonisolated enum ServerTransport: String, Codable, Sendable, CaseIterable {
	case irc
	case webSocket = "websocket"

	/// The port a server entry of this transport takes when none is given.
	func defaultPort(secured: Bool) -> UInt16 {
		switch self {
		case .irc:
			secured ? ConnectionDefaults.serverPortSecure : ConnectionDefaults.serverPort
		case .webSocket:
			secured ? ConnectionDefaults.webSocketPortSecure : ConnectionDefaults.webSocketPort
		}
	}

	/// The URL scheme a WebSocket endpoint is written in.
	static func webSocketScheme(secured: Bool) -> String {
		secured ? "wss" : "ws"
	}

	/** Whether `path` may be stored as a WebSocket request target.

	 One rule for every place a path comes from — the server properties sheet,
	 an imported file, a pasted or typed URL — and the same one the connection
	 host repairs against, so what the app accepts is exactly what is sent. */
	static func isValidWebSocketPath(_ path: String) -> Bool {
		WebSocketTransportOptions.isValidPath(path)
	}
}

/// A `ws://` or `wss://` address taken apart into what a server entry stores.
nonisolated struct WebSocketAddress: Equatable, Sendable {
	let host: String
	let port: UInt16
	let secured: Bool
	let path: String
	/// The channels a fragment named, as `irc://host/#a,b` names them.
	let channelFragment: String?

	/** Parses `location`, or answers nil for anything that is not a WebSocket
	 URL a server entry can hold.

	 A user name or password is refused, as it is for `irc:` links: a link
	 must not carry credentials into a configuration. The path keeps its
	 percent-encoding and query; the fragment is not part of the request and is
	 handed back separately. */
	init?(_ location: String) {
		guard location.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
		      let components = URLComponents(string: location, encodingInvalidCharacters: false),
		      let scheme = components.scheme?.lowercased(), scheme == "ws" || scheme == "wss",
		      components.user == nil, components.password == nil,
		      let encodedHost = components.percentEncodedHost,
		      var host = encodedHost.removingPercentEncoding, host.isEmpty == false
		else { return nil }

		if host.hasPrefix("["), host.hasSuffix("]") {
			host = String(host.dropFirst().dropLast())
		}
		guard host.isValidInternetAddress else { return nil }

		let secured = scheme == "wss"
		let defaultPort = ServerTransport.webSocket.defaultPort(secured: secured)
		guard let port = UInt16(exactly: components.port ?? Int(defaultPort)), port > 0 else { return nil }

		var path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
		if let query = components.percentEncodedQuery {
			path += "?" + query
		}
		guard ServerTransport.isValidWebSocketPath(path) else { return nil }

		self.host = host.lowercased()
		self.port = port
		self.secured = secured
		self.path = path
		channelFragment = components.percentEncodedFragment
	}

	/** The channels the fragment names, as a comma-separated list: in
	 `wss://host/irc#a,b` the fragment is `a,b`, which is `#a` and `#b`, the
	 way `irc://host/#a,b` reads. */
	var fragmentChannelList: String? {
		guard let fragment = channelFragment?.removingPercentEncoding, fragment.isEmpty == false else { return nil }
		return fragment.split(separator: ",").map { name in
			name.first.map { "#&+!".contains($0) } == true ? String(name) : "#" + name
		}.joined(separator: ",")
	}

	/// `ws://host:port/path`, bracketing an IPv6 literal.
	static func url(host: String, port: UInt16, secured: Bool, path: String) -> String {
		let bracketed = host.contains(":") ? "[\(host)]" : host
		return "\(ServerTransport.webSocketScheme(secured: secured))://\(bracketed):\(port)\(path)"
	}

	/** The URL with every query value replaced by `…`, for the console.

	 A gateway may take a token in the query; the console, the transcript log
	 and a screenshot of either are no place for it. */
	static func displayURL(host: String, port: UInt16, secured: Bool, path: String) -> String {
		guard let queryStart = path.firstIndex(of: "?") else {
			return url(host: host, port: port, secured: secured, path: path)
		}
		let query = path[path.index(after: queryStart)...].split(separator: "&", omittingEmptySubsequences: false).map { item in
			guard let equals = item.firstIndex(of: "=") else { return item.isEmpty ? "" : "…" }
			return item[..<equals] + "=…"
		}.joined(separator: "&")
		return url(host: host, port: port, secured: secured, path: path[..<queryStart] + "?" + query)
	}
}
