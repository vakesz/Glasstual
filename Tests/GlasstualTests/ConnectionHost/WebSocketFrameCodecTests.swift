// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Testing

/** The server half of RFC 6455 framing as the host reads it, and the client
 half as it writes it. Server frames come from the loopback fixture's own
 framing, independent of the encoder under test. */
@Suite("WebSocket frame codec")
nonisolated struct WebSocketFrameCodecTests {
	static func serverFrame(
		_ opcode: UInt8,
		_ payload: Data,
		final: Bool = true,
		reservedBits: UInt8 = 0,
		maskingKey: [UInt8]? = nil
	) -> Data {
		LoopbackWebSocketFraming.serverFrame(opcode, payload, final: final, reservedBits: reservedBits, maskingKey: maskingKey)
	}

	static func text(_ string: String) -> Data {
		serverFrame(0x1, Data(string.utf8))
	}

	// MARK: - Decoding

	@Test("Text and binary messages decode in order from one read")
	func messagesDecodeInOrder() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 16 * 1024)
		var read = Self.text("PING :a")
		read.append(Self.serverFrame(0x2, Data([0xE9, 0x41])))

		let events = try decoder.events(appending: read)

		#expect(events == [.message(Data("PING :a".utf8), .text), .message(Data([0xE9, 0x41]), .binary)])
		#expect(decoder.hasPartialFrame == false)
	}

	@Test("A frame that arrives a byte at a time decodes once it is whole")
	func frameSplitAcrossReads() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 16 * 1024)
		let frame = Self.serverFrame(0x1, Data(repeating: 0x61, count: 300))

		for byte in frame.dropLast() {
			#expect(try decoder.events(appending: Data([byte])).isEmpty)
			#expect(decoder.hasPartialFrame)
		}

		let events = try decoder.events(appending: Data([#require(frame.last)]))

		#expect(events == [.message(Data(repeating: 0x61, count: 300), .text)])
		#expect(decoder.hasPartialFrame == false)
	}

	@Test("Fragments are reassembled, with a ping between them answered on its own")
	func fragmentsAreReassembled() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 16 * 1024)
		var read = Self.serverFrame(0x1, Data("frag".utf8), final: false)
		read.append(Self.serverFrame(0x9, Data("p".utf8)))
		read.append(Self.serverFrame(0x0, Data("men".utf8), final: false))

		#expect(try decoder.events(appending: read) == [.ping(Data("p".utf8))])
		#expect(decoder.hasPartialFrame)

		let events = try decoder.events(appending: Self.serverFrame(0x0, Data("t".utf8)))

		#expect(events == [.message(Data("fragment".utf8), .text)])
		#expect(decoder.hasPartialFrame == false)
	}

	@Test("Sixteen- and sixty-four-bit lengths decode", arguments: [126, 0xFFFF, 0x10000])
	func extendedLengths(length: Int) throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 0x20000)
		let payload = Data(repeating: 0x62, count: length)

		#expect(try decoder.events(appending: Self.serverFrame(0x2, payload)) == [.message(payload, .binary)])
	}

	@Test("Close frames carry their code and reason, or neither")
	func closeFrames() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 1024)
		var read = Self.serverFrame(0x8, Data([0x0F, 0xA0]) + Data("bye".utf8))
		read.append(Self.serverFrame(0x8, Data()))

		let events = try decoder.events(appending: read)

		#expect(events == [.close(code: 4000, reason: Data("bye".utf8)), .close(code: nil, reason: Data())])
	}

	@Test("Pings carry their payload and pongs are reported")
	func controlFrames() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 1024)
		var read = Self.serverFrame(0x9, Data("token".utf8))
		read.append(Self.serverFrame(0xA, Data("x".utf8)))

		#expect(try decoder.events(appending: read) == [.ping(Data("token".utf8)), .pong])
	}

	static let violations: [(String, Data)] = [
		("a masked server frame", serverFrame(0x1, Data("a".utf8), maskingKey: [1, 2, 3, 4])),
		("a reserved bit", serverFrame(0x1, Data("a".utf8), reservedBits: 0x40)),
		("an undefined opcode", serverFrame(0x3, Data("a".utf8))),
		("a control frame over 125 bytes", serverFrame(0x9, Data(repeating: 0, count: 126))),
		("a fragmented control frame", serverFrame(0x9, Data(), final: false)),
		("a continuation of nothing", serverFrame(0x0, Data("a".utf8))),
		(
			"a new message inside a fragmented one",
			serverFrame(0x1, Data("a".utf8), final: false) + serverFrame(0x1, Data("b".utf8))
		),
		("a one-byte close payload", serverFrame(0x8, Data([0x03]))),
	]

	@Test("Framing a client must refuse is a protocol violation", arguments: violations.indices)
	func protocolViolations(index: Int) {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 1024)
		let (name, frame) = Self.violations[index]

		do {
			_ = try decoder.events(appending: frame)
			Issue.record("\(name) was accepted")
		} catch {
			#expect(error.kind == .protocolViolation, "\(name)")
		}
	}

	@Test("An oversized message is refused from its header, before its payload arrives")
	func oversizedMessageIsRefusedFromItsHeader() {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 16 * 1024)
		let header = Self.serverFrame(0x1, Data(repeating: 0x41, count: 16 * 1024 + 1)).prefix(4)

		do {
			_ = try decoder.events(appending: Data(header))
			Issue.record("the header of an oversized message was accepted")
		} catch {
			#expect(error.kind == .messageTooBig)
		}
	}

	@Test("A message at the ceiling is accepted")
	func messageAtTheCeilingIsAccepted() throws {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 16 * 1024)
		let payload = Data(repeating: 0x41, count: 16 * 1024)

		#expect(try decoder.events(appending: Self.serverFrame(0x1, payload)) == [.message(payload, .text)])
	}

	@Test("Fragments that add up past the ceiling are refused")
	func fragmentsAddingUpPastTheCeilingAreRefused() {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 100)
		var read = Self.serverFrame(0x1, Data(repeating: 0x41, count: 60), final: false)
		read.append(Self.serverFrame(0x0, Data(repeating: 0x41, count: 41)))

		do {
			_ = try decoder.events(appending: read)
			Issue.record("fragments past the ceiling were accepted")
		} catch {
			#expect(error.kind == .messageTooBig)
		}
	}

	@Test("Events completed before a fault are handed back with it")
	func eventsBeforeAFaultSurvive() {
		var decoder = WebSocketFrameDecoder(maximumMessageSize: 1024)
		var read = Self.text("one")
		read.append(Self.text("two"))
		read.append(Self.serverFrame(0x3, Data()))
		read.append(Self.text("three"))

		do {
			_ = try decoder.events(appending: read)
			Issue.record("an undefined opcode was accepted")
		} catch {
			#expect(error.completedEvents == [.message(Data("one".utf8), .text), .message(Data("two".utf8), .text)])
		}
	}

	// MARK: - Encoding

	/// Undoes what a server undoes: reads the header and unmasks the payload.
	static func unmask(_ frame: Data) throws -> (first: UInt8, payload: Data) {
		let bytes = [UInt8](frame)
		try #require(bytes.count >= 6)
		#expect(bytes[1] & 0x80 != 0, "a client frame went out unmasked")

		var length = Int(bytes[1] & 0x7F)
		var offset = 2
		if length == 126 {
			length = Int(bytes[2]) << 8 | Int(bytes[3])
			offset = 4
		} else if length == 127 {
			length = (2 ..< 10).reduce(0) { $0 << 8 | Int(bytes[$1]) }
			offset = 10
		}

		let key = Array(bytes[offset ..< offset + 4])
		let masked = bytes[(offset + 4)...]
		try #require(masked.count == length)

		return (bytes[0], Data(masked.enumerated().map { $1 ^ key[$0 % 4] }))
	}

	@Test("Client frames are final, masked with the given key, and unmask to the payload", arguments: [0, 125, 126, 0x10000])
	func clientFramesAreMasked(length: Int) throws {
		let payload = Data((0 ..< length).map { UInt8($0 & 0xFF) })
		let frame = WebSocketFrameEncoder.frame(.binary, payload: payload, maskingKey: 0xA1B2_C3D4)

		let (first, unmasked) = try Self.unmask(frame)

		#expect(first == 0x82)
		#expect(unmasked == payload)
		if length > 0 {
			#expect(frame.suffix(length) != payload, "the payload went out in the clear")
		}
	}

	@Test("A close frame carries its code, or nothing when there is none")
	func closeFramesCarryTheirCode() throws {
		let (first, payload) = try Self.unmask(WebSocketFrameEncoder.close(code: 1000, maskingKey: 7))
		#expect(first == 0x88)
		#expect(payload == Data([0x03, 0xE8]))

		let (_, empty) = try Self.unmask(WebSocketFrameEncoder.close(code: nil, maskingKey: 7))
		#expect(empty.isEmpty)
	}
}
