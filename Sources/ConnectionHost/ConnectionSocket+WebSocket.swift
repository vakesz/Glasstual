// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The WebSocket layer of one connection, from its upgrade on.

 It runs over the same TCP or TLS connection a stream does, so the TLS
 validator, legacy-suite retry, client identity, proxy and deadlines below it
 are the stream's, unchanged. Network.framework's own WebSocket protocol is
 not used: it discards every message still buffered when a close frame
 arrives, which would lose the lines a server sends just before it closes,
 and it reports a refused upgrade as a stalled connection with no status. */
struct WebSocketSession {
	var decoder: WebSocketFrameDecoder
	let lines: WebSocketLineCodec

	/** A negotiated message is one line, so the line ceiling is the message
	 ceiling. Without a subprotocol a message may batch lines, each still held
	 to the ceiling, so the message is held to one read instead. */
	init(subprotocol: WebSocketSubprotocol?) {
		let framing: WebSocketLineFraming = switch subprotocol {
		case .text: .negotiated(.text)
		case .binary: .negotiated(.binary)
		case nil: .unnegotiated
		}

		decoder = WebSocketFrameDecoder(
			maximumMessageSize: subprotocol == nil
				? ConnectionSocket.maximumDataLength
				: ConnectionSocket.maximumBufferedLineLength
		)
		lines = WebSocketLineCodec(framing: framing, maximumLineLength: ConnectionSocket.maximumBufferedLineLength)
	}

	/// The frames one queued write goes out as, each with a fresh mask.
	static func frames(for data: Data, framedBy lines: WebSocketLineCodec) -> Data {
		lines.messages(fromQueued: data).reduce(into: Data()) { frames, message in
			frames.append(WebSocketFrameEncoder.frame(
				message.kind == .text ? .text : .binary,
				payload: message.payload,
				maskingKey: .random(in: .min ... .max)
			))
		}
	}
}

/// Why the server's side of a WebSocket ended before the connection did.
enum WebSocketEnding {
	case closedByPeer(code: UInt16?, reason: Data)
	case protocolViolation
	case messageTooBig
}

extension ConnectionSocket {
	/// How long a close frame may take to go out before the connection ends
	/// without it.
	static let webSocketCloseTimeout = Duration.seconds(2)

	// MARK: - Reading

	/** Upgrades the transport, then reads frames until the connection ends.

	 One read can carry many frames, and the lines they hold go to the
	 application as one batch with the same acknowledgement the stream
	 transport waits for, so a busy server is slowed by TCP the same way. */
	func readWebSocket(
		from connection: TransportConnection,
		options: WebSocketTransportOptions,
		generation: Int
	) async throws {
		let upgrade = try await upgrade(connection, options: options)

		guard onUpgraded(to: upgrade.accepted.subprotocol, generation: generation) else { return }

		var data = upgrade.accepted.remainder
		var isComplete = upgrade.ended

		while connected, disconnecting == false {
			if data.isEmpty, isComplete == false {
				(data, isComplete) = try await connection.receive(atMost: Self.maximumDataLength)
				try Task.checkCancellation()
			}

			if let ending = try await deliverFrames(in: data, over: connection) {
				try await end(with: ending, over: connection)

				return
			}

			data = Data()

			if isComplete {
				/* A connection dropped without a close frame, the same as a stream
				 that ends inside a line. */
				if webSocket?.decoder.hasPartialFrame == true {
					throw ConnectionError.socket(error: NSError(domain: NSPOSIXErrorDomain, code: Int(EPROTO)))
				}

				events.yield(.closedReadStream)

				return
			}
		}
	}

	/** Sends the upgrade request and reads the response.

	 The request is the first operation on the connection, so sending it is
	 what establishes the transport: DNS, the proxy, the TLS handshake and its
	 trust prompt all happen inside that send, under the connect deadline. */
	private func upgrade(
		_ connection: TransportConnection,
		options: WebSocketTransportOptions
	) async throws -> (accepted: WebSocketUpgrade, ended: Bool) {
		var handshake = WebSocketHandshake(offering: options.subprotocols.map(\.rawValue))

		guard let request = handshake.request(
			host: config.serverAddress,
			port: config.serverPort,
			secure: config.connectionPrefersSecuredConnection,
			path: options.path
		) else {
			throw ConnectionError.other(message: String(localized: .ConnectionErrors.webSocketAddressInvalid))
		}

		try await connection.send(request)
		try Task.checkCancellation()
		config.diagnostics?.record(.transportReady)

		while true {
			let (content, isComplete) = try await connection.receive(atMost: Self.maximumDataLength)
			try Task.checkCancellation()

			do {
				if let upgrade = try handshake.consume(content) {
					return (upgrade, isComplete)
				}
			} catch {
				throw ConnectionError.webSocketHandshake(error)
			}

			if isComplete {
				throw ConnectionError.webSocketHandshake(.invalidResponse)
			}
		}
	}

