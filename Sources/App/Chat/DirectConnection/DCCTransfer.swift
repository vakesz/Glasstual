// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network

/// DCC SEND uses cumulative network-order UInt32 ACKs, modulo 4 GiB.
nonisolated struct DCCAcknowledgements {
	private var pending: [UInt8] = []
	private(set) var hasBytes = false
	private(set) var acknowledged: UInt64
	let offeredSize: UInt64

	init(offset: UInt64, offeredSize: UInt64) {
		acknowledged = offset
		self.offeredSize = offeredSize
	}

	var isComplete: Bool {
		hasBytes && pending.isEmpty && acknowledged == offeredSize
	}

	mutating func append(_ data: Data) throws {
		for byte in data {
			hasBytes = true
			pending.append(byte)
			guard pending.count == 4 else { continue }
			let value = pending.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
			pending.removeAll(keepingCapacity: true)
			let delta = UInt64(value &- UInt32(truncatingIfNeeded: acknowledged))
			guard acknowledged <= offeredSize, delta <= offeredSize - acknowledged else {
				throw DCCTransferError.badParameter
			}
			acknowledged += delta
		}
	}
}

/// Why a DCC transfer stopped before it delivered the whole file.
nonisolated enum DCCTransferError: Error, Equatable, Sendable {
	case connectTimeout
	/// The connection stopped moving data: a write did not complete in time,
	/// or a download went too long without receiving anything.
	case stalled
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

	/// How a failure reaches the feature driving a DCC connection: one of the
	/// cases above passes through, and anything else the network raised is
	/// reported with the text it came with.
	init(mapping error: Error) {
		self = error as? DCCTransferError ?? .network(error.localizedDescription)
	}
}

/// What a ``DCCTransfer`` reports to whoever is driving it.
///
/// The sequence is always zero or one `listening`, then `connected`, then any
/// number of `progress`, then — only for a transfer that delivered everything —
/// one `completion`, then exactly one of `finished`/`failed`. A cancelled
/// transfer ends the stream without a terminal event.
nonisolated enum DCCTransferEvent: Sendable {
	case listening(port: UInt16)
	case connected
	case progress(processedBytes: UInt64)
	case completion(DCCTransfer.Completion)
	case finished
	case failed(DCCTransferError)
}

/// Keeps display progress below the rate of file blocks without losing the
/// latest byte count. The transfer flushes it before completion, failure or
/// cancellation, so progress cannot arrive after a terminal event.
nonisolated struct DCCProgressSampler {
	let minimumInterval: Duration
	private var lastEmission: ContinuousClock.Instant?
	private var lastReportedBytes: UInt64?
	private var pendingBytes: UInt64?

	init(minimumInterval: Duration) {
		self.minimumInterval = minimumInterval
	}

	mutating func record(_ bytes: UInt64, at now: ContinuousClock.Instant) -> UInt64? {
		guard (pendingBytes ?? lastReportedBytes).map({ bytes > $0 }) ?? true else { return nil }
		if let lastEmission, now - lastEmission < minimumInterval {
			pendingBytes = bytes
			return nil
		}
		lastEmission = now
		lastReportedBytes = bytes
		pendingBytes = nil
		return bytes
	}

	mutating func flush() -> UInt64? {
		guard let pendingBytes else { return nil }
		self.pendingBytes = nil
		lastReportedBytes = pendingBytes
		return pendingBytes
	}
}

