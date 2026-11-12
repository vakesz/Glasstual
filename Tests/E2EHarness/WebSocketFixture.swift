import CryptoKit
import Foundation

/** The server's half of RFC 6455 for the loopback peer, so IRC lines travel
 the way the IRCv3 WebSocket specification carries them: one line per text
 message under `text.ircv3.net`.

 It checks what the client has to get right: the request target the scenario
 seeded, the version, a key, an offer that includes `text.ircv3.net`, and
 masked, unfragmented text frames. Anything else is a violation; no header or
 payload is ever printed. */
struct WebSocketFixture {
	static let path = "/e2e-socket"
	static let subprotocol = "text.ircv3.net"
	private static let acceptGUID = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

	/// What one read came to.
	struct Output {
		/// Bytes to write back before any line is answered: the upgrade
		/// response, a pong or the close frame.
		var reply = Data()
		var lines: [String] = []
	}

	private(set) var upgraded = false
	private(set) var closeReceived = false
	private var buffer = Data()

	/// Whether nothing is left half-read.
	var isDrained: Bool {
		buffer.isEmpty
	}

	/// One IRC line as an unmasked text frame, the way a server sends it.
	static func frame(_ line: String) -> Data {
		frame(opcode: 0x1, payload: Data(line.utf8))
	}

	private static func frame(opcode: UInt8, payload: Data) -> Data {
		var frame = Data([0x80 | opcode])
		switch payload.count {
		case ..<126:
			frame.append(UInt8(payload.count))
		case ..<65536:
			frame.append(126)
			frame.append(contentsOf: [UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
		default:
			frame.append(127)
			frame.append(contentsOf: (0 ..< 8).reversed().map { UInt8((payload.count >> ($0 * 8)) & 0xFF) })
		}
		frame.append(payload)
		return frame
	}

	static func acceptValue(forKey key: String) -> String {
		Data(Insecure.SHA1.hash(data: Data((key + acceptGUID).utf8))).base64EncodedString()
	}

	mutating func receive(_ data: Data) throws -> Output {
		guard closeReceived == false else { throw HarnessFailure.assertion("WebSocket data after the close frame") }
		buffer.append(data)
		guard buffer.count <= 65536 else { throw HarnessFailure.assertion("Oversized WebSocket input") }
		var output = Output()
		if upgraded == false {
			guard let end = buffer.range(of: Data("\r\n\r\n".utf8)) else { return output }
			guard let head = String(data: buffer[..<end.lowerBound], encoding: .utf8) else {
				throw HarnessFailure.assertion("Non-UTF8 WebSocket upgrade request")
			}
			buffer.removeSubrange(..<end.upperBound)
			output.reply = try Self.upgradeResponse(to: head)
			upgraded = true
		}
		while let frame = try nextFrame() {
			switch frame.opcode {
			case 0x1:
				guard let line = String(data: frame.payload, encoding: .utf8),
				      line.contains(where: { $0 == "\r" || $0 == "\n" }) == false
				else { throw HarnessFailure.assertion("A WebSocket text message was not one IRC line") }
				output.lines.append(line)
			case 0x8:
				closeReceived = true
				// The close is answered with the status it carried.
				output.reply.append(Self.frame(opcode: 0x8, payload: frame.payload.prefix(2)))
				guard buffer.isEmpty else { throw HarnessFailure.assertion("WebSocket data after the close frame") }
				return output
			case 0x9:
				output.reply.append(Self.frame(opcode: 0xA, payload: frame.payload))
			case 0xA:
				break
			default:
				throw HarnessFailure.assertion("Unexpected WebSocket opcode")
			}
		}
		return output
	}

	/// The 101 response, once `head` is the upgrade this fixture expects.
	private static func upgradeResponse(to head: String) throws -> Data {
		var lines = head.components(separatedBy: "\r\n")
		let request = lines.removeFirst()
		var headers: [String: String] = [:]
		for line in lines {
			guard let colon = line.firstIndex(of: ":") else {
				throw HarnessFailure.assertion("Malformed WebSocket upgrade header")
			}
			headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
		}
		let offered = (headers["sec-websocket-protocol"] ?? "").split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
		guard request == "GET \(path) HTTP/1.1",
		      headers["upgrade"]?.lowercased() == "websocket",
		      headers["connection"]?.lowercased().contains("upgrade") == true,
		      headers["sec-websocket-version"] == "13",
		      let key = headers["sec-websocket-key"], Data(base64Encoded: key)?.count == 16,
		      headers["host"]?.hasPrefix("127.0.0.1:") == true,
		      offered.contains(subprotocol),
		      headers["origin"] == nil, headers["cookie"] == nil, headers["authorization"] == nil,
		      headers["sec-websocket-extensions"] == nil
		else { throw HarnessFailure.assertion("The WebSocket upgrade request was not the expected one; payload withheld") }
		let response = [
			"HTTP/1.1 101 Switching Protocols",
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Accept: \(acceptValue(forKey: key))",
			"Sec-WebSocket-Protocol: \(subprotocol)",
		]
		return Data((response.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

	/// The next complete client frame, unmasked, or `nil` while it is partial.
	private mutating func nextFrame() throws -> (opcode: UInt8, payload: Data)? {
		let bytes = [UInt8](buffer.prefix(14))
		guard bytes.count >= 2 else { return nil }
		// Final, no extension bits, and masked: what a client has to send.
		guard bytes[0] & 0xF0 == 0x80, bytes[1] & 0x80 != 0 else {
			throw HarnessFailure.assertion("A client WebSocket frame was fragmented, extended or unmasked")
		}
		var length = Int(bytes[1] & 0x7F)
		var header = 2
		if length == 126 {
			guard bytes.count >= 4 else { return nil }
			length = Int(bytes[2]) << 8 | Int(bytes[3])
			header = 4
		} else if length == 127 {
			throw HarnessFailure.assertion("Oversized WebSocket frame")
		}
		guard buffer.count >= header + 4 + length else { return nil }
		let frame = [UInt8](buffer.prefix(header + 4 + length))
		buffer.removeFirst(header + 4 + length)
		let mask = frame[header ..< header + 4]
		let payload = frame[(header + 4)...].enumerated().map { $1 ^ mask[mask.startIndex + $0 % 4] }
		return (bytes[0] & 0x0F, Data(payload))
	}
}
