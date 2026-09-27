// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
private nonisolated func dynamicCast<Value>(_ value: Any) -> Value? { // nonisolated: pure
	value as? Value
}

private enum LoopbackTLSServerError: Error {
	case identityMissing
	case identityUnreadable(OSStatus)
	case listenerNeverBecameReady
	case peerNeverArrived
}

/** A TLS listener on loopback presenting a self-signed certificate.

 A self-signed chain exercises the async certificate validator: the system will
 not trust it, the failure is recoverable, and the service asks the application. */
private actor LoopbackTLSServer {
	/// Swift Testing suites are structs, so there is no test class to hand to
	/// `Bundle(for:)`.
	private final class Anchor {}

	private let listener: NWListener
	private var peer: NWConnection?
	private var received = Data()

	init(protocolVersion: tls_protocol_version_t? = nil) throws {
		let identity = try Self.identity()
		let options = NWProtocolTLS.Options()

		sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
		if let protocolVersion {
			sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, protocolVersion)
			sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, protocolVersion)
		}

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

	/// Sends one IRC line after the session accepts the certificate and waits for
	/// the transport to report it written.
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
		receiveNextChunk()
	}

	private func receiveNextChunk() {
		peer?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, complete, error in
			Task { await self?.received(data, complete: complete || error != nil) }
		}
	}

	private func received(_ data: Data?, complete: Bool) {
		if let data {
			received.append(data)
		}
		if complete == false {
			receiveNextChunk()
		}
	}

	func registrationLines() async throws -> [String] {
		for _ in 0 ..< 200 {
			let lines = (String(bytes: received, encoding: .utf8) ?? "").components(separatedBy: "\r\n")
			if lines.count >= 4 {
				return Array(lines.dropLast())
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		return []
	}

	func serverName() async throws -> String? {
		let peer = try await readyPeer()
		guard let metadata = peer.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata,
		      let name = sec_protocol_metadata_copy_server_name(metadata.securityProtocolMetadata)
		else { return nil }
		defer { free(UnsafeMutableRawPointer(mutating: name)) }
		return String(cString: name)
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
	case didSecure(protocolVersion: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t)
	case didReceive(Data)
	case didDisconnect(Error?)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
	case exportedTrust(SecureConnectionInformation, TrustDecisionHandler)
}

/** The object NSXPC exports for the host's callbacks.

 The same shape as the application's own shim: it holds nothing but the
 continuation, and every callback arrives on the NSXPC queue. */
private final class HostSessionShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<HostEvent>.Continuation

	init(events: AsyncStream<HostEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func willConnect(toProxy _: String, port _: UInt16) {}

	func didConnect(toHost _: String?) {
		events.yield(.didConnect)
	}

	func didSecureConnection(
		withProtocolType protocolType: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t
	) {
		events.yield(.didSecure(protocolVersion: protocolType, cipherSuite: cipherSuite))
	}

	func didCloseReadStream() {}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func didReceive(_ lines: [Data], acknowledge: @escaping @Sendable () -> Void) {
		for line in lines {
			events.yield(.didReceive(line))
		}
		acknowledge()
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func willSend(_: Data) {}

	func didSendData() {}
}

/** Async certificate validation, driven end to end through the real XPC
 service, a real TLS handshake, and a certificate the system refuses.

 The handshake remains suspended without blocking a thread while the person
 answers. "No" delivers zero bytes and closes; "yes" completes the handshake
 and delivers everything in order. */
@Suite("Async certificate validation over loopback TLS", .serialized)
nonisolated struct AsyncCertificateValidationLoopbackTests {
	static let testLines = [
		":loopback 001 tester :first",
		":loopback 002 tester :second",
		":loopback 003 tester :third",
	]

	@Test("A rejected certificate delivers no bytes and closes the connection")
	@concurrent
	func rejectedTrustDeliversNothing() async throws {
		let outcome = try await Self.driveHandshake(answering: false)

		#expect(outcome.received.isEmpty, "the peer's bytes reached the application after the user said no")

		let error = try #require(outcome.disconnectError as NSError?, "the connection was not closed")

		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("An accepted certificate completes the handshake and delivers bytes in order")
	@concurrent
	func acceptedTrustDeliversBytesInOrder() async throws {
		let outcome = try await Self.driveHandshake(answering: true)

		let lines = outcome.received.compactMap { String(bytes: $0, encoding: .utf8) }

		#expect(lines == Self.testLines, "the bytes did not arrive, or did not arrive in order")
	}

	/** The metadata a handshake produces only exists once the handshake has run,
	 and a typed connection establishes lazily: reading it when the transport
	 hands over the connection reads it from a connection still in setup, and
	 the event is silently never sent. */
	@Test("An accepted certificate reports the protocol and cipher that were negotiated")
	@concurrent
	func acceptedTrustReportsWhatWasNegotiated() async throws {
		let outcome = try await Self.driveHandshake(answering: true)

		let secured = try #require(outcome.secured, "the connection never reported itself secured")

		#expect(secured.protocolVersion != tlsProtocolVersionUnknown)
		#expect(secured.protocolVersion.rawValue >= SecureTransportSupport.minimumProtocolType.rawValue)
		#expect(secured.cipherSuite != tlsCipherSuiteUnknown)
		#expect(SecureTransportSupport.description(forCipherSuite: secured.cipherSuite) != "Unknown")
	}

	@Test("TLS 1.2 and 1.3 both report the negotiated version", arguments: [tls_protocol_version_t.TLSv12, .TLSv13])
	@concurrent
	func supportedProtocolVersions(protocolVersion: tls_protocol_version_t) async throws {
		let outcome = try await Self.driveHandshake(answering: true, serverProtocolVersion: protocolVersion)
		#expect(outcome.secured?.protocolVersion == protocolVersion)
		#expect(outcome.registration == ["CAP LS 302", "NICK tester", "USER tester 0 * :Tester"])
	}

	@Test("A DNS endpoint supplies the TLS server name and certificate policy host")
	@concurrent
	func dnsEndpointPreservesServerIdentity() async throws {
		let outcome = try await Self.driveHandshake(answering: true, serverAddress: "localhost")
		#expect(outcome.serverName == "localhost")
		#expect(outcome.policyName == "localhost")
		#expect(outcome.secured != nil)
	}

	@Test("Registration and certificate export do not depend on a pending TLS send")
	@concurrent
	func registrationAndTrustExportRemainLive() async throws {
		let outcome = try await Self.driveHandshake(answering: true)
		#expect(outcome.exportedCertificate)
		#expect(outcome.connectedBeforeTrust == false)
		#expect(outcome.registration == ["CAP LS 302", "NICK tester", "USER tester 0 * :Tester"])
		#expect(outcome.secured != nil)
	}

	@Test("Closing while the certificate prompt is unanswered cancels the handshake")
	@concurrent
	func closeCancelsPendingTrust() async throws {
		let outcome = try await Self.driveHandshake(answering: false, closeDuringTrust: true)
		#expect(outcome.exportedCertificate)
		#expect(outcome.disconnected)
		#expect(outcome.received.isEmpty)
		#expect(outcome.secured == nil)
		#expect(outcome.connectedBeforeTrust == false)
	}

	@Test("STS refuses an untrusted certificate without offering an override", arguments: [false, true])
	@concurrent
	func strictTrustCannotBeOverridden(validatesCertificateChain: Bool) async throws {
		let outcome = try await Self.driveHandshake(
			answering: true, requiresTrustedCertificate: true,
			validatesCertificateChain: validatesCertificateChain
		)
		#expect(outcome.disconnected)
		#expect(outcome.trustRequested == false)
		#expect(outcome.received.isEmpty)
		#expect(outcome.secured == nil)
		let error = try #require(outcome.disconnectError as NSError?)
		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("A missing configured client identity fails instead of connecting anonymously")
	@concurrent
	func missingClientIdentityFailsClosed() async throws {
		let outcome = try await Self.driveHandshake(answering: true, clientCertificateReference: Data([0, 1, 2]))
		#expect(outcome.disconnected)
		#expect(outcome.disconnectError != nil)
		#expect(outcome.trustRequested == false)
		#expect(outcome.secured == nil)
		#expect(outcome.registration.isEmpty)
	}

	// MARK: - The harness

	struct Secured: Sendable {
		var protocolVersion: tls_protocol_version_t
		var cipherSuite: tls_ciphersuite_t
	}

	struct Outcome {
		var received: [Data] = []
		var secured: Secured?
		var disconnectError: Error?
		var exportedCertificate = false
		var connectedBeforeTrust = false
		var registration: [String] = []
		var disconnected = false
		var trustRequested = false
		var policyName: String?
		var serverName: String?
	}

	/** Connects the real service to the loopback listener, sends
	 answers the trust prompt, sends ``testLines`` after an accepted handshake,
	 and collects what the application was told. */
	static func driveHandshake(
		answering trusted: Bool,
		closeDuringTrust: Bool = false,
		requiresTrustedCertificate: Bool = false,
		validatesCertificateChain: Bool = true,
		clientCertificateReference: Data? = nil,
		serverProtocolVersion: tls_protocol_version_t? = nil,
		serverAddress: String = "127.0.0.1"
	) async throws -> Outcome {
		let server = try LoopbackTLSServer(protocolVersion: serverProtocolVersion)
		let port = try await server.start()

		var config = ConnectionConfig()
		config.serverAddress = serverAddress
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true
		config.connectionShouldValidateCertificateChain = validatesCertificateChain
		config.connectionRequiresTrustedCertificate = requiresTrustedCertificate
		config.identityClientSideCertificate = clientCertificateReference

		let (events, continuation) = AsyncStream<HostEvent>.makeStream()
		let shim = HostSessionShim(events: continuation)

		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
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
			try? await Task.sleep(for: .seconds(8), clock: .continuous)
			guard Task.isCancelled == false else { return }
			continuation.finish()
			await server.stop()
		}

		defer { deadline.cancel() }

		host.open(with: ConnectionConfigEnvelope(config: config))

		var outcome = Outcome()
		var trustAnswered = false

		for await event in events {
			switch event {
			case let .requestInsecureCertificateTrust(answer):
				outcome.trustRequested = true
				host.exportSecureConnectionInformation { information in
					continuation.yield(.exportedTrust(information, answer))
				}
			case let .exportedTrust(information, answer):
				outcome.exportedCertificate = information.certificateChain.isEmpty == false
				outcome.policyName = information.policyName
				if closeDuringTrust {
					host.close()
					break
				}
				trustAnswered = true
				answer(trusted)

				if trusted {
					for line in testLines {
						try await server.send(line)
					}
				}
			case let .didReceive(data):
				outcome.received.append(data)

				if trusted, outcome.received.count == testLines.count {
					continuation.finish()
				}
			case let .didSecure(protocolVersion, cipherSuite):
				outcome.secured = Secured(protocolVersion: protocolVersion, cipherSuite: cipherSuite)
			case let .didDisconnect(error):
				outcome.disconnected = true
				outcome.disconnectError = error

				continuation.finish()
			case .didConnect:
				outcome.connectedBeforeTrust = trustAnswered == false
				for line in ["CAP LS 302", "NICK tester", "USER tester 0 * :Tester"] {
					host.send(Data((line + "\r\n").utf8))
				}
			}
		}

		if trusted, outcome.secured != nil {
			outcome.registration = try await server.registrationLines()
			outcome.serverName = try await server.serverName()
		}
		host.close()

		return outcome
	}
}
