// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network

/// What a ``DirectChatSocket`` reports to whoever is driving it.
///
/// The sequence is always zero or one `listening`, then `connected`, then any
/// number of `lines`, then exactly one `closed`. A cancelled session ends the
/// stream without a `closed`.
nonisolated enum DirectChatEvent: Sendable {
	case listening(port: UInt16)
	case connected
	/// The complete lines in one bounded read, without their newlines, in the
	/// peer's encoding. Finish the acknowledgement after consuming the batch;
	/// the connection waits for it before reading again.
	case lines([Data], acknowledged: AsyncStream<Void>.Continuation)
	/// `nil` when the peer closed cleanly.
	case closed(DCCTransferError?)
}

/// One DCC CHAT session: the socket and the line framing, owned by one actor.
///
/// The file-transfer side of DCC is ``DCCTransfer``, and the two reach their
/// peer through the same ``DCCConnectionEndpoint``. What differs is what
/// travels: a chat carries newline-terminated lines in both directions for as
/// long as the peer stays, so there is no length to count down and no
/// acknowledgement protocol — the session ends when one side closes.
///
/// Nothing is shared: the actor creates its own typed Network.framework
/// connection or listener and reports through ``events``.
actor DirectChatSocket {
	nonisolated struct Config: Sendable {
		var endpoint: DCCEndpoint
		/// A peer that never sends a newline must not be able to grow the
		/// buffer without bound; the session fails once it passes this.
		var maximumLineLength: Int
		/// How long a single write may take before the session fails.
		var sendTimeout: Duration?
		/// Only a connection from this address is accepted while listening.
		/// Empty accepts any, which is what is left when the offer named no
		/// address — every `DCC CHAT` offer this session listens for, since the
		/// peer's own hostmask says where they reached the *server* from rather
		/// than where they will dial out from.
		var expectedPeerAddress: String
		/// The whole window a listening session has to bind a port and take the
		/// peer's connection, not a budget for each step in turn.
		var acceptanceTimeout: Duration?

		init(
			endpoint: DCCEndpoint,
			maximumLineLength: Int = 16 * 1024,
			sendTimeout: Duration? = nil,
			expectedPeerAddress: String = "",
			acceptanceTimeout: Duration? = nil
		) {
			self.endpoint = endpoint
			self.maximumLineLength = maximumLineLength
			self.sendTimeout = sendTimeout
			self.expectedPeerAddress = expectedPeerAddress
			self.acceptanceTimeout = acceptanceTimeout
		}
	}

	/// What the session is doing, in order. Finishes when the session does.
	nonisolated let events: AsyncStream<DirectChatEvent>

	private let config: Config
	private let eventContinuation: AsyncStream<DirectChatEvent>.Continuation

	private var runTask: Task<Void, Never>?
	/// Set once the connection is carrying bytes, which is when ``send(_:)``
	/// has somewhere to write.
	private var readyConnection: NetworkConnection<TCP>?
	private var framer: LineFramer
	private var isCancelled = false
	private var hasFinished = false

	init(config: Config) {
		let (stream, continuation) = AsyncStream<DirectChatEvent>.makeStream()
		events = stream
		eventContinuation = continuation
		self.config = config
		/* DCC CHAT frames on a bare line feed: a peer that sends CRLF leaves the
		 CR at the end of the line, and the session strips it when it decodes. */
		framer = LineFramer(
			maximumLineLength: config.maximumLineLength,
			stripsCarriageReturns: false,
			dropsEmptyLines: false
		)
	}

	deinit {
		eventContinuation.finish()
	}

	/// Begins the session. Calling it twice does nothing the second time.
	func start() {
		guard runTask == nil, isCancelled == false else {
			return
		}

		runTask = Task { [self] in
			await run()
		}
	}

	/// Stops the session and ends ``events`` without a `closed`.
	func close() {
		guard isCancelled == false else {
			return
		}

		isCancelled = true
		runTask?.cancel()
		runTask = nil
		tearDown()
		hasFinished = true
		eventContinuation.finish()
	}

	/// Writes one line, appending the CRLF the protocol frames with.
	///
	/// `payload` is already in the peer's encoding, and must not contain a
	/// newline of its own: the caller splits, because only it knows how the
	/// text was meant to be divided.
	func send(_ payload: Data) async throws {
		try await write(payload + Data([0x0D, 0x0A]))
	}

	/// Writes bytes exactly as given. ``send(_:)`` is this plus the framing.
	func write(_ payload: Data) async throws {
		guard let connection = readyConnection, isCancelled == false, hasFinished == false else {
			throw DCCTransferError.closedByPeer
		}

		try await DCCTransport.withTimeout(config.sendTimeout, failingWith: .stalled) {
			try await connection.send(payload)
		}
	}

	// MARK: - Running

	private func run() async {
		do {
			let connection = try await establishConnection()
			readyConnection = connection
			emit(.connected)

			try await readLines(over: connection)

			tearDown()
			finish(with: .closed(nil))
		} catch {
			tearDown()

			guard isCancelled == false, error is CancellationError == false else {
				hasFinished = true
				eventContinuation.finish()

				return
			}

			finish(with: .closed(DCCTransferError(mapping: error)))
		}
	}

	private func emit(_ event: DirectChatEvent) {
		guard hasFinished == false else {
			return
		}

		eventContinuation.yield(event)
	}

	private func finish(with event: DirectChatEvent) {
		guard hasFinished == false else {
			return
		}

		hasFinished = true
		eventContinuation.yield(event)
		eventContinuation.finish()
	}

	private func tearDown() {
		readyConnection = nil
	}

	// MARK: - Establishing the connection

	private func establishConnection() async throws -> NetworkConnection<TCP> {
		switch config.endpoint {
		case let .connect(host, port, interfaceName, timeout):
			return try await DCCConnectionEndpoint.connect(
				toHost: host,
				port: port,
				interfaceName: interfaceName,
				timeout: timeout
			)
		case let .listen(portRange):
			let deadline = config.acceptanceTimeout.map { ContinuousClock.now + $0 }
			let session = try await DCCConnectionEndpoint.bind(portRange: portRange, deadline: deadline)

			emit(.listening(port: session.port))

			/* The transfer side pins the peer address too. Nothing negotiates an
			 address for a chat, so the expectation is normally empty and every
			 caller gets in; a caller that configures one is held to it. */
			return try await DCCConnectionEndpoint.accept(
				on: session,
				expectedPeerAddress: config.expectedPeerAddress,
				sendTimeout: config.sendTimeout,
				deadline: deadline,
				log: DirectConnectionLog.chat
			)
		}
	}

	// MARK: - Reading

	private func readLines(over connection: NetworkConnection<TCP>) async throws {
		while true {
			try Task.checkCancellation()

			let (payload, isComplete) = try await DCCConnectionEndpoint.receive(on: connection)

			if let payload, payload.isEmpty == false {
				let lines: [Data]
				do {
					lines = try framer.lines(appending: payload)
				} catch {
					/* A peer that grows a line past the ceiling is not speaking
					 DCC CHAT; whatever it completed before that goes with it. */
					throw DCCTransferError.badParameter
				}

				if !lines.isEmpty {
					let (drained, acknowledgement) = AsyncStream<Void>.makeStream()
					emit(.lines(lines, acknowledged: acknowledgement))
					// Admit another bounded read only after the consumer handles this one.
					for await _ in drained {}
					try Task.checkCancellation()
				}
			}

			if isComplete {
				/* The peer hung up. Whatever it left without a newline is not a
				 line, so it is dropped, which is what the old socket did. */
				return
			}
		}
	}
}
