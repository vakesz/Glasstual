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

/// Why a DCC transfer stopped before it delivered the whole file.
public nonisolated enum DCCTransferError: Error, Equatable, Sendable { // nonisolated: value
	case connectTimeout
	case writeTimeout
	case closedByPeer
	case noOpenPort
	case badParameter
	/// The only connection to reach the listening port came from somewhere
	/// other than the peer the transfer was negotiated with.
	case rejectedPeerAddress
	/// The peer pushed more bytes than the transfer announced.
	case oversizedTransfer
	case fileUnreadable
	case fileUnwritable
	case storageFull
	case network(String)
}

/// What a ``DCCTransfer`` reports to whoever is driving it.
///
/// The sequence is always zero or one `listening`, then `connected`, then any
/// number of `progress`, then exactly one of `finished`/`failed`. A cancelled
/// transfer ends the stream without a terminal event.
public nonisolated enum DCCTransferEvent: Sendable { // nonisolated: value
	case listening(port: UInt16)
	case connected(peerAddress: String?)
	case progress(processedBytes: UInt64)
	case completion(DCCTransfer.Completion)
	case finished
	case failed(DCCTransferError)
}

/// One DCC file transfer: the socket, the file and the DCC acknowledgement
/// protocol, all owned by a single actor.
///
/// Nothing about a transfer is shared: the actor creates its own typed
/// Network.framework connection or listener, opens its own `FileHandle`, and
/// reports what it is doing through ``events``. The transport's async methods
/// run inside the transfer task, so the actor is the one place the transfer's
/// state lives.
public actor DCCTransfer {
	public nonisolated enum Completion: Sendable { // nonisolated: value
		case received
		case acknowledged
		/// All bytes were submitted and the ACKless peer closed cleanly. This
		/// does not claim that the peer persisted or acknowledged the file.
		case unacknowledged
	}

	/// Which end of the transfer this actor is.
	public nonisolated enum Role: Sendable { // nonisolated: value
		case sender
		case receiver
	}

	/// How the two ends find each other.
	public nonisolated enum Endpoint: Sendable { // nonisolated: value
		/// Dial the peer, which is already listening.
		case connect(host: String, port: UInt16, interfaceName: String?, timeout: Duration?)
		/// Listen for the peer on the first port in the range that binds.
		case listen(portRange: ClosedRange<UInt16>)
	}

	public nonisolated struct Configuration: Sendable { // nonisolated: value
		public var role: Role
		public var endpoint: Endpoint
		/// The file to read from, or the file to write into. The caller
		/// reserves it: the actor only ever uses the descriptor it is handed,
		/// so nothing here can open a second file under the same name.
		public var file: DCCTransferFile
		/// How many bytes the transfer announced. The receiver refuses to
		/// store more than this and the sender stops after it.
		public var fileSize: UInt64
		/// Where in the file to resume, for a DCC `RESUME`.
		public var resumeOffset: UInt64
		/// Only a connection from this address is accepted. Empty accepts any,
		/// which is what a plain `DCC SEND` has to do: we listen, and the peer
		/// announces itself by arriving.
		public var expectedPeerAddress: String
		/// How long a single write may take before the transfer fails.
		public var sendTimeout: Duration?
		public var inactivityTimeout: Duration?
		/// The whole window a listening transfer has to bind a port and take
		/// the peer's connection, not a budget for each step in turn.
		public var acceptanceTimeout: Duration?

		public init(
			role: Role,
			endpoint: Endpoint,
			file: DCCTransferFile,
			fileSize: UInt64,
			resumeOffset: UInt64 = 0,
			expectedPeerAddress: String = "",
			sendTimeout: Duration? = .seconds(30),
			inactivityTimeout: Duration? = .seconds(30),
			acceptanceTimeout: Duration? = .seconds(120)
		) {
			self.role = role
			self.endpoint = endpoint
			self.file = file
			self.fileSize = fileSize
			self.resumeOffset = resumeOffset
			self.expectedPeerAddress = expectedPeerAddress
			self.sendTimeout = sendTimeout
			self.inactivityTimeout = inactivityTimeout
			self.acceptanceTimeout = acceptanceTimeout
		}
	}

	/// Read buffer, and the ceiling on a single connection receive.
	static let bufferSize = 64 * 1024
	/// The transfer paces itself to this many bytes a second so a local
	/// transfer cannot starve the rest of the app.
	static let rateLimitBytesPerSecond: UInt64 = 10 * 1024 * 1024
	/// How long the sender waits for the receiver to close once the last block
	/// has gone out.
	static let gracefulCloseTimeout: Duration = .seconds(30)

	static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "DCCTransfer"
	)

	/// The transfer's progress, in order. Finishes when the transfer does.
	public nonisolated let events: AsyncStream<DCCTransferEvent> // nonisolated: let

	private var configuration: Configuration
	private let eventContinuation: AsyncStream<DCCTransferEvent>.Continuation

	private var runTask: Task<Void, Never>?
	private var connection: NetworkConnection<TCP>?
	private var listener: NetworkListener<TCP>?
	private var listenerTask: Task<Void, Never>?
	private var file: DCCTransferFile?
	private var bytesStarted = false
	private var submittedBytes: UInt64 = 0
	private var isCancelled = false
	private var hasFinished = false

	public init(configuration: Configuration) {
		let (stream, continuation) = AsyncStream<DCCTransferEvent>.makeStream()
		events = stream
		eventContinuation = continuation
		self.configuration = configuration
	}

	deinit {
		eventContinuation.finish()
	}

	/// Begins the transfer. Calling it twice does nothing the second time.
	public func start() {
		guard runTask == nil, isCancelled == false else {
			return
		}

		runTask = Task { [self] in
			await run()
		}
	}

	/// Stops the transfer and ends ``events`` without a terminal event.
	public func cancel() async {
		let running = runTask
		if isCancelled == false {
			isCancelled = true
			running?.cancel()
			tearDown()
			hasFinished = true
			eventContinuation.finish()
		}

		// Every caller must observe quiescence before releasing the file lease,
		// including a second cancellation while the first is still draining.
		await running?.value
		runTask = nil
	}

	/// RESUME changes the pending byte offset, never the listening socket.
	public func commitResumeOffset(_ offset: UInt64) -> Bool {
		guard !Task.isCancelled, !isCancelled, !hasFinished, !bytesStarted,
		      offset > 0, offset <= configuration.fileSize else { return false }
		configuration.resumeOffset = offset
		return true
	}

	// MARK: - Running

	private func run() async {
		do {
			guard configuration.resumeOffset <= configuration.fileSize else { throw DCCTransferError.badParameter }
			file = configuration.file
			let connection = try await establishConnection()
			try Task.checkCancellation()
			bytesStarted = true
			submittedBytes = configuration.resumeOffset
			emit(.connected(peerAddress: connection.remoteEndpoint.flatMap(Self.host(of:))))

			switch configuration.role {
			case .sender:
				try await sendFile(over: connection)
			case .receiver:
				try await receiveFile(over: connection)
				emit(.completion(.received))
			}

			tearDown()
			finish(with: .finished)
		} catch {
			tearDown()

			guard isCancelled == false, error is CancellationError == false else {
				hasFinished = true
				eventContinuation.finish()
				return
			}

			finish(with: .failed(Self.transferError(from: error)))
		}
	}

	private func emit(_ event: DCCTransferEvent) {
		guard hasFinished == false else {
			return
		}

		eventContinuation.yield(event)
	}

	private func finish(with event: DCCTransferEvent) {
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

		connection = nil

		file = nil
	}

	private nonisolated static func transferError(from error: Error) -> DCCTransferError { // nonisolated: pure
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

		let parameters = Self.parameters(interfaceName: interfaceName, connectTimeout: timeout)
		let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: networkPort)
		let connection = NetworkConnection<TCP>(
			to: endpoint,
			using: .parameters(initialParameters: parameters) { TCP() }
		)
		self.connection = connection

		try await Self.withTimeout(timeout, failingWith: .connectTimeout) {
			/* Typed Network connections establish on first I/O. Empty data puts no
			 bytes on the DCC stream but makes the connected event truthful. */
			try await connection.send(Data())
		}

		return connection
	}

	private func acceptConnection(portRange: ClosedRange<UInt16>) async throws -> NetworkConnection<TCP> {
		/* Binding a port and waiting for the peer share one window. Applying
		 the timeout to each in turn gave a slow bind twice what was asked. */
		let deadline = configuration.acceptanceTimeout.map { ContinuousClock.now + $0 }

		let listening = try await Self.withDeadline(deadline, failingWith: .connectTimeout) {
			try await Self.startListener(portRange: portRange)
		}
		listener = listening.listener
		listenerTask = listening.task

		emit(.listening(port: listening.port))

		let expectedPeerAddress = configuration.expectedPeerAddress
		let sendTimeout = configuration.sendTimeout
		return try await Self.withDeadline(deadline, failingWith: .connectTimeout) { [self] in
			var rejectedAPeer = false
			for await candidate in listening.connections {
				try Task.checkCancellation()
				guard Self.connection(candidate, isFrom: expectedPeerAddress) else {
					Self.logger.error(
						"Rejected a DCC connection from an address other than the one the transfer was offered from"
					)
					rejectedAPeer = true
					await reject(candidate)
					continue
				}

				/* One listener serves one transfer. Leaving the port open past the
				 first accept only gives somebody else a window to reach it. */
				await accepted(candidate)
				try await Self.withTimeout(sendTimeout, failingWith: .connectTimeout) {
					try await candidate.send(Data())
				}

				return candidate
			}

			if rejectedAPeer {
				throw DCCTransferError.rejectedPeerAddress
			}

			throw DCCTransferError.closedByPeer
		}
	}

	private func accepted(_ candidate: NetworkConnection<TCP>) {
		listenerTask?.cancel()
		listenerTask = nil
		listener = nil
		connection = candidate
	}

	// MARK: - Sending

	private nonisolated enum SendResult: Sendable { // nonisolated: value
		case sent
		case peer(Completion)
	}

	private func sendFile(over connection: NetworkConnection<TCP>) async throws {
		guard let file else { throw DCCTransferError.fileUnreadable }
		try await withThrowingTaskGroup(of: SendResult.self) { group in
			defer { group.cancelAll() }
			group.addTask { try await .peer(self.readAcknowledgements(over: connection)) }
			group.addTask {
				try await self.sendBlocks(from: file, over: connection)
				return .sent
			}
			var sent = false
			var completion: Completion?
			while let result = try await group.next() {
				switch result {
				case .sent:
					sent = true
					group.addTask {
						try await Task.sleep(for: Self.gracefulCloseTimeout)
						throw DCCTransferError.writeTimeout
					}
				case let .peer(result):
					completion = result
				}
				if sent, let completion {
					emit(.completion(completion))
					return
				}
			}

			/* Both sides of the group finished without agreeing on a verdict,
			 which only happens if the connection went away underneath them. */
			throw DCCTransferError.closedByPeer
		}
	}

	private func readAcknowledgements(over connection: NetworkConnection<TCP>) async throws -> Completion {
		var acknowledgements = DCCAcknowledgements(
			offset: configuration.resumeOffset,
			offeredSize: configuration.fileSize
		)
		while true {
			let (payload, complete) = try await receive(on: connection)
			if let payload {
				try acknowledgements.append(payload)
			}
			guard acknowledgements.acknowledged <= submittedBytes else { throw DCCTransferError.badParameter }
			if acknowledgements.isComplete {
				return .acknowledged
			}
			if complete {
				guard submittedBytes == configuration.fileSize, !acknowledgements.hasBytes else {
					throw DCCTransferError.closedByPeer
				}
				return .unacknowledged
			}
		}
	}

	private func sendBlocks(from file: DCCTransferFile, over connection: NetworkConnection<TCP>) async throws {
		var processedBytes = configuration.resumeOffset
		var windowStart = ContinuousClock.now
		var windowBytes: UInt64 = 0

		while processedBytes < configuration.fileSize {
			try Task.checkCancellation()

			let count = Int(min(UInt64(Self.bufferSize), configuration.fileSize - processedBytes))
			let chunk = try await file.read(at: processedBytes, count: count)
			try Task.checkCancellation()
			submittedBytes = processedBytes + UInt64(chunk.count)

			try await Self.withTimeout(configuration.sendTimeout, failingWith: .writeTimeout) {
				try await connection.send(chunk)
			}

			processedBytes += UInt64(chunk.count)
			emit(.progress(processedBytes: processedBytes))

			windowBytes += UInt64(chunk.count)

			if windowBytes >= Self.rateLimitBytesPerSecond {
				try await Self.pause(untilASecondHasPassedSince: windowStart)
				windowStart = ContinuousClock.now
				windowBytes = 0
			}
		}
	}

	private nonisolated static func pause( // nonisolated: pure
		untilASecondHasPassedSince start: ContinuousClock.Instant
	) async throws { // nonisolated: pure
		let elapsed = ContinuousClock.now - start

		guard elapsed < .seconds(1) else {
			return
		}

		try await Task.sleep(for: .seconds(1) - elapsed)
	}

	// MARK: - Receiving

	private func receiveFile(over connection: NetworkConnection<TCP>) async throws {
		guard let file, try await file.size() == configuration.resumeOffset else {
			throw DCCTransferError.fileUnwritable
		}

		var processedBytes = configuration.resumeOffset
		if processedBytes == configuration.fileSize {
			let acknowledgement = Self.acknowledgement(for: processedBytes)
			try await Self.withTimeout(configuration.sendTimeout, failingWith: .writeTimeout) {
				try await connection.send(acknowledgement)
			}
		}

		while processedBytes < configuration.fileSize {
			try Task.checkCancellation()

			let (payload, isComplete) = try await Self.withTimeout(
				configuration.inactivityTimeout,
				failingWith: .connectTimeout
			) { [self] in
				try await receive(on: connection)
			}

			if let payload, payload.isEmpty == false {
				let remaining = configuration.fileSize - processedBytes
				let overshot = UInt64(payload.count) > remaining
				let accepted = overshot ? Data(payload.prefix(Int(remaining))) : payload
				try await file.write(accepted, at: processedBytes)
				processedBytes += UInt64(accepted.count)

				/* The DCC acknowledgement is the receiver's running total, so
				 it goes out before the transfer is torn down for the excess. */
				let acknowledgement = Self.acknowledgement(for: processedBytes)
				try await Self.withTimeout(configuration.sendTimeout, failingWith: .writeTimeout) {
					try await connection.send(acknowledgement)
				}
				emit(.progress(processedBytes: processedBytes))

				if overshot {
					throw DCCTransferError.oversizedTransfer
				}
			}

			if isComplete, processedBytes < configuration.fileSize {
				throw DCCTransferError.closedByPeer
			}
		}
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
	 on a connection this transfer owns, not a pure function of its inputs, so
	 its isolation follows the socket. */
	private func receive(on connection: NetworkConnection<TCP>) async throws -> (Data?, Bool) {
		let message = try await connection.receive(atLeast: 1, atMost: Self.bufferSize)

		return (message.content, message.metadata.endOfStream)
	}

	/// DCC acknowledges with the receiver's running total as a big-endian
	/// 32-bit count, which wraps for files past 4 GB.
	nonisolated static func acknowledgement(for byteCount: UInt64) -> Data { // nonisolated: pure
		let bytes = UInt32(truncatingIfNeeded: byteCount)

		return Data([
			UInt8(truncatingIfNeeded: bytes >> 24),
			UInt8(truncatingIfNeeded: bytes >> 16),
			UInt8(truncatingIfNeeded: bytes >> 8),
			UInt8(truncatingIfNeeded: bytes),
		])
	}
}