/// One DCC file transfer: the socket, the file and the DCC acknowledgement
/// protocol, all owned by a single actor.
///
/// Nothing about a transfer is shared: the actor creates its own typed
/// Network.framework connection or listener, opens its own `FileHandle`, and
/// reports what it is doing through ``events``. The transport's async methods
/// run inside the transfer task, so the actor is the one place the transfer's
/// state lives.
actor DCCTransfer {
	nonisolated enum Completion: Sendable {
		case received
		case acknowledged
		/// All bytes were submitted and the ACKless peer closed cleanly. This
		/// does not claim that the peer persisted or acknowledged the file.
		case unacknowledged
	}

	/// Which end of the transfer this actor is.
	nonisolated enum Role: Sendable {
		case sender
		case receiver
	}

	struct Config: Sendable {
		var role: Role
		var endpoint: DCCEndpoint
		/// The file to read from, or the file to write into. The caller
		/// reserves it: the actor only ever uses the descriptor it is handed,
		/// so nothing here can open a second file under the same name.
		var file: DCCTransferFile
		/// How many bytes the transfer announced. The receiver refuses to
		/// store more than this and the sender stops after it.
		var fileSize: UInt64
		/// Where in the file to resume, for a DCC `RESUME`.
		var resumeOffset: UInt64
		/// Only a connection from this address is accepted. Empty accepts any,
		/// which is what a plain `DCC SEND` has to do: we listen, and the peer
		/// announces itself by arriving.
		var expectedPeerAddress: String
		/// How long a single write may take before the transfer fails.
		var sendTimeout: Duration?
		var inactivityTimeout: Duration?
		/// The whole window a listening transfer has to bind a port and take
		/// the peer's connection, not a budget for each step in turn.
		var acceptanceTimeout: Duration?

		init(
			role: Role,
			endpoint: DCCEndpoint,
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

	/// The transfer paces itself to this many bytes a second so a local
	/// transfer cannot starve the rest of the app.
	static let rateLimitBytesPerSecond: UInt64 = 10 * 1024 * 1024
	/// Progress is presentation data; byte I/O and DCC acknowledgements still
	/// happen for every block. Ten updates per second keep large transfers from
	/// asking the main actor to redraw a row for every 64 KiB block.
	static let progressInterval: Duration = .milliseconds(100)
	/// How long the sender waits for the receiver to close once the last block
	/// has gone out.
	static let gracefulCloseTimeout: Duration = .seconds(30)

	/// The transfer's progress, in order. Finishes when the transfer does.
	nonisolated let events: AsyncStream<DCCTransferEvent>

	private var config: Config
	private let eventContinuation: AsyncStream<DCCTransferEvent>.Continuation

	private var runTask: Task<Void, Never>?
	private var connection: NetworkConnection<TCP>?
	private var file: DCCTransferFile?
	private var bytesStarted = false
	private var submittedBytes: UInt64 = 0
	private var isCancelled = false
	private var hasFinished = false
	private var progressSampler = DCCProgressSampler(minimumInterval: DCCTransfer.progressInterval)

	init(config: Config) {
		let (stream, continuation) = AsyncStream<DCCTransferEvent>.makeStream()
		events = stream
		eventContinuation = continuation
		self.config = config
	}

	deinit {
		eventContinuation.finish()
	}

	/// Begins the transfer. Calling it twice does nothing the second time.
	func start() {
		guard runTask == nil, isCancelled == false else {
			return
		}

		runTask = Task { [self] in
			await run()
		}
	}

	/// Stops the transfer and ends ``events`` without a terminal event.
	func cancel() async {
		let running = runTask
		if isCancelled == false {
			isCancelled = true
			running?.cancel()
			tearDown()
			flushProgress()
			hasFinished = true
			eventContinuation.finish()
		}

		// Every caller must observe quiescence before releasing the file lease,
		// including a second cancellation while the first is still draining.
		await running?.value
		runTask = nil
	}

	/// RESUME changes the pending byte offset, never the listening socket.
	func commitResumeOffset(_ offset: UInt64) -> Bool {
		guard !Task.isCancelled, !isCancelled, !hasFinished, !bytesStarted,
		      offset > 0, offset <= config.fileSize else { return false }
		config.resumeOffset = offset
		return true
	}

	// MARK: - Running

	private func run() async {
		do {
			guard config.resumeOffset <= config.fileSize else { throw DCCTransferError.badParameter }
			file = config.file
			let connection = try await establishConnection()
			try Task.checkCancellation()
			bytesStarted = true
			submittedBytes = config.resumeOffset
			emit(.connected)

			switch config.role {
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

			finish(with: .failed(DCCTransferError(mapping: error)))
		}
	}

	private func emit(_ event: DCCTransferEvent) {
		guard hasFinished == false else {
			return
		}
		if case let .progress(processedBytes) = event {
			if let bytes = progressSampler.record(processedBytes, at: .now) {
				eventContinuation.yield(.progress(processedBytes: bytes))
			}
			return
		}
		if case .completion = event {
			flushProgress()
		}
		eventContinuation.yield(event)
	}

	private func flushProgress() {
		if let bytes = progressSampler.flush() {
			eventContinuation.yield(.progress(processedBytes: bytes))
		}
	}

	private func finish(with event: DCCTransferEvent) {
		guard hasFinished == false else {
			return
		}

		flushProgress()
		hasFinished = true
		eventContinuation.yield(event)
		eventContinuation.finish()
	}

	private func tearDown() {
		connection = nil

		file = nil
	}

	// MARK: - Establishing the connection

	private func establishConnection() async throws -> NetworkConnection<TCP> {
		let connection: NetworkConnection<TCP>

		switch config.endpoint {
		case let .connect(host, port, interfaceName, timeout):
			connection = try await DCCConnectionEndpoint.connect(
				toHost: host,
				port: port,
				interfaceName: interfaceName,
				timeout: timeout
			)
		case let .listen(portRange):
			let deadline = config.acceptanceTimeout.map { ContinuousClock.now + $0 }
			let session = try await DCCConnectionEndpoint.bind(portRange: portRange, deadline: deadline)

			emit(.listening(port: session.port))

			connection = try await DCCConnectionEndpoint.accept(
				on: session,
				expectedPeerAddress: config.expectedPeerAddress,
				sendTimeout: config.sendTimeout,
				deadline: deadline,
				log: DirectConnectionLog.transfer
			)
		}

		self.connection = connection

		return connection
	}

	// MARK: - Sending

	private nonisolated enum SendResult: Sendable {
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
						throw DCCTransferError.stalled
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
			offset: config.resumeOffset,
			offeredSize: config.fileSize
		)
		while true {
			let (payload, complete) = try await DCCConnectionEndpoint.receive(on: connection)
			if let payload {
				try acknowledgements.append(payload)
			}
			guard acknowledgements.acknowledged <= submittedBytes else { throw DCCTransferError.badParameter }
			if acknowledgements.isComplete {
				return .acknowledged
			}
			if complete {
				guard submittedBytes == config.fileSize, !acknowledgements.hasBytes else {
					throw DCCTransferError.closedByPeer
				}
				return .unacknowledged
			}
		}
	}

	private func sendBlocks(from file: DCCTransferFile, over connection: NetworkConnection<TCP>) async throws {
		var processedBytes = config.resumeOffset
		var windowStart = ContinuousClock.now
		var windowBytes: UInt64 = 0

		while processedBytes < config.fileSize {
			try Task.checkCancellation()

			let count = Int(min(UInt64(DCCTransport.bufferSize), config.fileSize - processedBytes))
			let chunk = try await file.read(at: processedBytes, count: count)
			try Task.checkCancellation()
			submittedBytes = processedBytes + UInt64(chunk.count)

			try await DCCTransport.withTimeout(config.sendTimeout, failingWith: .stalled) {
				try await connection.send(chunk)
			}

			processedBytes += UInt64(chunk.count)
			emit(.progress(processedBytes: processedBytes))

			windowBytes += UInt64(chunk.count)

			if windowBytes >= Self.rateLimitBytesPerSecond {
				try await pause(untilASecondHasPassedSince: windowStart)
				windowStart = ContinuousClock.now
				windowBytes = 0
			}
		}
	}

	/// Sleeps out what is left of the second that began at `start`. The sleep
	/// suspends the transfer, not the actor: nothing else waits on it meanwhile.
	private func pause(untilASecondHasPassedSince start: ContinuousClock.Instant) async throws {
		let elapsed = ContinuousClock.now - start

		guard elapsed < .seconds(1) else {
			return
		}

		try await Task.sleep(for: .seconds(1) - elapsed)
	}

	// MARK: - Receiving

	private func receiveFile(over connection: NetworkConnection<TCP>) async throws {
		guard let file, try await file.size() == config.resumeOffset else {
			throw DCCTransferError.fileUnwritable
		}

		var processedBytes = config.resumeOffset
		if processedBytes == config.fileSize {
			let acknowledgement = Self.acknowledgement(for: processedBytes)
			try await DCCTransport.withTimeout(config.sendTimeout, failingWith: .stalled) {
				try await connection.send(acknowledgement)
			}
		}

		while processedBytes < config.fileSize {
			try Task.checkCancellation()

			let (payload, isComplete) = try await DCCTransport.withTimeout(
				config.inactivityTimeout,
				failingWith: .stalled
			) {
				try await DCCConnectionEndpoint.receive(on: connection)
			}

			if let payload, payload.isEmpty == false {
				let remaining = config.fileSize - processedBytes
				let overshot = UInt64(payload.count) > remaining
				let accepted = overshot ? Data(payload.prefix(Int(remaining))) : payload
				try await file.write(accepted, at: processedBytes)
				processedBytes += UInt64(accepted.count)

				/* The DCC acknowledgement is the receiver's running total, so
				 it goes out before the transfer is torn down for the excess. */
				let acknowledgement = Self.acknowledgement(for: processedBytes)
				try await DCCTransport.withTimeout(config.sendTimeout, failingWith: .stalled) {
					try await connection.send(acknowledgement)
				}
				emit(.progress(processedBytes: processedBytes))

				if overshot {
					throw DCCTransferError.oversizedTransfer
				}
			}

			if isComplete, processedBytes < config.fileSize {
				throw DCCTransferError.closedByPeer
			}
		}
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
