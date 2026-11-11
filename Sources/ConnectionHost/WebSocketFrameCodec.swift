// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The frame opcodes RFC 6455 defines. Every other value is a protocol error.
nonisolated enum WebSocketOpcode: UInt8, Sendable {
	case continuation = 0x0
	case text = 0x1
	case binary = 0x2
	case close = 0x8
	case ping = 0x9
	case pong = 0xA

	var isControl: Bool {
		rawValue & 0x8 != 0
	}
}

/// The close status codes the host sends or tells apart.
nonisolated enum WebSocketCloseCode {
	static let normalClosure: UInt16 = 1000
	static let goingAway: UInt16 = 1001
	static let protocolError: UInt16 = 1002
	static let messageTooBig: UInt16 = 1009

	/// A control frame carries at most 125 bytes, two of them the code.
	static let maximumReasonLength = 123
}

/// Which data opcode a message arrived in, or is to be sent in.
nonisolated enum WebSocketFrameKind: Sendable, Equatable {
	case text
	case binary
}

/// What the server's frames amount to, in the order they arrived.
nonisolated enum WebSocketFrameEvent: Sendable, Equatable {
	/// A complete message, reassembled from its fragments.
	case message(Data, WebSocketFrameKind)
	case ping(Data)
	case pong
	/// The server began the closing handshake. `code` is nil when the frame
	/// carried no status.
	case close(code: UInt16?, reason: Data)
}

/** The server broke the framing. The events completed before the fault are
 still the server's, and the caller hands them on before failing the
 connection, the same stance ``LineFramingError`` takes. */
nonisolated struct WebSocketFrameError: Error, Sendable {
	nonisolated enum Kind: Error, Sendable, Equatable {
		/// A message grew past the ceiling.
		case messageTooBig
		/// Anything else RFC 6455 says a client must fail the connection for.
		case protocolViolation
	}

	let kind: Kind
	let completedEvents: [WebSocketFrameEvent]
}

/** Reads the server's side of an RFC 6455 connection out of a byte stream.

 Frames are found by offset and the consumed bytes are dropped once per read,
 so a read carrying thousands of short messages costs one pass. A message is
 limited to `maximumMessageSize` bytes across all of its fragments, and that
 is checked from the frame header, before its payload is buffered.

 Servers never mask, and a masked frame is a protocol error, as are reserved
 bits, unknown opcodes, a fragmented or oversized control frame, and a
 continuation that continues nothing. No extension is ever negotiated, so no
 reserved bit has a meaning. */
