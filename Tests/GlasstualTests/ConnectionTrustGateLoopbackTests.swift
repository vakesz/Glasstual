/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Security
import Testing

/** A checked cast that stays checked.

 `value as? SecIdentity` is rejected outright -- the compiler says a conditional
 downcast to a CoreFoundation type always succeeds -- and `as!` is not
 something this tree writes. Behind a generic parameter the same cast is the
 ordinary dynamic one, which is what it should have been. */
private nonisolated func dynamicCast<Value>(_ value: Any) -> Value? {
	value as? Value
}

private enum LoopbackTLSServerError: Error {
	case identityMissing
	case identityUnreadable(OSStatus)
	case listenerNeverBecameReady
	case peerNeverArrived
}

/** A TLS listener on loopback presenting a self-signed certificate.

 A self-signed chain is what the trust gate exists for: the system will not
 trust it, the failure is recoverable, and the service asks the application. */
private actor LoopbackTLSServer {
	/// Swift Testing suites are structs, so there is no test class to hand to
	/// `Bundle(for:)`.
	private final class Anchor {}

	private let listener: NWListener
	private var peer: NWConnection?

	init() throws {
		let identity = try Self.identity()
		let options = NWProtocolTLS.Options()

		sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)

		listener = try NWListener(using: NWParameters(tls: options))
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

		throw LoopbackTLSServerError.listenerNeverBecameReady
	}

	func stop() {
		peer?.cancel()
		peer = nil
		listener.cancel()
	}

	/** Sends one IRC line to the connected peer and waits for the transport to
	 report it written.

	 The test calls this while the trust prompt is outstanding, so what it sends
	 is exactly what the gate has to hold. */
	func send(_ line: String) async throws {
		let peer = try await readyPeer()
		let data = Data((line + "\r\n").utf8)

		await withCheckedContinuation { continuation in
			peer.send(content: data, completion: .contentProcessed { _ in
				continuation.resume()
			})
		}
	}

	private func accept(_ connection: NWConnection) {
		peer = connection

		connection.start(queue: .global())
	}

	private func readyPeer() async throws -> NWConnection {
		for _ in 0 ..< 400 {
			if let peer, peer.state == .ready {
				return peer
			}

			try await Task.sleep(for: .milliseconds(25), clock: .continuous)
		}

		throw LoopbackTLSServerError.peerNeverArrived
	}

	private static func identity() throws -> sec_identity_t {
		guard let url = Bundle(for: Anchor.self).url(
			forResource: "LoopbackTestIdentity",
			withExtension: "p12"
		) else {
			throw LoopbackTLSServerError.identityMissing
		}

		let data = try Data(contentsOf: url)

		/* To memory only: the identity is a test fixture and has no business in
		 anyone's keychain. */
		let options: [String: Any] = [
			kSecImportExportPassphrase as String: "glasstual",
			kSecImportToMemoryOnly as String: kCFBooleanTrue as Any,
		]

		var imported: CFArray?
		let status = SecPKCS12Import(data as CFData, options as CFDictionary, &imported)

		guard status == errSecSuccess,
		      let items = imported as? [[String: Any]],
		      let value = items.first?[kSecImportItemIdentity as String],
		      let secIdentity: SecIdentity = dynamicCast(value)
		else {
			throw LoopbackTLSServerError.identityUnreadable(status)
		}

		guard let identity = sec_identity_create(secIdentity) else {
			throw LoopbackTLSServerError.identityUnreadable(errSecInternalError)
		}

		return identity
	}
}

/// Everything the connection host reports back, in the order it sent it.
private enum HostEvent: Sendable {
	case didConnect
	case didSecure
	case didReceive(Data)
	case didDisconnect(Error?)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
}

/** The object NSXPC exports for the host's callbacks.

 The same shape as the application's own shim: it holds nothing but the
 continuation, and every callback arrives on the NSXPC queue. */
