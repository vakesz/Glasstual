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

/// What a ``DCCChatConnection`` reports to whoever is driving it.
///
/// The sequence is always zero or one `listening`, then `connected`, then any
/// number of `line`, then exactly one `closed`. A cancelled session ends the
/// stream without a `closed`.
public nonisolated enum DCCChatEvent: Sendable { // nonisolated: value
	case listening(port: UInt16)
	case connected(peerAddress: String?)
	/// One line as it arrived, without its newline. Still in the peer's
	/// encoding: only the client knows which one that is.
	case line(Data)
	/// `nil` when the peer closed cleanly.
	case closed(DCCTransferError?)
}

/// One DCC CHAT session: the socket and the line framing, owned by one actor.
///
/// The file-transfer side of DCC is ``DCCTransfer``, and the two share the
/// Network.framework helpers in `DCCTransfer+Network.swift`. What differs is
/// what travels: a chat carries newline-terminated lines in both directions for
/// as long as the peer stays, so there is no length to count down and no
/// acknowledgement protocol — the session ends when one side closes.
///
/// Nothing is shared: the actor creates its own typed Network.framework
/// connection or listener and reports through ``events``.
public actor DCCChatConnection {
	/// How the two ends find each other.
	public nonisolated enum Endpoint: Sendable { // nonisolated: value
		/// Dial the peer, which is already listening.
		case connect(host: String, port: UInt16, interfaceName: String?, timeout: Duration?)
		/// Listen for the peer on the first port in the range that binds.
		case listen(portRange: ClosedRange<UInt16>)
	}

	public nonisolated struct Configuration: Sendable { // nonisolated: value
		public var endpoint: Endpoint
		/// A peer that never sends a newline must not be able to grow the
		/// buffer without bound; the session fails once it passes this.
		public var maximumLineLength: Int
		/// How long a single write may take before the session fails.
		public var sendTimeout: Duration?

		public init(
			endpoint: Endpoint,
			maximumLineLength: Int = 16 * 1024,
			sendTimeout: Duration? = nil
		) {
			self.endpoint = endpoint
			self.maximumLineLength = maximumLineLength
			self.sendTimeout = sendTimeout
		}
	}

	/// What the session is doing, in order. Finishes when the session does.
	public nonisolated let events: AsyncStream<DCCChatEvent> // nonisolated: let

	private let configuration: Configuration
	private let eventContinuation: AsyncStream<DCCChatEvent>.Continuation

	private var runTask: Task<Void, Never>?
	private var connection: NetworkConnection<TCP>?
	private var listener: NetworkListener<TCP>?
	private var listenerTask: Task<Void, Never>?
	/// Set once the connection is carrying bytes, which is when ``send(_:)``
	/// has somewhere to write.
	private var readyConnection: NetworkConnection<TCP>?
	private var lineBuffer = Data()
	private var isCancelled = false
	private var hasFinished = false

	public init(configuration: Configuration) {
		let (stream, continuation) = AsyncStream<DCCChatEvent>.makeStream()
		events = stream
		eventContinuation = continuation
		self.configuration = configuration
	}

	deinit {
		eventContinuation.finish()
	}

	/// Begins the session. Calling it twice does nothing the second time.
	public func start() {
		guard runTask == nil, isCancelled == false else {
			return
		}

		runTask = Task { [self] in
			await run()
		}
	}

	/// Stops the session and ends ``events`` without a `closed`.
	public func close() {
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
	public func send(_ payload: Data) async throws {
		try await write(payload + Data([0x0D, 0x0A]))
	}

	/// Writes bytes exactly as given. ``send(_:)`` is this plus the framing.
	func write(_ payload: Data) async throws {
		guard let connection = readyConnection, isCancelled == false, hasFinished == false else {
			throw DCCTransferError.closedByPeer
		}

		try await DCCTransfer.withTimeout(configuration.sendTimeout, failingWith: .writeTimeout) {
			try await DCCTransfer.send(payload, over: connection)
		}
	}

	// MARK: - Running

	private func run() async {
		do {
			let connection = try await establishConnection()
			readyConnection = connection
			emit(.connected(peerAddress: connection.remoteEndpoint.flatMap(DCCTransfer.host(of:))))

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

		let parameters = DCCTransfer.parameters(interfaceName: interfaceName, connectTimeout: timeout)
		let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: networkPort)
		let connection = NetworkConnection<TCP>(
			to: endpoint,
			using: .parameters(initialParameters: parameters) { TCP() }
		)
		self.connection = connection

		try await DCCTransfer.withTimeout(timeout, failingWith: .connectTimeout) {
			/* Typed Network connections establish on first I/O. Empty data puts no
			 bytes on the chat stream but makes the connected event truthful. */
			try await connection.send(Data())
		}

		return connection
	}

	private func acceptConnection(portRange: ClosedRange<UInt16>) async throws -> NetworkConnection<TCP> {
		let listening = try await DCCTransfer.startListener(portRange: portRange)
		listener = listening.listener
		listenerTask = listening.task

		emit(.listening(port: listening.port))

		for await candidate in listening.connections {
			/* One offer serves one conversation. Leaving the port open past the
			 first accept only gives somebody else a window to reach it. */
			listenerTask?.cancel()
			listenerTask = nil
			listener = nil

			connection = candidate
			try await candidate.send(Data())

			return candidate
		}

		throw DCCTransferError.closedByPeer
	}

	// MARK: - Reading

	private func readLines(over connection: NetworkConnection<TCP>) async throws {
		while true {
			try Task.checkCancellation()

			let (payload, isComplete) = try await DCCTransfer.receive(on: connection)

			if let payload, payload.isEmpty == false {
				try consume(payload)
			}

			if isComplete {
				/* The peer hung up. Whatever it left without a newline is not a
				 line, so it is dropped, which is what the old socket did. */
				return
			}
		}
	}

	/// Splits `payload` into lines, emitting each one.
	///
	/// The framing is a bare line feed: a peer that sends CRLF leaves the CR at
	/// the end of the line, and the client strips it when it decodes.
	private func consume(_ payload: Data) throws {
		lineBuffer.append(payload)

		while let newline = lineBuffer.firstIndex(of: 0x0A) {
			let line = Data(lineBuffer[lineBuffer.startIndex ..< newline])
			lineBuffer.removeSubrange(lineBuffer.startIndex ... newline)

			emit(.line(line))
		}

		guard lineBuffer.count <= configuration.maximumLineLength else {
			throw DCCTransferError.badParameter
		}
	}
}