nonisolated struct WebSocketFrameDecoder: Sendable {
	private let maximumMessageSize: Int
	private var pending = Data()
	private var fragments: (kind: WebSocketFrameKind, payload: Data)?

	init(maximumMessageSize: Int) {
		precondition(maximumMessageSize >= 0)
		self.maximumMessageSize = maximumMessageSize
	}

	/// Whether part of a frame, or part of a fragmented message, is waiting
	/// for bytes that have not arrived.
	var hasPartialFrame: Bool {
		pending.isEmpty == false || fragments != nil
	}

	/// The events `data` completes, in order.
	mutating func events(appending data: Data) throws(WebSocketFrameError) -> [WebSocketFrameEvent] {
		pending.append(data)

		var events: [WebSocketFrameEvent] = []
		var offset = pending.startIndex

		do {
			while let frame = try frame(at: offset) {
				offset = frame.end

				if let event = try assemble(frame) {
					events.append(event)
				}
			}
		} catch {
			throw WebSocketFrameError(kind: error, completedEvents: events)
		}

		pending.removeSubrange(pending.startIndex ..< offset)

		return events
	}

	private nonisolated struct Frame {
		let isFinal: Bool
		let opcode: WebSocketOpcode
		let payload: Data
		let end: Data.Index
	}

	/// The frame starting at `offset`, or nil when it has not all arrived.
	private func frame(at offset: Data.Index) throws(WebSocketFrameError.Kind) -> Frame? {
		let available = pending.endIndex - offset

		guard available >= 2 else { return nil }

		let first = pending[offset]
		let second = pending[offset + 1]

		guard first & 0x70 == 0, second & 0x80 == 0, let opcode = WebSocketOpcode(rawValue: first & 0x0F) else {
			throw .protocolViolation
		}

		let isFinal = first & 0x80 != 0
		var headerLength = 2
		var length = UInt64(second & 0x7F)

		if length == 126 {
			guard available >= 4 else { return nil }

			length = UInt64(pending[offset + 2]) << 8 | UInt64(pending[offset + 3])
			headerLength = 4
		} else if length == 127 {
			guard available >= 10 else { return nil }

			length = (2 ..< 10).reduce(0) { $0 << 8 | UInt64(pending[offset + $1]) }
			headerLength = 10
		}

		if opcode.isControl {
			guard isFinal, length <= 125 else { throw .protocolViolation }
		} else {
			let buffered = opcode == .continuation ? fragments?.payload.count ?? 0 : 0

			guard length <= UInt64(maximumMessageSize - buffered) else { throw .messageTooBig }
		}

		let payloadLength = Int(length)

		guard available >= headerLength + payloadLength else { return nil }

		let payloadStart = offset + headerLength
		let end = payloadStart + payloadLength

		return Frame(isFinal: isFinal, opcode: opcode, payload: Data(pending[payloadStart ..< end]), end: end)
	}

	/// What `frame` adds up to, once its message is whole.
	private mutating func assemble(_ frame: Frame) throws(WebSocketFrameError.Kind) -> WebSocketFrameEvent? {
		switch frame.opcode {
		case .continuation:
			guard var message = fragments else { throw .protocolViolation }

			message.payload.append(frame.payload)

			guard frame.isFinal else {
				fragments = message

				return nil
			}

			fragments = nil

			return .message(message.payload, message.kind)
		case .text, .binary:
			guard fragments == nil else { throw .protocolViolation }

			let kind: WebSocketFrameKind = frame.opcode == .text ? .text : .binary

			guard frame.isFinal else {
				fragments = (kind, frame.payload)

				return nil
			}

			return .message(frame.payload, kind)
		case .close:
			return try Self.close(from: frame.payload)
		case .ping:
			return .ping(frame.payload)
		case .pong:
			return .pong
		}
	}

	private static func close(from payload: Data) throws(WebSocketFrameError.Kind) -> WebSocketFrameEvent {
		guard payload.isEmpty == false else {
			return .close(code: nil, reason: Data())
		}

		guard payload.count >= 2 else { throw .protocolViolation }

		let start = payload.startIndex
		let code = UInt16(payload[start]) << 8 | UInt16(payload[start + 1])

		return .close(code: code, reason: Data(payload[(start + 2)...]))
	}
}

/// Writes client frames, which RFC 6455 requires to be masked.
nonisolated enum WebSocketFrameEncoder {
	/// One unfragmented frame. `maskingKey` comes from a strong random source
	/// at the call site, a fresh one per frame.
	static func frame(_ opcode: WebSocketOpcode, payload: Data, maskingKey: UInt32) -> Data {
		var frame = Data(capacity: payload.count + 14)
		frame.append(0x80 | opcode.rawValue)

		switch payload.count {
		case 0 ..< 126:
			frame.append(0x80 | UInt8(payload.count))
		case 126 ... Int(UInt16.max):
			frame.append(0x80 | 126)
			frame.append(contentsOf: withUnsafeBytes(of: UInt16(payload.count).bigEndian, Array.init))
		default:
			frame.append(0x80 | 127)
			frame.append(contentsOf: withUnsafeBytes(of: UInt64(payload.count).bigEndian, Array.init))
		}

		let key = withUnsafeBytes(of: maskingKey.bigEndian, Array.init)
		frame.append(contentsOf: key)
		frame.append(contentsOf: payload.enumerated().map { index, byte in byte ^ key[index & 3] })

		return frame
	}

	/// A close frame with `code`, or with no status at all when it is nil.
	static func close(code: UInt16?, maskingKey: UInt32) -> Data {
		let payload = code.map { Data(withUnsafeBytes(of: $0.bigEndian, Array.init)) } ?? Data()

		return frame(.close, payload: payload, maskingKey: maskingKey)
	}
}
