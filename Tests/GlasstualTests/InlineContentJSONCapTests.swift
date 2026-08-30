import Foundation
import InlineContentKit
import Network
import Testing

private enum LoopbackJSONServerError: Error {
	case listenerNeverBecameReady
}

/// A server that answers every request with the same JSON body over loopback.
///
/// The cap only shows itself against an endpoint that returns more than it
/// should, and optionally lies about how much that is, so the test serves the
/// response itself.
private actor LoopbackJSONServer {
	private let listener: NWListener
	private let header: Data
	private let body: Data
	private var connections: [NWConnection] = []

	init(body: String, declaredLength: Int?) throws {
		listener = try NWListener(using: .tcp, on: .any)
		self.body = Data(body.utf8)

		var headerLines = [
			"HTTP/1.1 200 OK",
			"Content-Type: application/json",
			"Connection: close",
		]

		if let declaredLength {
			headerLines.append("Content-Length: \(declaredLength)")
		}

		header = Data((headerLines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
	}

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

		throw LoopbackJSONServerError.listenerNeverBecameReady
	}

	func stop() {
		for connection in connections {
			connection.cancel()
		}

		connections.removeAll()
		listener.cancel()
	}

	private func accept(_ connection: NWConnection) {
		connections.append(connection)

		connection.start(queue: .global())

		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, _ in
			Task { await self?.respond(on: connection) }
		}
	}

	/// Answers, without ever waiting on the client.
	///
	/// The send is fire-and-forget: a client that refuses the body and closes
	/// mid-transfer leaves the completion to report the error instead of
	/// leaving the server parked on a send that will never drain.
	private func respond(on connection: NWConnection) {
		guard connection.state == .ready else {
			connection.cancel()

			return
		}

		connection.send(content: header + body, completion: .contentProcessed { _ in
			connection.cancel()
		})
	}
}

/** The size cap on an oEmbed-style JSON reply.

 The cap used to be applied after `URLSession.data` had already buffered the
 whole reply, which let the endpoint decide how much memory the inline-content
 service spent: it refused the body only once it had been paid for. */
@Suite("Inline content JSON cap", .serialized)
struct InlineContentJSONCapTests {
	private func strings(from body: String, declaredLength: Int?) async throws -> [String: String]? {
		let server = try LoopbackJSONServer(body: body, declaredLength: declaredLength)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let url = try #require(URL(string: "http://127.0.0.1:\(port)/oembed"))

		return await InlineContentHelpers.jsonStrings(from: url)
	}

	@Test("A small reply is read")
	func smallReplyIsRead() async throws {
		let body = #"{"title":"a video","author_name":"someone"}"#
		let strings = try await strings(from: body, declaredLength: body.utf8.count)

		#expect(strings?["title"] == "a video")
		#expect(strings?["author_name"] == "someone")
	}

	/// The declared length is over the cap, so the body is never read at all.
	@Test("A reply that declares more than the cap is refused before it is read")
	func declaredLengthOverTheCapIsRefused() async throws {
		let padding = String(repeating: "x", count: InlineContentNetworkLimits.maximumJSONResponseSize + 1)
		let body = #"{"title":"# + "\"\(padding)\"" + "}"

		#expect(try await strings(from: body, declaredLength: body.utf8.count) == nil)
	}

	/// A server that declares nothing, or lies, is caught by the running count
	/// instead — and the read stops the moment the count passes the cap.
	@Test("A reply that declares nothing and overruns is still refused")
	func undeclaredOverrunIsRefused() async throws {
		let padding = String(repeating: "x", count: InlineContentNetworkLimits.maximumJSONResponseSize + 1)
		let body = #"{"title":"# + "\"\(padding)\"" + "}"

		#expect(try await strings(from: body, declaredLength: nil) == nil)
	}

	@Test("A reply that is not JSON yields nothing")
	func nonJSONYieldsNothing() async throws {
		#expect(try await strings(from: "not json at all", declaredLength: 15) == nil)
	}

	/** The refusal costs about as long as the transfer, and no longer.

	 The body used to be read a byte at a time with a `Data.append` per byte,
	 which took nineteen seconds for this megabyte over loopback and took the
	 test host with it about one run in three. Two seconds is far above what
	 the chunked reader needs and far below what the byte-wise loop cost. */
	@Test("A megabyte overrun is refused in seconds, not tens of seconds")
	func megabyteOverrunIsRefusedQuickly() async throws {
		let padding = String(repeating: "x", count: InlineContentNetworkLimits.maximumJSONResponseSize + 1)
		let body = #"{"title":"# + "\"\(padding)\"" + "}"

		let clock = ContinuousClock()
		let started = clock.now

		#expect(try await strings(from: body, declaredLength: nil) == nil)

		#expect(clock.now - started < .seconds(2))
	}
}
