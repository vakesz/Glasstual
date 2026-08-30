import Foundation
import InlineContentKit
import Network
import Testing

private enum LoopbackChunkedServerError: Error {
	case listenerNeverBecameReady
}

/// A server that drip-feeds a body over loopback, one chunk per interval.
///
/// The chunk boundaries and the pace are what the reader is being tested
/// against: a cap that lands part-way through a chunk, and a caller that walks
/// away while the body is still arriving.
private actor LoopbackChunkedServer {
	private let listener: NWListener
	private let header: Data
	private let chunk: Data
	private let chunkCount: Int
	private let interval: Duration

	private var connections: [NWConnection] = []
	private var sentChunks = 0
	private var completedSends = 0
	private var sendFailed = false
	private var stopped = false

	init(
		chunkByteCount: Int,
		chunkCount: Int,
		interval: Duration = .zero,
		declaresLength: Bool = false
	) throws {
		listener = try NWListener(using: .tcp, on: .any)
		chunk = Data(repeating: 0x2A, count: chunkByteCount)
		self.chunkCount = chunkCount
		self.interval = interval

		var headerLines = [
			"HTTP/1.1 200 OK",
			"Content-Type: application/octet-stream",
			"Connection: close",
		]

		if declaresLength {
			headerLines.append("Content-Length: \(chunkByteCount * chunkCount)")
		}

		header = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

	/// The port the listener settled on, once it is ready.
	func start() async throws -> UInt16 {
		listener.newConnectionHandler = { [weak self] connection in
			Task { await self?.accept(connection) }
		}

		listener.start(queue: .global())

		for _ in 0 ..< 200 {
			if let port = listener.port?.rawValue, listener.state == .ready {
				return port
			}

			try await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		throw LoopbackChunkedServerError.listenerNeverBecameReady
	}

	func stop() {
		stopped = true

		for connection in connections {
			connection.cancel()
		}

		connections.removeAll()
		listener.cancel()
	}

	/// How many chunks reached the transport. A client that walked away leaves
	/// this short of `chunkCount`.
	var chunksSent: Int {
		sentChunks
	}

	private func accept(_ connection: NWConnection) {
		connections.append(connection)

		connection.start(queue: .global())

		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, _ in
			Task { await self?.respond(on: connection) }
		}
	}

	/// Sends the body chunk by chunk, without ever waiting on a send.
	///
	/// Nothing here blocks on the client: the completions only record what
	/// happened, and every wait is bounded, so a client that stops reading —
	/// or closes mid-body — leaves the loop to run out its own schedule
	/// instead of parking the server on a send that will never drain.
	private func respond(on connection: NWConnection) async {
		connection.send(content: header, completion: .idempotent)

		var issued = 0

		for _ in 0 ..< chunkCount {
			guard !stopped, !sendFailed else { break }

			issued += 1

			connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
				Task { await self?.recordSend(error: error) }
			})

			if interval > .zero {
				try? await Task.sleep(for: interval, clock: .continuous)
			}
		}

		/* Closing before the transport has taken the last chunk would reach
		 the client as a reset rather than the end of the body. */
		for _ in 0 ..< 200 {
			guard completedSends < issued, !stopped else { break }

			try? await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		connection.cancel()
	}

	private func recordSend(error: NWError?) {
		completedSends += 1

		if error == nil {
			sentChunks += 1
		} else {
			sendFailed = true
		}
	}
}

private let readerSession: URLSession = {
	let configuration = URLSessionConfiguration.ephemeral
	configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
	return URLSession(configuration: configuration)
}()

/** The chunked reader behind both inline-content body readers.

 Both used to iterate `URLSession.AsyncBytes` a byte at a time, which cost
 about twenty seconds per megabyte and regularly took the test host with it. */
@Suite("Inline content body reader", .serialized)
struct InlineContentBodyReaderTests {
	private func url(for port: UInt16) throws -> URL {
		try #require(URL(string: "http://127.0.0.1:\(port)/body"))
	}

