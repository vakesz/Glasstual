// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/// The client half of the RFC 6455 opening handshake.
@Suite("WebSocket opening handshake")
nonisolated struct WebSocketHandshakeTests {
	/// RFC 6455 §1.3: the sample nonce and the accept value derived from it.
	static let sampleNonce = Array("the sample nonce".utf8)
	static let sampleKey = "dGhlIHNhbXBsZSBub25jZQ=="
	static let sampleAccept = "s3pPLMBiTxaQ9kYGzzhZRbK+xOo="

	static let offer = ["text.ircv3.net", "binary.ircv3.net"]

	static func handshake() -> WebSocketHandshake {
		WebSocketHandshake(offering: offer, nonce: sampleNonce)
	}

	static func response(_ headers: [String], status: String = "101 Switching Protocols") -> Data {
		Data((["HTTP/1.1 \(status)"] + headers).joined(separator: "\r\n").utf8 + Array("\r\n\r\n".utf8))
	}

	static let upgradeHeaders = ["Upgrade: websocket", "Connection: Upgrade", "Sec-WebSocket-Accept: \(sampleAccept)"]

	@Test("The key and accept value match the RFC's worked example")
	func acceptValueMatchesTheRFC() {
		#expect(Self.handshake().key == Self.sampleKey)
		#expect(WebSocketHandshake.acceptValue(forKey: Self.sampleKey) == Self.sampleAccept)
	}

	@Test("Fresh handshakes use fresh keys")
	func keysAreRandom() {
		#expect(WebSocketHandshake(offering: []).key != WebSocketHandshake(offering: []).key)
	}

	@Test("The request carries the target, host, key, version and offer, and nothing else")
	func requestIsMinimal() throws {
		let request = try #require(Self.handshake().request(host: "irc.example.test", port: 8097, secure: true, path: "/irc?x=1"))

		#expect(String(bytes: request, encoding: .utf8) == [
			"GET /irc?x=1 HTTP/1.1",
			"Host: irc.example.test:8097",
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Key: \(Self.sampleKey)",
			"Sec-WebSocket-Version: 13",
			"Sec-WebSocket-Protocol: text.ircv3.net, binary.ircv3.net",
			"",
			"",
		].joined(separator: "\r\n"))
	}

	struct AuthorityCase: Sendable, CustomTestStringConvertible {
		let host: String
		let port: UInt16
		let secure: Bool
		let expected: String

		var testDescription: String {
			"\(secure ? "wss" : "ws")://\(host):\(port)"
		}
	}

	@Test(
		"The Host header names the port only when it is not the scheme's default",
		arguments: [
			AuthorityCase(host: "irc.example.test", port: 80, secure: false, expected: "irc.example.test"),
			AuthorityCase(host: "irc.example.test", port: 443, secure: true, expected: "irc.example.test"),
			AuthorityCase(host: "irc.example.test", port: 443, secure: false, expected: "irc.example.test:443"),
			AuthorityCase(host: "irc.example.test", port: 80, secure: true, expected: "irc.example.test:80"),
			AuthorityCase(host: "127.0.0.1", port: 8080, secure: false, expected: "127.0.0.1:8080"),
			AuthorityCase(host: "2001:db8::1", port: 443, secure: true, expected: "[2001:db8::1]"),
			AuthorityCase(host: "fe80::1%en0", port: 8080, secure: false, expected: "[fe80::1%25en0]:8080"),
		]
	)
	func authority(_ example: AuthorityCase) {
		#expect(WebSocketHandshake.authority(host: example.host, port: example.port, secure: example.secure) == example.expected)
	}

	@Test(
		"An address that could split the request is refused",
		arguments: ["", "irc.example.test\r\nX-Injected: 1", "irc example", "irc/example", "irc@example", "bücher.example"]
	)
	func unsafeAddressesAreRefused(host: String) {
		#expect(Self.handshake().request(host: host, port: 80, secure: false, path: "/") == nil)
	}

	@Test("A response read in pieces completes once its head has arrived, keeping the bytes after it")
	func responseInPieces() throws {
		var handshake = Self.handshake()
		var response = Self.response(Self.upgradeHeaders + ["Sec-WebSocket-Protocol: text.ircv3.net"])
		response.append(contentsOf: [0x81, 0x01, 0x41])

		var upgrade: WebSocketUpgrade?
		for byte in response {
			#expect(upgrade == nil, "the head completed before its terminator")
			upgrade = try handshake.consume(Data([byte])) ?? upgrade
			if upgrade != nil {
				break
			}
		}

		let result = try #require(upgrade)
		#expect(result.subprotocol == "text.ircv3.net")
		#expect(result.remainder.isEmpty)

		var whole = Self.handshake()
		let completed = try #require(try whole.consume(response))
		#expect(completed.remainder == Data([0x81, 0x01, 0x41]))
	}

	@Test("Header names and the upgrade tokens are compared without case")
	func headersIgnoreCase() throws {
		var handshake = Self.handshake()
		let response = Self.response([
			"UPGRADE: WebSocket", "connection: keep-alive, UPGRADE", "sec-websocket-accept: \(Self.sampleAccept)",
		])

		let upgrade = try #require(try handshake.consume(response))
		#expect(upgrade.subprotocol == nil)
	}

	@Test("A status other than 101 is a refusal that names the status")
	func refusalNamesTheStatus() {
		var handshake = Self.handshake()

		#expect(throws: WebSocketHandshakeError.rejected(status: 404)) {
			try handshake.consume(Self.response(["Content-Length: 0"], status: "404 Not Found"))
		}
	}

	static let invalidResponses: [(String, [String])] = [
		("a wrong accept value", ["Upgrade: websocket", "Connection: Upgrade", "Sec-WebSocket-Accept: AAAA"]),
		("no upgrade header", ["Connection: Upgrade", "Sec-WebSocket-Accept: \(sampleAccept)"]),
		("no connection upgrade token", ["Upgrade: websocket", "Connection: close", "Sec-WebSocket-Accept: \(sampleAccept)"]),
		("an extension nobody offered", upgradeHeaders + ["Sec-WebSocket-Extensions: permessage-deflate"]),
		("a subprotocol nobody offered", upgradeHeaders + ["Sec-WebSocket-Protocol: chat"]),
		("a header line with no colon", upgradeHeaders + ["garbage"]),
	]

	@Test("A response that is not a valid upgrade is refused", arguments: invalidResponses.indices)
	func invalidResponsesAreRefused(index: Int) {
		var handshake = Self.handshake()
		let (name, headers) = Self.invalidResponses[index]

		#expect(throws: WebSocketHandshakeError.invalidResponse, "\(name) was accepted") {
			try handshake.consume(Self.response(headers))
		}
	}

	@Test("A response head longer than the ceiling is refused before it ends")
	func overlongResponseIsRefused() throws {
		var handshake = Self.handshake()
		let filler = Data(repeating: 0x41, count: WebSocketHandshake.maximumResponseLength)

		#expect(try handshake.consume(Data("HTTP/1.1 101 OK\r\nX: ".utf8)) == nil)
		#expect(throws: WebSocketHandshakeError.invalidResponse) {
			try handshake.consume(filler)
		}
	}
}
