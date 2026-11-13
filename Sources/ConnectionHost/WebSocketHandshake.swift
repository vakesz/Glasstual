// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation

/// The server answered the upgrade request with something other than an
/// upgrade.
nonisolated enum WebSocketHandshakeError: Error, Sendable, Equatable {
	/// A well-formed HTTP response with a status other than 101.
	case rejected(status: Int)
	/// A response that is not a valid RFC 6455 upgrade: malformed, too long,
	/// with the wrong accept value, or agreeing to something not offered.
	case invalidResponse
}

/// A completed upgrade.
nonisolated struct WebSocketUpgrade: Sendable, Equatable {
	/// The subprotocol the server chose from the offer, or nil when it chose none.
	let subprotocol: String?
	/// Bytes that followed the response in the same read: the first frames.
	let remainder: Data
}

/** The client's half of the RFC 6455 opening handshake.

 The request carries the host, the request target, a fresh key, the version
 and the subprotocol offer, and nothing else: no `Origin`, cookies,
 credentials or extensions. Offering no extension is what keeps compression,
 and the decompression it would let a server demand, out of the host.

 The response is read up to ``maximumResponseLength`` bytes. A server must
 echo the key's accept value, upgrade to `websocket`, and agree to nothing it
 was not offered. */
nonisolated struct WebSocketHandshake: Sendable {
	/// The longest response head accepted, in bytes.
	static let maximumResponseLength = 8 * 1024

	private static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
	private static let headTerminator = Data("\r\n\r\n".utf8)

	/// The `Sec-WebSocket-Key` value: sixteen random bytes in base64.
	let key: String
	private let offeredSubprotocols: [String]
	private var response = Data()

	/// `nonce` is sixteen bytes from a strong random source.
	init(offering subprotocols: [String], nonce: [UInt8]) {
		precondition(nonce.count == 16)
		key = Data(nonce).base64EncodedString()
		offeredSubprotocols = subprotocols
	}

	init(offering subprotocols: [String]) {
		var generator = SystemRandomNumberGenerator()

		self.init(offering: subprotocols, nonce: (0 ..< 16).map { _ in UInt8.random(in: .min ... .max, using: &generator) })
	}

	/// The value a server derives from `key` to prove it read the request.
	static func acceptValue(forKey key: String) -> String {
		Data(Insecure.SHA1.hash(data: Data((key + acceptGUID).utf8))).base64EncodedString()
	}

	/** The upgrade request for `path` on `host`, or nil when `host` cannot be
	 written into a `Host` header.

	 `path` has already passed ``WebSocketTransportOptions/isValidPath(_:)``;
	 the host is checked here, because it reaches this request as typed. */
	func request(host: String, port: UInt16, secure: Bool, path: String) -> Data? {
		guard let authority = Self.authority(host: host, port: port, secure: secure) else {
			return nil
		}

		var lines = [
			"GET \(path) HTTP/1.1",
			"Host: \(authority)",
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Key: \(key)",
			"Sec-WebSocket-Version: 13",
		]

		if offeredSubprotocols.isEmpty == false {
			lines.append("Sec-WebSocket-Protocol: \(offeredSubprotocols.joined(separator: ", "))")
		}

		return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

	/** The `Host` header value: the port is left out when it is the scheme's
	 default, and an IPv6 literal is bracketed with its zone escaped.

	 Only the characters a host name or address literal can hold are accepted,
	 so nothing typed as an address can add a header or end the request. */
	static func authority(host: String, port: UInt16, secure: Bool) -> String? {
		let name: String

		if host.contains(":") {
			/* An IPv6 literal, with an optional zone after `%` naming an interface. */
			let parts = host.split(separator: "%", maxSplits: 1, omittingEmptySubsequences: false)

			guard consists(parts[0], of: hexadecimal + ":."),
			      parts.count == 1 || consists(parts[1], of: hostName)
			else {
				return nil
			}

			name = "[" + parts.joined(separator: "%25") + "]"
		} else {
			guard consists(host[...], of: hostName) else { return nil }

			name = host
		}

		let defaultPort: UInt16 = secure ? 443 : 80

		return port == defaultPort ? name : "\(name):\(port)"
	}

	private static let hexadecimal = "0123456789abcdefABCDEF"
	private static let hostName = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._"

	private static func consists(_ text: Substring, of allowed: String) -> Bool {
		text.isEmpty == false && text.unicodeScalars.allSatisfy { allowed.unicodeScalars.contains($0) }
	}

	/// Reads `data` as more of the response: nil while the head is incomplete,
	/// the upgrade once it has arrived and checks out.
	mutating func consume(_ data: Data) throws(WebSocketHandshakeError) -> WebSocketUpgrade? {
		response.append(data)

		guard let terminator = response.range(of: Self.headTerminator) else {
			guard response.count <= Self.maximumResponseLength else { throw .invalidResponse }

			return nil
		}

		guard terminator.lowerBound - response.startIndex <= Self.maximumResponseLength, let head = String(
			bytes: response[..<terminator.lowerBound],
			encoding: .utf8
		) else {
			throw .invalidResponse
		}

		let subprotocol = try validate(head)

		return WebSocketUpgrade(subprotocol: subprotocol, remainder: Data(response[terminator.upperBound...]))
	}

	/// The chosen subprotocol, once `head` is shown to be a valid upgrade.
	private func validate(_ head: String) throws(WebSocketHandshakeError) -> String? {
		var lines = head.components(separatedBy: "\r\n")
		let statusLine = lines.removeFirst().split(separator: " ", maxSplits: 2)

		guard statusLine.count >= 2, statusLine[0].hasPrefix("HTTP/1."), let status = Int(statusLine[1]) else {
			throw .invalidResponse
		}

		guard status == 101 else { throw .rejected(status: status) }

		var headers: [String: String] = [:]
		for line in lines {
			guard let colon = line.firstIndex(of: ":") else { throw .invalidResponse }

			let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
			let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)

			headers[name] = headers[name].map { $0 + ", " + value } ?? value
		}

		let connectionTokens = (headers["connection"] ?? "").lowercased()
			.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }

		guard headers["upgrade"]?.lowercased() == "websocket",
		      connectionTokens.contains("upgrade"),
		      headers["sec-websocket-accept"] == Self.acceptValue(forKey: key),
		      (headers["sec-websocket-extensions"] ?? "").isEmpty
		else {
			throw .invalidResponse
		}

		guard let subprotocol = headers["sec-websocket-protocol"], subprotocol.isEmpty == false else {
			return nil
		}

		guard offeredSubprotocols.contains(subprotocol) else { throw .invalidResponse }

		return subprotocol
	}
}
