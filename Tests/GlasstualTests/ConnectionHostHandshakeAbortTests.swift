import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Testing

private enum AbortingListenerError: Error {
	case listenerNeverBecameReady
}

/// A loopback listener that accepts the TCP connection and closes it at once,
/// before any TLS record is exchanged: the shape of a server that throttles a
/// reconnect on a TLS port, which has nothing to say and simply hangs up.
private actor AbortingLoopbackServer {
	private let listener: NWListener
	private var peers: [NWConnection] = []

	init() throws {
		listener = try NWListener(using: .tcp)
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

		throw AbortingListenerError.listenerNeverBecameReady
	}

	func stop() {
		peers.forEach { $0.cancel() }
		peers.removeAll()
		listener.cancel()
	}

	private func accept(_ connection: NWConnection) {
		peers.append(connection)
		connection.start(queue: .global())
		drain(connection)
		/* An orderly close: the ClientHello is read and a FIN goes back, the
		 way a server that hangs up on a throttled reconnect does. Cancelling
		 with unread bytes would send a reset instead, which the transport
		 already reports promptly. */
		connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .idempotent)
	}

	private func drain(_ connection: NWConnection) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, error in
			guard isComplete == false, error == nil else { return }
			Task { await self?.drain(connection) }
		}
	}
}

private enum HostEvent: Sendable {
	case didConnect
	case didDisconnect(Error?)
}

private final class AbortClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<HostEvent>.Continuation

	init(events: AsyncStream<HostEvent>.Continuation) {
		self.events = events
		super.init()
	}

	func ircConnectionWillConnect(toProxy _: String, port _: UInt16) {}
	func ircConnectionDidConnect(toHost _: String?) {
		events.yield(.didConnect)
	}

	func ircConnectionDidSecureConnection(withProtocolType _: tls_protocol_version_t,
	                                      cipherSuite _: tls_ciphersuite_t) {}
	func ircConnectionDidCloseReadStream() {}
	func ircConnectionDidDisconnectWithError(_ error: Error?) {
		events.yield(.didDisconnect(error))
	}

	func ircConnectionDidReceive(_: Data) {}
	func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		trustBlock(false)
	}

	func ircConnectionWillSend(_: Data) {}
	func ircConnectionDidSendData() {}
}

/** A server that hangs up during the TLS handshake must be reported as a
 failure right away.

 Network.framework does not fail a connection whose transport connected but
 whose handshake was cut off; it parks it in `waiting` with the error and
 leaves it there until the path changes. A transport that only listens for
 `ready` then sits on the parked connection until its own 30-second connect
 timer fires, and the person sees "timed out" half a minute after the server
 already said no. */
@Suite("Connection host handshake abort over loopback", .serialized)
nonisolated struct ConnectionHostHandshakeAbortTests { // nonisolated: value
	@Test("A server that closes during the TLS handshake is reported promptly, not after the connect timer")
	@concurrent
	func handshakeAbortIsReportedPromptly() async throws {
		let server = try AbortingLoopbackServer()
		let port = try await server.start()

		var config = IRCConnectionConfig()
		config.serverAddress = "localhost"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true

		let (events, continuation) = AsyncStream<HostEvent>.makeStream()
		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		service.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		service.exportedObject = AbortClientShim(events: continuation)
		service.resume()

		let deadline = Task {
			try? await Task.sleep(for: .seconds(8), clock: .continuous)
			continuation.finish()
		}
		defer {
			deadline.cancel()
			service.invalidate()
			Task { await server.stop() }
		}

		let host = try #require(service.remoteObjectProxy as? RemoteConnectionServerProtocol)
		let started = ContinuousClock.now
		host.open(with: ConnectionConfigEnvelope(config: config))

		var disconnectError: Error?
		var disconnected = false
		for await event in events {
			switch event {
			case .didConnect:
				Issue.record("A connection the server closed mid-handshake was reported connected")
			case let .didDisconnect(error):
				disconnected = true
				disconnectError = error
				continuation.finish()
			}
		}
		let elapsed = ContinuousClock.now - started

		#expect(disconnected, "the host never reported the aborted handshake; elapsed \(elapsed)")
		#expect(elapsed < .seconds(5), "the aborted handshake took \(elapsed) to surface")
		let error = try #require(disconnectError as NSError?, "the abort was reported without its error")
		#expect(error.localizedDescription.localizedCaseInsensitiveContains("timed out") == false,
		        "the server's hang-up was reported as a timeout: \(error)")
	}
}
