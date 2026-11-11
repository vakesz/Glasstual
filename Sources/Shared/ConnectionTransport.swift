// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Which framing carries IRC lines between the host and the server.

 Travels inside ``ConnectionConfigEnvelope`` only. The TLS, proxy and address
 settings beside it apply to both: a WebSocket runs over the same TCP or TLS
 connection a stream does. */
nonisolated enum ConnectionTransport: Codable, Sendable, Equatable {
	/// TCP or TLS carrying CRLF-terminated lines.
	case stream
	/// An RFC 6455 WebSocket carrying one IRC line per message, as the IRCv3
	/// WebSocket specification describes.
	case webSocket(WebSocketTransportOptions)

	private enum Kind: String, Codable {
		case stream
		case webSocket
	}

	private enum CodingKeys: String, CodingKey {
		case kind
		case webSocket
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		switch try container.decode(Kind.self, forKey: .kind) {
		case .stream:
			self = .stream
		case .webSocket:
			self = try .webSocket(container.decode(WebSocketTransportOptions.self, forKey: .webSocket))
		}
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		switch self {
		case .stream:
			try container.encode(Kind.stream, forKey: .kind)
		case let .webSocket(options):
			try container.encode(Kind.webSocket, forKey: .kind)
			try container.encode(options, forKey: .webSocket)
		}
	}

	/// The port a configuration that names none dials.
	func defaultPort(secure: Bool) -> UInt16 {
		switch self {
		case .stream:
			ConnectionDefaults.serverPort
		case .webSocket:
			secure ? ConnectionDefaults.webSocketPortSecure : ConnectionDefaults.webSocketPort
		}
	}
}

/// The subprotocols the IRCv3 WebSocket specification defines.
nonisolated enum WebSocketSubprotocol: String, Codable, Sendable, CaseIterable {
	/// Text frames: every line is UTF-8.
	case text = "text.ircv3.net"
	/// Binary frames: lines are bytes in whatever encoding the session uses.
	case binary = "binary.ircv3.net"
}

/** Where a WebSocket upgrade is requested, and which subprotocols it offers.

 An XPC peer can reach the decoder, so decoding repairs rather than refuses:
 a path that breaks ``isValidPath(_:)`` becomes `/`, unknown subprotocols are
 dropped, and an empty offer becomes both, text first. */
nonisolated struct WebSocketTransportOptions: Codable, Sendable, Equatable {
	/// The longest request target accepted, in UTF-8 bytes.
	static let maximumPathLength = 1024

	/// The request target: percent-encoded, starting with `/`, with an optional
	/// query and no fragment.
	var path: String
	/// The offer, most preferred first.
	var subprotocols: [WebSocketSubprotocol]

	init(path: String = "/", subprotocols: [WebSocketSubprotocol] = WebSocketSubprotocol.allCases) {
		self.path = path
		self.subprotocols = subprotocols
	}

	private enum CodingKeys: String, CodingKey {
		case path
		case subprotocols
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		path = container.decode(String.self, forKey: .path, default: "/")
		subprotocols = container.decode([String].self, forKey: .subprotocols, default: [])
			.compactMap(WebSocketSubprotocol.init(rawValue:))

		self = repaired()
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encode(path, forKey: .path)
		try container.encode(subprotocols.map(\.rawValue), forKey: .subprotocols)
	}

	/// These options with the path and offer put back inside the rules the
	/// host relies on when it writes the upgrade request.
	func repaired() -> WebSocketTransportOptions {
		var offer: [WebSocketSubprotocol] = []
		for subprotocol in subprotocols where offer.contains(subprotocol) == false {
			offer.append(subprotocol)
		}

		return WebSocketTransportOptions(
			path: Self.isValidPath(path) ? path : "/",
			subprotocols: offer.isEmpty ? WebSocketSubprotocol.allCases : offer
		)
	}

	/** Whether `path` can be written into a request line as it is.

	 It starts with `/`, holds only printable ASCII with no space and no `#`,
	 every `%` begins a two-digit escape, and URL parsing gives back exactly
	 the same path and query. A CR, LF or NUL can therefore never reach the
	 request, which is what keeps a configured path from splitting it. */
	static func isValidPath(_ path: String) -> Bool {
		let bytes = Array(path.utf8)

		guard bytes.first == UInt8(ascii: "/"), bytes.count <= maximumPathLength else {
			return false
		}

		var index = 0
		while index < bytes.count {
			let byte = bytes[index]

			guard byte > 0x20, byte < 0x7F, byte != UInt8(ascii: "#") else {
				return false
			}

			guard byte == UInt8(ascii: "%") else {
				index += 1

				continue
			}

			guard index + 2 < bytes.count, isHexDigit(bytes[index + 1]), isHexDigit(bytes[index + 2]) else {
				return false
			}

			index += 3
		}

		guard let components = URLComponents(string: "ws://host" + path) else {
			return false
		}

		return components.percentEncodedPath + (components.percentEncodedQuery.map { "?" + $0 } ?? "") == path
	}

	private static func isHexDigit(_ byte: UInt8) -> Bool {
		switch byte {
		case UInt8(ascii: "0") ... UInt8(ascii: "9"),
		     UInt8(ascii: "a") ... UInt8(ascii: "f"),
		     UInt8(ascii: "A") ... UInt8(ascii: "F"):
			true
		default:
			false
		}
	}
}