private final class HostClientShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<HostEvent>.Continuation

	init(events: AsyncStream<HostEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func ircConnectionWillConnect(toProxy _: String, port _: UInt16) {}

	func ircConnectionDidConnect(toHost _: String?) {
		events.yield(.didConnect)
	}

	func ircConnectionDidSecureConnection(
		withProtocolType _: tls_protocol_version_t,
		cipherSuite _: tls_ciphersuite_t
	) {
		events.yield(.didSecure)
	}

	func ircConnectionDidCloseReadStream() {}

	func ircConnectionDidDisconnectWithError(_ disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func ircConnectionDidReceive(_ data: Data) {
		events.yield(.didReceive(data))
	}

	func ircConnectionRequestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func ircConnectionWillSend(_: Data) {}

	func ircConnectionDidSendData() {}
}

/** The trust gate, driven end to end: the real XPC service, a real TLS
 handshake, and a certificate the system genuinely refuses.

 `ConnectionTrustGate` is unit-tested on its own, but what it is for is the
 wiring around it -- the handshake completes, the peer starts talking, and
 nothing it says may reach the application until the person answers. That is
 what these two tests hold: "no" delivers zero bytes and closes, "yes" delivers
 everything that arrived during the wait, in order. */
@Suite("Connection trust gate over loopback TLS", .serialized)
struct ConnectionTrustGateLoopbackTests {
	/// The lines the server sends while the prompt is on screen.
	static let heldLines = [
		":loopback 001 tester :first",
		":loopback 002 tester :second",
		":loopback 003 tester :third",
	]

	@Test("A rejected certificate delivers no bytes and closes the connection")
	func rejectedTrustDeliversNothing() async throws {
		let outcome = try await Self.driveHandshake(answering: false)

		#expect(outcome.received.isEmpty, "the peer's bytes reached the application after the user said no")

		let error = try #require(outcome.disconnectError as NSError?, "the connection was not closed")

		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("An accepted certificate delivers the bytes held during the wait, in order")
	func acceptedTrustDeliversHeldBytesInOrder() async throws {
		let outcome = try await Self.driveHandshake(answering: true)

		let lines = outcome.received.compactMap { String(bytes: $0, encoding: .utf8) }

		#expect(lines == Self.heldLines, "the held bytes did not arrive, or did not arrive in order")
	}

	// MARK: - The harness

	struct Outcome {
		var received: [Data] = []
		var disconnectError: Error?
	}

	/** Connects the real service to the loopback listener, sends
	 ``heldLines`` while the trust prompt is outstanding, answers it, and
	 collects what the application was told.

	 The ordering the test depends on is the ordering the gate promises: the
	 server sends only after the trust request has arrived, so every byte it
	 writes is one the gate has already taken responsibility for. */
	static func driveHandshake(answering trusted: Bool) async throws -> Outcome {
		let server = try LoopbackTLSServer()
		let port = try await server.start()

		var config = IRCConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true
		config.connectionShouldValidateCertificateChain = true

		let (events, continuation) = AsyncStream<HostEvent>.makeStream()
		let shim = HostClientShim(events: continuation)

		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = NSXPCInterface(with: RemoteConnectionServerProtocol.self)
		service.exportedInterface = NSXPCInterface(with: RemoteConnectionClientProtocol.self)
		service.exportedObject = shim
		service.resume()

		defer {
			service.invalidate()

			Task { await server.stop() }
		}

		let host = try #require(
			service.remoteObjectProxy as? RemoteConnectionServerProtocol,
			"the connection host did not vend its proxy"
		)

		/* A test that hangs tells nobody anything, so the stream ends on its own
		 if the handshake never gets anywhere. */
		let deadline = Task {
			try? await Task.sleep(for: .seconds(30), clock: .continuous)

			continuation.finish()
		}

		defer { deadline.cancel() }

		host.open(with: ConnectionConfigEnvelope(config: config))

		var outcome = Outcome()

		for await event in events {
			switch event {
			case let .requestInsecureCertificateTrust(answer):
				for line in heldLines {
					try await server.send(line)
				}

				answer(trusted)
			case let .didReceive(data):
				outcome.received.append(data)

				if trusted, outcome.received.count == heldLines.count {
					continuation.finish()
				}
			case let .didDisconnect(error):
				outcome.disconnectError = error

				continuation.finish()
			case .didConnect, .didSecure:
				break
			}
		}

		host.close()

		return outcome
	}
}