	@Test("Cancelling the caller ends the read and stops the transfer")
	func cancellingTheCallerStopsTheTransfer() async throws {
		let server = try LoopbackChunkedServer(
			chunkByteCount: 16 * 1024,
			chunkCount: 40,
			interval: .milliseconds(50)
		)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let transfer = try await InlineContentBodyReader.begin(
			url(for: port),
			using: readerSession,
			limit: .unlimited
		)

		let reading = Task { try await transfer.data() }

		try await Task.sleep(for: .milliseconds(200), clock: .continuous)

		reading.cancel()

		await #expect(throws: CancellationError.self) {
			_ = try await reading.value
		}

		/* `URLSessionTask.cancel()` is asynchronous, so the state it leaves
		 behind is worth waiting for rather than sampling once. */
		var cancelled = false

		for _ in 0 ..< 100 {
			if transfer.isCancelled {
				cancelled = true

				break
			}

			try await Task.sleep(for: .milliseconds(20), clock: .continuous)
		}

		#expect(cancelled)

		/* The server was still half-way through its schedule, so a transfer
		 that had not stopped would have kept collecting chunks. */
		let sent = await server.chunksSent

		#expect(sent < 40)
	}

	@Test("A cap that falls inside a chunk still refuses the body")
	func capInsideAChunkRefusesTheBody() async throws {
		let server = try LoopbackChunkedServer(chunkByteCount: 4096, chunkCount: 32)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		/* Deliberately not a multiple of the chunk size, and not the whole
		 body either: the refusal has to happen part-way through a chunk. */
		let cap = 4096 + 1000

		let transfer = try await InlineContentBodyReader.begin(
			url(for: port),
			using: readerSession,
			limit: InlineContentBodyLimit(maximumByteCount: cap, refusesDeclaredOverrun: true)
		)

		var received = 0

		await #expect(throws: InlineContentBodyError.bodyTooLarge) {
			for try await chunk in transfer.chunks {
				received += chunk.count
			}
		}

		/* Nothing past the cap is ever handed over: the chunk that would cross
		 it is refused before it is appended. */
		#expect(received <= cap)
	}

	@Test("A body inside the cap is read whole")
	func bodyInsideTheCapIsReadWhole() async throws {
		let server = try LoopbackChunkedServer(chunkByteCount: 4096, chunkCount: 16, declaresLength: true)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let transfer = try await InlineContentBodyReader.begin(
			url(for: port),
			using: readerSession,
			limit: InlineContentBodyLimit(maximumByteCount: 1024 * 1024, refusesDeclaredOverrun: true)
		)

		let body = try await transfer.data()

		#expect(body.count == 4096 * 16)
		#expect(transfer.isCancelled == false)
	}

	@Test("A declared length over the cap is refused before the body is read")
	func declaredOverrunIsRefusedBeforeTheBody() async throws {
		let server = try LoopbackChunkedServer(chunkByteCount: 4096, chunkCount: 16, declaresLength: true)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		await #expect(throws: InlineContentBodyError.bodyTooLarge) {
			_ = try await InlineContentBodyReader.begin(
				url(for: port),
				using: readerSession,
				limit: InlineContentBodyLimit(maximumByteCount: 1024, refusesDeclaredOverrun: true)
			)
		}
	}

	@Test("A megabyte is read in well under a second")
	func aMegabyteIsReadQuickly() async throws {
		let server = try LoopbackChunkedServer(chunkByteCount: 64 * 1024, chunkCount: 16, declaresLength: true)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let transfer = try await InlineContentBodyReader.begin(
			url(for: port),
			using: readerSession,
			limit: InlineContentBodyLimit(maximumByteCount: 4 * 1024 * 1024, refusesDeclaredOverrun: true)
		)

		let clock = ContinuousClock()
		let started = clock.now
		let body = try await transfer.data()

		#expect(body.count == 1024 * 1024)
		#expect(clock.now - started < .seconds(2))
	}
}
