// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CryptoKit
import Foundation

/** The server's half of RFC 6455, written independently of the host's codecs
 so that the loopback fixtures check the host against the specification rather
 than against itself. */
nonisolated enum LoopbackWebSocketFraming {
	/// One client frame as a server reads it.
	nonisolated struct ClientFrame: Equatable, Sendable {
		let opcode: UInt8
		let payload: Data
		let isFinal: Bool
		let isMasked: Bool
	}

	/// One server frame: unmasked unless a key is given.
	static func serverFrame(
		_ opcode: UInt8,
		_ payload: Data,
		final: Bool = true,
		reservedBits: UInt8 = 0,
		maskingKey: [UInt8]? = nil
	) -> Data {
		var frame = Data([(final ? 0x80 : 0) | reservedBits | opcode])
		let maskBit: UInt8 = maskingKey == nil ? 0 : 0x80

		switch payload.count {
		case 0 ..< 126:
			frame.append(maskBit | UInt8(payload.count))
		case 126 ... 0xFFFF:
			frame.append(contentsOf: [maskBit | 126, UInt8(payload.count >> 8), UInt8(payload.count & 0xFF)])
		default:
			frame.append(maskBit | 127)
			frame.append(contentsOf: (0 ..< 8).reversed().map { UInt8((payload.count >> ($0 * 8)) & 0xFF) })
		}

		guard let maskingKey else {
			frame.append(payload)

			return frame
		}

		frame.append(contentsOf: maskingKey)
		frame.append(contentsOf: payload.enumerated().map { $1 ^ maskingKey[$0 % 4] })

		return frame
	}

	static func text(_ line: String) -> Data {
		serverFrame(0x1, Data(line.utf8))
	}

	static func close(code: UInt16, reason: String = "") -> Data {
		serverFrame(0x8, Data([UInt8(code >> 8), UInt8(code & 0xFF)]) + Data(reason.utf8))
	}

	/// Takes every whole client frame off the front of `buffer`.
	static func clientFrames(from buffer: inout Data) -> [ClientFrame] {
		var frames: [ClientFrame] = []

		while true {
			let bytes = [UInt8](buffer.prefix(14))
			guard bytes.count >= 2 else { break }

			var length = Int(bytes[1] & 0x7F)
			var offset = 2
			if length == 126 {
				guard bytes.count >= 4 else { break }
				length = Int(bytes[2]) << 8 | Int(bytes[3])
				offset = 4
			} else if length == 127 {
				guard bytes.count >= 10 else { break }
				length = (2 ..< 10).reduce(0) { $0 << 8 | Int(bytes[$1]) }
				offset = 10
			}

			let isMasked = bytes[1] & 0x80 != 0
			let headerLength = offset + (isMasked ? 4 : 0)

			guard buffer.count >= headerLength + length else { break }

			let start = buffer.startIndex
			let key = isMasked ? [UInt8](buffer[(start + offset) ..< (start + offset + 4)]) : [0, 0, 0, 0]
			let masked = buffer[(start + headerLength) ..< (start + headerLength + length)]
			let payload = Data(masked.enumerated().map { $1 ^ key[$0 % 4] })

			frames.append(ClientFrame(opcode: bytes[0] & 0x0F, payload: payload, isFinal: bytes[0] & 0x80 != 0, isMasked: isMasked))
			buffer.removeFirst(headerLength + length)
		}

		return frames
	}

	/// The request head, once `buffer` holds all of it, and the bytes after it.
	static func requestHead(in buffer: Data) -> (head: String, remainder: Data)? {
		guard let end = buffer.range(of: Data("\r\n\r\n".utf8)),
		      let head = String(bytes: buffer[..<end.lowerBound], encoding: .utf8)
		else {
			return nil
		}

		return (head, Data(buffer[end.upperBound...]))
	}

	/// The value of header `name` in `head`, compared without case.
	static func header(_ name: String, in head: String) -> String? {
		head.components(separatedBy: "\r\n").dropFirst().first {
			$0.lowercased().hasPrefix(name.lowercased() + ":")
		}.map {
			String($0.drop { $0 != ":" }.dropFirst()).trimmingCharacters(in: .whitespaces)
		}
	}

	/// A 101 answer to `head`, choosing `subprotocol`.
	static func upgradeResponse(to head: String, subprotocol: String?) -> Data {
		let key = header("Sec-WebSocket-Key", in: head) ?? ""
		let accept = Data(Insecure.SHA1.hash(data: Data((key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11").utf8)))
			.base64EncodedString()

		var lines = [
			"HTTP/1.1 101 Switching Protocols",
			"Upgrade: websocket",
			"Connection: Upgrade",
			"Sec-WebSocket-Accept: \(accept)",
		]
		if let subprotocol {
			lines.append("Sec-WebSocket-Protocol: \(subprotocol)")
		}

		return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

	/// The subprotocols `head` offers, in order.
	static func offeredSubprotocols(in head: String) -> [String] {
		(header("Sec-WebSocket-Protocol", in: head) ?? "")
			.split(separator: ",")
			.map { $0.trimmingCharacters(in: .whitespaces) }
	}
}
