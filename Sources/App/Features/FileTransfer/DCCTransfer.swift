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
	case finished
	case failed(DCCTransferError)
}

/// One DCC file transfer: the socket, the file and the DCC acknowledgement
/// protocol, all owned by a single actor.
///
/// Nothing about a transfer is shared: the actor creates its own `NWConnection`
/// or `NWListener`, opens its own `FileHandle`, and reports what it is doing
/// through ``events``. Network.framework's callbacks never touch actor state —
/// they only resume a continuation or yield into an `AsyncStream` — so the
/// actor is the one place the transfer's state lives.
public actor DCCTransfer {
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
		/// The file to read from, or the file to write into. The caller picks
		/// the name: the actor only opens what it is handed.
		public var filePath: String
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

		public init(
			role: Role,
			endpoint: Endpoint,
			filePath: String,
			fileSize: UInt64,
			resumeOffset: UInt64 = 0,
			expectedPeerAddress: String = "",
			sendTimeout: Duration? = nil
		) {
			self.role = role
			self.endpoint = endpoint
			self.filePath = filePath
			self.fileSize = fileSize
			self.resumeOffset = resumeOffset
			self.expectedPeerAddress = expectedPeerAddress
			self.sendTimeout = sendTimeout
		}
	}

	/// Read buffer, and the ceiling on a single `NWConnection.receive`.
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

	/** Network.framework insists on a dispatch queue for its callbacks. Those
	 callbacks only resume a continuation or yield into an `AsyncStream`, both
	 of which are thread-safe, so the shared concurrent queue is enough: the
	 actor, not the queue, is what serialises the transfer. */
	static let callbackQueue = DispatchQueue.global(qos: .utility)

	/// The transfer's progress, in order. Finishes when the transfer does.
	public nonisolated let events: AsyncStream<DCCTransferEvent> // nonisolated: let

	private let configuration: Configuration
	private let eventContinuation: AsyncStream<DCCTransferEvent>.Continuation

	private var runTask: Task<Void, Never>?
	private var connection: NWConnection?
	private var listener: NWListener?
	private var incomingContinuation: AsyncStream<NWConnection>.Continuation?
	private var fileHandle: FileHandle?
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
	public func cancel() {
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

	// MARK: - Running

	private func run() async {
		do {
			let connection = try await establishConnection()
			emit(.connected(peerAddress: Self.host(of: connection.endpoint)))

			switch configuration.role {
			case .sender:
				try await sendFile(over: connection)
			case .receiver:
				try await receiveFile(over: connection)
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
		incomingContinuation?.finish()
		incomingContinuation = nil

		listener?.cancel()
		listener = nil

		connection?.cancel()
		connection = nil

		closeFile()
	}

	private func closeFile() {
		guard let fileHandle else {
			return
		}

		do {
			try fileHandle.close()
		} catch {
			Self.logger.error(
				"Failed to close the transfer file: \(error.localizedDescription, privacy: .public)"
			)
		}

		self.fileHandle = nil
	}

	private nonisolated static func transferError(from error: Error) -> DCCTransferError { // nonisolated: pure
		if let error = error as? DCCTransferError {
			return error
		}

		return .network(error.localizedDescription)
	}

	// MARK: - Establishing the connection

	private func establishConnection() async throws -> NWConnection {
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
	) async throws -> NWConnection {
		guard host.isEmpty == false, let networkPort = NWEndpoint.Port(rawValue: port) else {
			throw DCCTransferError.badParameter
		}

		let parameters = Self.parameters(interfaceName: interfaceName, connectTimeout: timeout)
		let connection = NWConnection(host: NWEndpoint.Host(host), port: networkPort, using: parameters)
		self.connection = connection

		try await Self.withTimeout(timeout, failingWith: .connectTimeout) {
			try await Self.start(connection)
		}

		return connection
	}

	private func acceptConnection(portRange: ClosedRange<UInt16>) async throws -> NWConnection {
		let (incoming, continuation) = AsyncStream<NWConnection>.makeStream()
		incomingContinuation = continuation

		let listener = try startListener(portRange: portRange, incoming: continuation)
		self.listener = listener

		let boundPort = try await Self.start(listener)
		emit(.listening(port: boundPort))

		var rejectedAPeer = false

		for await candidate in incoming {
			guard Self.connection(candidate, isFrom: configuration.expectedPeerAddress) else {
				Self.logger.error(
					"Rejected a DCC connection from an address other than the one the transfer was offered from"
				)
				rejectedAPeer = true
				candidate.cancel()
				continue
			}

			/* One listener serves one transfer. Leaving the port open past the
			 first accept only gives somebody else a window to reach it. */
			listener.newConnectionHandler = nil
			listener.cancel()
			self.listener = nil
			incomingContinuation = nil
			continuation.finish()

			connection = candidate
			try await Self.start(candidate)

			return candidate
		}

		if rejectedAPeer {
			throw DCCTransferError.rejectedPeerAddress
		}

		throw DCCTransferError.closedByPeer
	}

	/// Binds the first port in the range that will take a listener.
	///
	/// `newConnectionHandler` is installed before the listener starts because
	/// Network.framework refuses to start one without it.
	private func startListener(
		portRange: ClosedRange<UInt16>,
		incoming: AsyncStream<NWConnection>.Continuation
	) throws -> NWListener {
		guard portRange.lowerBound > 0 else {
			throw DCCTransferError.noOpenPort
		}

		for port in portRange {
			guard let networkPort = NWEndpoint.Port(rawValue: port),
			      let listener = try? NWListener(using: .tcp, on: networkPort)
			else {
				continue
			}

			listener.newConnectionHandler = { incoming.yield($0) }

			return listener
		}

		throw DCCTransferError.noOpenPort
	}

	// MARK: - Sending

	private func sendFile(over connection: NWConnection) async throws {
		let handle = try openFileForReading()
		defer { closeFile() }

		try await withThrowingTaskGroup(of: Void.self) { group in
			/* The receiver acknowledges every block and closes the connection
			 once it has the whole file. Draining its acknowledgements keeps
			 them from filling our receive buffer and stalling it, and waiting
			 for the close is what stops us tearing the connection down — and
			 resetting away the last block — before it has landed. */
			group.addTask { await Self.drainUntilPeerCloses(connection) }

			try await sendBlocks(from: handle, over: connection)

			/* Only now does the clock on the close start: a slow but healthy
			 transfer must not trip it. */
			group.addTask {
				try await Task.sleep(for: Self.gracefulCloseTimeout)

				throw DCCTransferError.writeTimeout
			}

			_ = try await group.next()
			group.cancelAll()
		}
	}

	private func openFileForReading() throws -> FileHandle {
		guard let handle = FileHandle(forReadingAtPath: configuration.filePath) else {
			throw DCCTransferError.fileUnreadable
		}

		fileHandle = handle

		guard configuration.resumeOffset > 0 else {
			return handle
		}

		do {
			try handle.seek(toOffset: configuration.resumeOffset)
		} catch {
			closeFile()

			throw DCCTransferError.fileUnreadable
		}

		return handle
	}

	private func sendBlocks(from handle: FileHandle, over connection: NWConnection) async throws {
		var processedBytes = configuration.resumeOffset
		var windowStart = ContinuousClock.now
		var windowBytes: UInt64 = 0

		while processedBytes < configuration.fileSize {
			try Task.checkCancellation()

			let chunk = try Self.read(from: handle, upTo: Self.bufferSize)

			try await Self.withTimeout(configuration.sendTimeout, failingWith: .writeTimeout) {
				try await Self.send(chunk, over: connection)
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

	private nonisolated static func read(from handle: FileHandle, upTo count: Int) throws -> Data { // nonisolated: pure
		let chunk: Data?

		do {
			chunk = try handle.read(upToCount: count)
		} catch {
			throw DCCTransferError.fileUnreadable
		}

		guard let chunk, chunk.isEmpty == false else {
			/* The file shrank, or it never held what the offer announced. */
			throw DCCTransferError.fileUnreadable
		}

		return chunk
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

	private func receiveFile(over connection: NWConnection) async throws {
		let handle = try openFileForWriting()
		defer { closeFile() }

		var processedBytes = configuration.resumeOffset

		while processedBytes < configuration.fileSize {
			try Task.checkCancellation()

			let (payload, isComplete) = try await Self.receive(on: connection)

			if let payload, payload.isEmpty == false {
				let overshot = try store(payload, into: handle, processedBytes: &processedBytes)

				/* The DCC acknowledgement is the receiver's running total, so
				 it goes out before the transfer is torn down for the excess. */
				try await Self.send(Self.acknowledgement(for: processedBytes), over: connection)
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

	/// Writes as much of `payload` as the announced size still has room for.
	///
	/// Returns whether the peer overshot: a peer that sends more than it
	/// advertised would otherwise grow the file by up to one read buffer past
	/// what the user agreed to receive.
	private func store(
		_ payload: Data,
		into handle: FileHandle,
		processedBytes: inout UInt64
	) throws -> Bool {
		let remaining = configuration.fileSize - processedBytes
		let overshot = UInt64(payload.count) > remaining
		let accepted = overshot ? payload.prefix(Int(remaining)) : payload

		guard accepted.isEmpty == false else {
			return overshot
		}

		do {
			try handle.write(contentsOf: accepted)
		} catch {
			let writeError = error as NSError

			if writeError.domain == NSPOSIXErrorDomain, writeError.code == Int(ENOSPC) {
				throw DCCTransferError.storageFull
			}

			throw DCCTransferError.fileUnwritable
		}

		processedBytes += UInt64(accepted.count)

		return overshot
	}

	private func openFileForWriting() throws -> FileHandle {
		let path = configuration.filePath

		if FileManager.default.fileExists(atPath: path) == false {
			guard FileManager.default.createFile(atPath: path, contents: Data()) else {
				throw DCCTransferError.fileUnwritable
			}
		}

		guard let handle = FileHandle(forUpdatingAtPath: path) else {
			throw DCCTransferError.fileUnwritable
		}

		fileHandle = handle

		do {
			if configuration.resumeOffset > 0 {
				try handle.seek(toOffset: configuration.resumeOffset)
			} else {
				try handle.truncate(atOffset: 0)
			}
		} catch {
			closeFile()

			throw DCCTransferError.fileUnwritable
		}

		return handle
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
