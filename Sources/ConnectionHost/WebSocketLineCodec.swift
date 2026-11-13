// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// Text a server or a session produced, made fit for a text frame or a sentence.
nonisolated enum WebSocketText {
	/** `bytes` as UTF-8, with U+FFFD in place of each invalid sequence: the
	 replacement the IRCv3 WebSocket specification allows a server, applied by
	 the client to text it cannot otherwise send or show. */
	static func repairingUTF8(_ bytes: some Sequence<UInt8>) -> String {
		var scalars = String.UnicodeScalarView()
		var input = bytes.makeIterator()
		var decoder = UTF8()

		while true {
			switch decoder.decode(&input) {
			case let .scalarValue(scalar):
				scalars.append(scalar)
			case .error:
				scalars.append("\u{FFFD}")
			case .emptyInput:
				return String(scalars)
			}
		}
	}
}

/// How a WebSocket connection carries lines, decided by the upgrade.
nonisolated enum WebSocketLineFraming: Sendable, Equatable {
	/// The server chose an IRCv3 subprotocol: one line per message, in text
	/// frames for `text.ircv3.net` and binary frames for `binary.ircv3.net`.
	case negotiated(WebSocketFrameKind)
	/** The server chose none, which the specification leaves to the
	 implementation. Inbound messages may carry several CRLF-terminated lines;
	 outbound lines go one per text message, without a terminator. */
	case unnegotiated
}

/// A message broke the framing rules.
nonisolated enum WebSocketFramingError: Error, Sendable, Equatable {
	/// A negotiated message carried a CR, LF or NUL inside its line.
	case invalidLine
	/// A line passed the ceiling. The lines before it in the same message are
	/// the server's and are delivered first.
	case lineTooLong(completedLines: [Data])
}

/// One message to send, already in the frame kind the framing calls for.
nonisolated struct WebSocketOutboundMessage: Sendable, Equatable {
	let kind: WebSocketFrameKind
	let payload: Data
}

/** The line policy for one WebSocket connection, in both directions.

 Inbound, the IRCv3 rule is one line per message with no terminator. A
 trailing CR or LF is tolerated and removed. Under a negotiated subprotocol a
 CR, LF or NUL anywhere else means the server tried to carry more than one
 line, or a line the stream transport could never have delivered, in a single
 message, and that fails the connection. Without one, a message is split the
 way the stream transport splits its reads.

 Outbound, the application queues CRLF-terminated lines. Each becomes one
 message without its terminator. A text message's payload is made valid UTF-8,
 with U+FFFD for each invalid sequence, because a text frame that is not
 UTF-8 is one the server must reject. */
nonisolated struct WebSocketLineCodec: Sendable {
	let framing: WebSocketLineFraming
	private let maximumLineLength: Int

	init(framing: WebSocketLineFraming, maximumLineLength: Int) {
		self.framing = framing
		self.maximumLineLength = maximumLineLength
	}

	/// The lines one complete message carries.
	func lines(fromMessage payload: Data) throws(WebSocketFramingError) -> [Data] {
		guard case .negotiated = framing else {
			return try splitLines(payload)
		}

		var line = payload[...]
		while let last = line.last, last == 0x0A || last == 0x0D {
			line = line.dropLast()
		}

		guard line.contains(where: { $0 == 0x00 || $0 == 0x0A || $0 == 0x0D }) == false else {
			throw .invalidLine
		}

		guard line.count <= maximumLineLength else {
			throw .lineTooLong(completedLines: [])
		}

		return line.isEmpty ? [] : [Data(line)]
	}

	/// What the stream transport would have made of `payload`, with the end of
	/// the message ending its last line.
	private func splitLines(_ payload: Data) throws(WebSocketFramingError) -> [Data] {
		var framer = LineFramer(
			maximumLineLength: maximumLineLength,
			stripsCarriageReturns: true,
			dropsEmptyLines: true
		)

		var terminated = payload
		if terminated.last != 0x0A {
			terminated.append(0x0A)
		}

		do {
			return try framer.lines(appending: terminated)
		} catch {
			throw .lineTooLong(completedLines: error.completedLines)
		}
	}

	/** The client frames one queued write goes out as, each with a fresh mask.

	 None once this side's close frame has been sent: RFC 6455 §5.5.1 allows
	 no data frame after it. */
	func frames(fromQueued data: Data, afterClose closeSent: Bool) -> Data {
		guard closeSent == false else { return Data() }

		return messages(fromQueued: data).reduce(into: Data()) { frames, message in
			frames.append(WebSocketFrameEncoder.frame(
				message.kind == .text ? .text : .binary,
				payload: message.payload,
				maskingKey: .random(in: .min ... .max)
			))
		}
	}

	/// The messages one queued write becomes, in order.
	func messages(fromQueued data: Data) -> [WebSocketOutboundMessage] {
		let kind: WebSocketFrameKind = framing == .negotiated(.binary) ? .binary : .text

		return data.split(separator: 0x0A, omittingEmptySubsequences: true).compactMap { line in
			var trimmed = line
			while trimmed.last == 0x0D {
				trimmed = trimmed.dropLast()
			}

			guard trimmed.isEmpty == false else { return nil }

			let payload = kind == .text ? Data(WebSocketText.repairingUTF8(trimmed).utf8) : Data(trimmed)

			return WebSocketOutboundMessage(kind: kind, payload: payload)
		}
	}
}
