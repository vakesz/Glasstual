// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/// One IRC line per WebSocket message, as the IRCv3 specification asks, and
/// the stream transport's splitting when no subprotocol was agreed.
@Suite("WebSocket line codec")
nonisolated struct WebSocketLineCodecTests {
	static let ceiling = 16 * 1024

	static func codec(_ framing: WebSocketLineFraming) -> WebSocketLineCodec {
		WebSocketLineCodec(framing: framing, maximumLineLength: ceiling)
	}

	static func bytes(_ string: String) -> Data {
		Data(string.utf8)
	}

	@Test(
		"A negotiated message is one line, with a trailing terminator tolerated",
		arguments: [
			("PING :a", ["PING :a"]),
			("PING :a\r\n", ["PING :a"]),
			("PING :a\r\r\n", ["PING :a"]),
			("PING :a\n", ["PING :a"]),
			("", []),
			("\r\n", []),
		]
	)
	func negotiatedInbound(message: String, expected: [String]) throws {
		let lines = try Self.codec(.negotiated(.text)).lines(fromMessage: Self.bytes(message))

		#expect(lines == expected.map(Self.bytes))
	}

	@Test(
		"A negotiated message carrying a second line or a NUL is refused",
		arguments: ["PING :a\r\nPING :b", "PING :a\nPING :b", "PING :a\rb", "PRIVMSG #a :b\0c"]
	)
	func negotiatedInboundRefusesSmuggledLines(message: String) {
		#expect(throws: WebSocketFramingError.invalidLine) {
			try Self.codec(.negotiated(.binary)).lines(fromMessage: Self.bytes(message))
		}
	}

	@Test("A negotiated line past the ceiling is refused")
	func negotiatedInboundCeiling() throws {
		let codec = Self.codec(.negotiated(.text))

		#expect(try codec.lines(fromMessage: Data(repeating: 0x61, count: Self.ceiling)).count == 1)
		#expect(throws: WebSocketFramingError.lineTooLong(completedLines: [])) {
			try codec.lines(fromMessage: Data(repeating: 0x61, count: Self.ceiling + 1))
		}
	}

	@Test("Without a subprotocol a message is split the way the stream transport splits a read")
	func unnegotiatedInboundSplits() throws {
		let lines = try Self.codec(.unnegotiated).lines(fromMessage: Self.bytes(":a 001 x :one\r\n\r\n:a 002 x :two\r\r\n:a 003 x :three"))

		#expect(lines == [":a 001 x :one", ":a 002 x :two", ":a 003 x :three"].map(Self.bytes))
	}

	@Test("Without a subprotocol a line past the ceiling is refused, after the lines before it")
	func unnegotiatedInboundCeiling() {
		var message = Self.bytes("first\r\n")
		message.append(Data(repeating: 0x61, count: Self.ceiling + 1))

		#expect(throws: WebSocketFramingError.lineTooLong(completedLines: [Self.bytes("first")])) {
			try Self.codec(.unnegotiated).lines(fromMessage: message)
		}
	}

	@Test(
		"Each queued line goes out as one message without its terminator",
		arguments: [WebSocketLineFraming.negotiated(.text), .negotiated(.binary), .unnegotiated]
	)
	func outboundStripsTerminators(framing: WebSocketLineFraming) {
		let messages = Self.codec(framing).messages(fromQueued: Self.bytes("NICK a\r\nUSER a 0 * :A\r\n\r\n"))
		let kind: WebSocketFrameKind = framing == .negotiated(.binary) ? .binary : .text

		#expect(messages == [
			WebSocketOutboundMessage(kind: kind, payload: Self.bytes("NICK a")),
			WebSocketOutboundMessage(kind: kind, payload: Self.bytes("USER a 0 * :A")),
		])
	}

	@Test("A text message is made valid UTF-8, and a binary one keeps its bytes")
	func outboundEncoding() {
		let latin1 = Data([0x50, 0x52, 0x49, 0x56, 0x4D, 0x53, 0x47, 0x20, 0x23, 0x61, 0x20, 0x3A, 0xE9, 0x0D, 0x0A])

		let text = Self.codec(.negotiated(.text)).messages(fromQueued: latin1)
		let binary = Self.codec(.negotiated(.binary)).messages(fromQueued: latin1)

		#expect(text.map(\.payload) == [Self.bytes("PRIVMSG #a :\u{FFFD}")])
		#expect(binary.map(\.payload) == [latin1.dropLast(2)])
	}
}
