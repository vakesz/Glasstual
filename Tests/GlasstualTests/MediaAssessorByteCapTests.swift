import Foundation
import InlineContentKit
import Network
import Testing

private enum LoopbackImageServerError: Error {
	case listenerNeverBecameReady
}

/// A server that answers every request with the same body over loopback.
///
/// The assessor's file-size cap only bites when the endpoint declines to
/// declare a length, which no public host can be relied on to do, so the test
/// serves the response itself.
private actor LoopbackImageServer {
	private let listener: NWListener
	private let header: Data
	private let body: Data
	private var connections: [NWConnection] = []

	init(bodyByteCount: Int, declareLength: Bool) throws {
		listener = try NWListener(using: .tcp, on: .any)
		body = Data(repeating: 0x2A, count: bodyByteCount)

		var headerLines = [
			"HTTP/1.1 200 OK",
			"Content-Type: image/png",
			"Connection: close",
		]

		if declareLength {
			headerLines.append("Content-Length: \(bodyByteCount)")
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

		throw LoopbackImageServerError.listenerNeverBecameReady
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

		/* One read is enough: the request fits in a single segment and the
		 response does not depend on it. */
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, _, _ in
			Task { await self?.respond(on: connection) }
		}
	}

	private func respond(on connection: NWConnection) {
		connection.send(content: header + body, completion: .contentProcessed { _ in
			connection.cancel()
		})
	}
}

private func assess(
	address: String,
	expecting type: InlineContentMediaType
) async -> (assessment: MediaAssessment?, error: NSError?) {
	await withCheckedContinuation { continuation in
		guard let url = URL(string: address),
		      let assessor = MediaAssessor(url: url, expectedType: type, completion: { assessment, error in
		      	continuation.resume(returning: (assessment, error))
		      })
		else {
			return continuation.resume(returning: (nil, nil))
		}

		assessor.resume()

		/* URLSession keeps the assessor alive as its delegate until the session
		 invalidates, which is what completes the continuation. */
		withExtendedLifetime(assessor) {}
	}
}

@Suite("Media assessor byte cap", .serialized)
struct MediaAssessorByteCapTests {
	/// Installing preferences is process-wide, so each test puts the default
	/// reader back before it returns.
	private func withImageFileSizeCap<T>(_ cap: UInt64, _ body: () async throws -> T) async rethrows -> T {
		InlineContentPreferences.install {
			InlineContentPreferences.Values(
				maximumImageFileSize: cap,
				maximumHeight: 0,
				maximumWidth: 0,
				limitBasicsToFiles: false
			)
		}

		defer {
			InlineContentPreferences.install {
				InlineContentPreferences.Values(
					maximumImageFileSize: 2 * 1_048_576,
					maximumHeight: 0,
					maximumWidth: 0,
					limitBasicsToFiles: false
				)
			}
		}

		return try await body()
	}

	@Test("A declared length over the cap is refused before the body is fetched")
	func declaredLengthOverTheCapIsRefused() async throws {
		let server = try LoopbackImageServer(bodyByteCount: 64 * 1024, declareLength: true)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let result = await withImageFileSizeCap(8 * 1024) {
			await assess(address: "http://127.0.0.1:\(port)/image.png", expecting: .image)
		}

		let error = try #require(result.error)

		#expect(error.domain == "ICLMediaAssessorErrorDomain")
		#expect(error.code == 1006)
	}

	@Test("An undeclared length is counted and cut off at the cap")
	func undeclaredLengthIsCountedAndCutOff() async throws {
		let server = try LoopbackImageServer(bodyByteCount: 512 * 1024, declareLength: false)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let result = await withImageFileSizeCap(16 * 1024) {
			await assess(address: "http://127.0.0.1:\(port)/image.png", expecting: .image)
		}

		let error = try #require(result.error)

		#expect(error.domain == "ICLMediaAssessorErrorDomain")
		#expect(error.code == 1006)
	}

	@Test("A body inside the cap is not what fails the assessment")
	func bodyInsideTheCapIsNotRefusedForItsSize() async throws {
		let server = try LoopbackImageServer(bodyByteCount: 4 * 1024, declareLength: true)
		let port = try await server.start()

		defer { Task { await server.stop() } }

		let result = await withImageFileSizeCap(64 * 1024) {
			await assess(address: "http://127.0.0.1:\(port)/image.png", expecting: .image)
		}

		/* The bytes are not a real PNG, so the pixel check may still object;
		 what must not happen is a size refusal. */
		#expect(result.error?.code != 1006)
		#expect(result.assessment?.type == .image)
	}
}