	/// The upgrade completed: from here the connection is connected, and the
	/// application learns how its lines are framed.
	func onUpgraded(to subprotocol: String?, generation: Int) -> Bool {
		guard generation == dialGeneration, connecting, disconnecting == false else { return false }

		/* The handshake refuses a subprotocol that was not offered, so a name
		 is always one of these. */
		let negotiated = subprotocol.flatMap(WebSocketSubprotocol.init(rawValue:))

		webSocket = WebSocketSession(subprotocol: negotiated)

		onConnect()
		events.yield(.negotiatedSubprotocol(negotiated?.rawValue))
		onSecured()

		return true
	}

	/** Hands on the lines `data` completes, answers pings, and reports the
	 ending it carried, if any.

	 Lines that precede a fault or a close frame are the server's, and are
	 delivered before the connection acts on what followed them. */
	private func deliverFrames(in data: Data, over connection: TransportConnection) async throws -> WebSocketEnding? {
		guard data.isEmpty == false, var session = webSocket else { return nil }

		var ending: WebSocketEnding?
		let frameEvents: [WebSocketFrameEvent]

		do {
			frameEvents = try session.decoder.events(appending: data)
		} catch {
			frameEvents = error.completedEvents
			ending = error.kind == .messageTooBig ? .messageTooBig : .protocolViolation
		}

		webSocket = session

		var lines: [Data] = []

		eventLoop: for event in frameEvents {
			switch event {
			case let .message(payload, _):
				do {
					try lines.append(contentsOf: session.lines.lines(fromMessage: payload))
				} catch .invalidLine {
					ending = .protocolViolation

					break eventLoop
				} catch let .lineTooLong(completedLines) {
					lines.append(contentsOf: completedLines)
					ending = .messageTooBig

					break eventLoop
				}
			case let .ping(payload):
				try await connection.send(WebSocketFrameEncoder.frame(
					.pong,
					payload: payload,
					maskingKey: .random(in: .min ... .max)
				))
			case .pong:
				continue
			case let .close(code, reason):
				ending = .closedByPeer(code: code, reason: reason)

				break eventLoop
			}
		}

		if lines.isEmpty == false, disconnecting == false {
			try await deliver(lines)
		}

		return ending
	}

	/// Finishes the closing handshake the server started, or fails the
	/// connection for the fault it committed.
	private func end(with ending: WebSocketEnding, over connection: TransportConnection) async throws {
		switch ending {
		case let .closedByPeer(code, reason):
			/* RFC 6455 answers a close with a close that carries the same status. */
			await sendCloseFrame(code: code, over: connection)

			/* The owner's own close is under way, and that close has no error. */
			guard disconnecting == false else { return }

			guard let code, code != WebSocketCloseCode.normalClosure, code != WebSocketCloseCode.goingAway else {
				events.yield(.closedReadStream)

				return
			}

			throw ConnectionError.webSocketClosed(code: code, reason: reason)
		case .protocolViolation:
			await sendCloseFrame(code: WebSocketCloseCode.protocolError, over: connection)

			throw ConnectionError.other(message: String(localized: .ConnectionErrors.webSocketProtocolViolation))
		case .messageTooBig:
			await sendCloseFrame(code: WebSocketCloseCode.messageTooBig, over: connection)

			throw ConnectionError.other(message: String(localized: .ConnectionErrors.peerLineTooLong))
		}
	}

	// MARK: - Closing

	/** Ends an open WebSocket the owner closed: a normal-closure frame, then
	 the dial. The dial ends when the frame has gone out or the deadline
	 passes, whichever is first, so a stalled peer cannot hold a close open. */
	func closeWebSocketGracefully(over connection: TransportConnection) {
		let dial = dialTask

		gracefulCloseTask = Task { [weak self] in
			await self?.sendCloseFrame(code: WebSocketCloseCode.normalClosure, over: connection)

			dial?.cancel()
		}
	}

	/** Sends this connection's one close frame, waiting no longer than
	 ``webSocketCloseTimeout`` for it to go out.

	 Neither the send nor the deadline is awaited directly: a send that does
	 not answer cancellation must not keep the caller waiting past the deadline. */
	func sendCloseFrame(code: UInt16?, over connection: TransportConnection) async {
		guard webSocketCloseSent == false else { return }

		webSocketCloseSent = true

		let frame = WebSocketFrameEncoder.close(code: code, maskingKey: .random(in: .min ... .max))
		let (finished, finish) = AsyncStream<Void>.makeStream()

		let sending = Task {
			try? await connection.send(frame)
			finish.finish()
		}

		let deadline = Task {
			try? await Task.sleep(for: Self.webSocketCloseTimeout, clock: .continuous)
			finish.finish()
		}

		for await _ in finished {}

		sending.cancel()
		deadline.cancel()
	}
}
