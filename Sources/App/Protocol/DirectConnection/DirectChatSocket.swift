/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
import Network
import os

/// What a ``DirectChatSocket`` reports to whoever is driving it.
///
/// The sequence is always zero or one `listening`, then `connected`, then any
/// number of `lines`, then exactly one `closed`. A cancelled session ends the
/// stream without a `closed`.
nonisolated enum DCCChatEvent: Sendable { // nonisolated: value
	case listening(port: UInt16)
	case connected
	/// The complete lines in one bounded read, without their newlines, in the
	/// peer's encoding. Finish the acknowledgement after consuming the batch;
	/// the connection waits for it before reading again.
	case lines([Data], acknowledged: AsyncStream<Void>.Continuation)
	/// `nil` when the peer closed cleanly.
	case closed(DCCTransferError?)
}

private nonisolated let directChatConnectionLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "DCCChatConnection"
)

/// One DCC CHAT session: the socket and the line framing, owned by one actor.
///
/// The file-transfer side of DCC is ``DCCTransfer``, and the two share the
/// Network.framework helpers in ``DCCSocket``. What differs is
/// what travels: a chat carries newline-terminated lines in both directions for
/// as long as the peer stays, so there is no length to count down and no
/// acknowledgement protocol — the session ends when one side closes.
///
/// Nothing is shared: the actor creates its own typed Network.framework
/// connection or listener and reports through ``events``.
actor DirectChatSocket {
	/// How the two ends find each other.
	nonisolated enum Endpoint: Sendable { // nonisolated: value
		/// Dial the peer, which is already listening.
		case connect(host: String, port: UInt16, interfaceName: String?, timeout: Duration?)
		/// Listen for the peer on the first port in the range that binds.
		case listen(portRange: ClosedRange<UInt16>)
	}

	nonisolated struct Configuration: Sendable { // nonisolated: value
		var endpoint: Endpoint
		/// A peer that never sends a newline must not be able to grow the
		/// buffer without bound; the session fails once it passes this.
		var maximumLineLength: Int
		/// How long a single write may take before the session fails.
		var sendTimeout: Duration?
		/// Only a connection from this address is accepted while listening.
		/// Empty accepts any, which is what is left when the offer named no
		/// address — every `DCC CHAT` offer this client listens for, since the
		/// peer's own hostmask says where they reached the *server* from rather
		/// than where they will dial out from.
		var expectedPeerAddress: String

		init(
			endpoint: Endpoint,
			maximumLineLength: Int = 16 * 1024,
			sendTimeout: Duration? = nil,
			expectedPeerAddress: String = ""
		) {
			self.endpoint = endpoint
			self.maximumLineLength = maximumLineLength
			self.sendTimeout = sendTimeout
			self.expectedPeerAddress = expectedPeerAddress
		}
	}

	/// What the session is doing, in order. Finishes when the session does.
	nonisolated let events: AsyncStream<DCCChatEvent> // nonisolated: let

	private let configuration: Configuration
	private let eventContinuation: AsyncStream<DCCChatEvent>.Continuation

	private var runTask: Task<Void, Never>?
	private var connection: NetworkConnection<TCP>?
	private var listener: NetworkListener<TCP>?
	private var listenerTask: Task<Void, Never>?
	/// Set once the connection is carrying bytes, which is when ``send(_:)``
	/// has somewhere to write.
	private var readyConnection: NetworkConnection<TCP>?
	private var framer: DCCChatLineFramer
	private var isCancelled = false
	private var hasFinished = false

	init(configuration: Configuration) {
		let (stream, continuation) = AsyncStream<DCCChatEvent>.makeStream()
		events = stream
		eventContinuation = continuation
		self.configuration = configuration
		framer = DCCChatLineFramer(maximumLineLength: configuration.maximumLineLength)
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

		try await DCCSocket.withTimeout(configuration.sendTimeout, failingWith: .stalled) {
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

			finish(with: .closed(Self.chatError(from: error)))
		}
	}

	private func emit(_ event: DCCChatEvent) {
		guard hasFinished == false else {
			return
		}

		eventContinuation.yield(event)
	}

	private func finish(with event: DCCChatEvent) {
		guard hasFinished == false else {
			return
		}

		hasFinished = true
		eventContinuation.yield(event)
		eventContinuation.finish()
	}

	private func tearDown() {
		listenerTask?.cancel()
		listenerTask = nil
		listener = nil

		readyConnection = nil
		connection = nil
	}

	private nonisolated static func chatError(from error: Error) -> DCCTransferError { // nonisolated: pure
		if let error = error as? DCCTransferError {
			return error
		}

		return .network(error.localizedDescription)
	}

	// MARK: - Establishing the connection

	private func establishConnection() async throws -> NetworkConnection<TCP> {
		switch configuration.endpoint {
		case let .connect(host, port, interfaceName, timeout):
			try await connect(toHost: host, port: port, interfaceName: interfaceName, timeout: timeout)
		case let .listen(portRange):
			try await acceptConnection(portRange: portRange)
		}
	}

	private func connect(
		toHost host: String,
		port: UInt16,
		interfaceName: String?,
		timeout: Duration?
	) async throws -> NetworkConnection<TCP> {
		guard host.isEmpty == false, let networkPort = NWEndpoint.Port(rawValue: port) else {
			throw DCCTransferError.badParameter
		}

		let parameters = DCCSocket.parameters(interfaceName: interfaceName, connectTimeout: timeout)
		let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: networkPort)
		let connection = NetworkConnection<TCP>(
			to: endpoint,
			using: .parameters(initialParameters: parameters) { TCP() }
		)
		self.connection = connection

		try await DCCSocket.withTimeout(timeout, failingWith: .connectTimeout) {
			/* Typed Network connections establish on first I/O. Empty data puts no
			 bytes on the chat stream but makes the connected event truthful. */
			try await connection.send(Data())
		}

		return connection
	}

	private func acceptConnection(portRange: ClosedRange<UInt16>) async throws -> NetworkConnection<TCP> {
		let listening = try await DCCSocket.startListener(portRange: portRange)
		listener = listening.listener
		listenerTask = listening.task

		emit(.listening(port: listening.port))

		let expectedPeerAddress = configuration.expectedPeerAddress
		var rejectedAPeer = false

		for await candidate in listening.connections {
			try Task.checkCancellation()

			/* The transfer side checks this too. Nothing negotiates an address
			 for a chat, so the expectation is normally empty and every caller
			 gets in; a caller that configures one is held to it. */
			guard DCCSocket.connection(candidate, isFrom: expectedPeerAddress) else {
				directChatConnectionLogger.error(
					"Rejected a DCC CHAT connection from an address other than the one the offer named"
				)
				rejectedAPeer = true
				await reject(candidate)
				continue
			}

			/* One offer serves one conversation. Leaving the port open past the
			 first accept only gives somebody else a window to reach it. */
			listenerTask?.cancel()
			listenerTask = nil
			listener = nil

			connection = candidate
			try await candidate.send(Data())

			return candidate
		}

		if rejectedAPeer {
			throw DCCTransferError.rejectedPeerAddress
		}

		throw DCCTransferError.closedByPeer
	}

	// MARK: - Reading and writing

	/** Refuses one inbound connection.

	 Half-closing tells whoever dialled that the port is not going to answer,
	 rather than leaving them holding a socket that never carries anything, and
	 releasing the last reference lets the stack finish tearing it down. */
	private func reject(_ connection: NetworkConnection<TCP>) async {
		try? await connection.send(Data(), endOfStream: true)
	}

	/** Reads whatever the peer has sent, and reports whether the peer is done.

	 An instance method rather than a shared `nonisolated static` one: it is I/O
	 on a connection this session owns, not a pure function of its inputs, so
	 its isolation follows the socket. */
	private func receive(on connection: NetworkConnection<TCP>) async throws -> (Data?, Bool) {
		let message = try await connection.receive(atLeast: 1, atMost: DCCSocket.bufferSize)

		return (message.content, message.metadata.endOfStream)
	}

	private func readLines(over connection: NetworkConnection<TCP>) async throws {
		while true {
			try Task.checkCancellation()

			let (payload, isComplete) = try await receive(on: connection)

			if let payload, payload.isEmpty == false {
				let lines = try framer.lines(appending: payload)
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

/** Cuts a DCC CHAT byte stream into lines.

 The framing is a bare line feed: a peer that sends CRLF leaves the CR at the
 end of the line, and the client strips it when it decodes.

 A read is scanned once, from where the last one stopped, and the buffer is
 compacted once per read. Removing each line from the front of the buffer as it
 was found moved everything behind it every time, which made a read carrying
 many short lines cost the square of its length. */
nonisolated struct DCCChatLineFramer { // nonisolated: value
	/// A peer that never sends a newline must not be able to grow the buffer
	/// without bound; framing fails once the unterminated part passes this.
	let maximumLineLength: Int

	/// Bytes after the last line feed, waiting for the rest of their line.
	private var pending = Data()

	init(maximumLineLength: Int) {
		self.maximumLineLength = maximumLineLength
	}

	/// The lines `payload` completes, in order.
	mutating func lines(appending payload: Data) throws -> [Data] {
		let scanFrom = pending.count
		pending.append(payload)

		var lines: [Data] = []
		var lineStart = pending.startIndex
		var searchStart = pending.startIndex + scanFrom
		while let newline = pending[searchStart...].firstIndex(of: 0x0A) {
			lines.append(Data(pending[lineStart ..< newline]))
			lineStart = pending.index(after: newline)
			searchStart = lineStart
		}
		pending.removeSubrange(pending.startIndex ..< lineStart)

		guard pending.count <= maximumLineLength else {
			throw DCCTransferError.badParameter
		}

		return lines
	}
}
