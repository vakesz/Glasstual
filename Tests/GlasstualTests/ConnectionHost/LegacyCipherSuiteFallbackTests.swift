// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Security
import Testing

/** Which failures the transport answers by dialling again with the legacy
 suites added, and which it must not.

 The retry is a downgrade the server asked for, so the set of failures that
 reaches it is the whole of the security argument: a peer that can force a
 handshake failure may cost the connection its forward secrecy — which the
 console then says — and must not be able to cost it anything else. */
@Suite("Legacy cipher-suite fallback predicate")
nonisolated struct LegacyCipherSuiteFallbackTests {
	private static func retries(
		after code: Int?,
		alreadyOffered: Bool = false,
		certificateSeen: Bool = false
	) -> Bool {
		SecureTransportSupport.retriesWithLegacyCipherSuites(
			afterErrorCode: code,
			legacySuitesAlreadyOffered: alreadyOffered,
			peerCertificateSeen: certificateSeen
		)
	}

	@Test("A peer that accepted none of the offered suites is retried")
	func noSharedSuiteIsRetried() {
		/* -9824 errSSLPeerHandshakeFail is what dumanet.hu:6697 answers a modern
		 offer with; -9801 errSSLNegotiation is the local shape of the same
		 disagreement. */
		#expect(Self.retries(after: -9824))
		#expect(Self.retries(after: -9801))
		#expect(SecureTransportSupport.namesNoSharedCipherSuite(errorCode: -9824))
		#expect(SecureTransportSupport.namesNoSharedCipherSuite(errorCode: -9801))
	}

	@Test(
		"A failure a cipher suite cannot fix is never retried",
		arguments: [
			-9800, // errSSLProtocol
			-9802, // errSSLFatalAlert
			-9807, // errSSLXCertChainInvalid
			-9808, // errSSLBadCert
			-9812, // errSSLCertExpired
			-9813, // errSSLCertNotYetValid
			-9814, // errSSLUnknownRootCert
			-9815, // errSSLNoRootCert
			-9816, // errSSLClosedNoNotify — a throttled reconnect
			-9819, // errSSLPeerUnexpectedMsg
			-9821, // errSSLPeerInsufficientSecurity
			-9825, // errSSLPeerBadCert
			-9829, // errSSLPeerCertExpired
			-9836, // errSSLPeerProtocolVersion
			-9843, // errSSLHostNameMismatch
			-9999, // what an out-of-range code normalises to
		]
	)
	func otherFailuresAreNotRetried(code: Int) {
		#expect(Self.retries(after: code) == false)
		#expect(SecureTransportSupport.namesNoSharedCipherSuite(errorCode: code) == false)
	}

	/// A timeout, a cancel and a POSIX or DNS failure reach the decision with no
	/// TLS code at all.
	@Test("A failure that is not a TLS failure is never retried")
	func nonTLSFailuresAreNotRetried() {
		#expect(Self.retries(after: nil) == false)
	}

	@Test("The legacy suites are offered once and once only")
	func theRetryHappensOnlyOnce() {
		#expect(Self.retries(after: -9824, alreadyOffered: false))
		#expect(Self.retries(after: -9824, alreadyOffered: true) == false)
	}

	/** A suite both sides agreed on is named in the server's first message, so a
	 handshake that got as far as the peer's certificate agreed on one. A
	 certificate failure reported as -9824 therefore stops the retry on this
	 condition even before the code is looked at. */
	@Test("A failure after the peer's certificate is never retried")
	func failuresAfterTheCertificateAreNotRetried() {
		#expect(Self.retries(after: -9824, certificateSeen: true) == false)
		#expect(Self.retries(after: -9801, certificateSeen: true) == false)
	}
}

// MARK: - The warning the console carries

/** A connection with no forward secrecy says so in the server console, every
 time.

 Keyed on the suite that was negotiated rather than on whether the fallback ran,
 so no path to a legacy suite can reach the console without the warning. */
@MainActor
@Suite("Forward-secrecy warning")
struct ForwardSecrecyWarningTests {
	private static func printedBodies(after suite: UInt16) throws -> [String] {
		let session = TestServerSession()
		let cipherSuite = try #require(tls_ciphersuite_t(rawValue: suite))

		session.connectionDidSecure(protocolType: .TLSv12, cipherSuite: cipherSuite)

		return (session.printedLines as NSArray).compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	private static let warning = String(localized: .IRC.connectionIsNotForwardSecret)

	@Test("A legacy suite warns that the connection is not forward secret")
	func legacySuiteWarns() throws {
		let bodies = try Self.printedBodies(after: 0x009C) // TLS_RSA_WITH_AES_128_GCM_SHA256

		#expect(bodies.contains(Self.warning))
		#expect(bodies.count == 2, "\(bodies)")
	}

	@Test("A forward-secret suite says nothing extra")
	func forwardSecretSuiteDoesNotWarn() throws {
		let bodies = try Self.printedBodies(after: 0xC030) // TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384

		#expect(bodies.contains(Self.warning) == false)
		#expect(bodies.count == 1, "\(bodies)")
	}
}

// MARK: - The fallback, end to end

private enum LegacyListenerError: Error {
	case identityMissing
	case identityUnreadable(OSStatus)
	case listenerNeverBecameReady
}

/** A checked cast that stays checked; `value as? SecIdentity` is rejected
 outright because a conditional downcast to a CoreFoundation type always
 succeeds. */
private nonisolated func dynamicCast<Value>(_ value: Any) -> Value? { // nonisolated: pure
	value as? Value
}

/** A loopback TLS listener that offers exactly the suites it is given, and
 counts how many times it was dialled.

 The count is what the retry is measured by: the application is told nothing
 about the first dial, by design, so the listener is the only place the two are
 distinguishable. A connection reaches `newConnectionHandler` before its
 handshake runs, so a handshake the listener refuses is counted too. */
private actor LegacyCipherSuiteListener {
	/// Swift Testing suites are structs, so there is no test class to hand to
	/// `Bundle(for:)`.
	private final class Anchor {}

	private let listener: NWListener
	private var peers: [NWConnection] = []
	private(set) var dialCount = 0

	init(offering suites: [UInt16]) throws {
		let identity = try Self.identity()
		let options = NWProtocolTLS.Options()

		sec_protocol_options_set_local_identity(options.securityProtocolOptions, identity)
		/* TLS 1.3 has no static-RSA suite, so a server that is to offer one is a
		 TLS 1.2 server. The shape dumanet.hu:6697 has. */
		sec_protocol_options_set_min_tls_protocol_version(options.securityProtocolOptions, .TLSv12)
		sec_protocol_options_set_max_tls_protocol_version(options.securityProtocolOptions, .TLSv12)

		for suite in suites {
			guard let value = tls_ciphersuite_t(rawValue: suite) else { continue }

			sec_protocol_options_append_tls_ciphersuite(options.securityProtocolOptions, value)
		}

		listener = try NWListener(using: NWParameters(tls: options))
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

		throw LegacyListenerError.listenerNeverBecameReady
	}

	func stop() {
		peers.forEach { $0.cancel() }
		peers.removeAll()
		listener.cancel()
	}

	func sendOverlongLine() async throws {
		let peer = try #require(peers.last)
		let data = Data(repeating: 0x61, count: 1024 * 1024 + 1)
		try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
			peer.send(content: data, completion: .contentProcessed { error in
				if let error {
					continuation.resume(throwing: error)
				} else {
					continuation.resume()
				}
			})
		}
	}

	private func accept(_ connection: NWConnection) {
		dialCount += 1
		peers.append(connection)
		connection.start(queue: .global())
		drain(connection)
	}

	private func drain(_ connection: NWConnection) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] _, _, isComplete, error in
			guard isComplete == false, error == nil else { return }

			Task { await self?.drain(connection) }
		}
	}

	private static func identity() throws -> sec_identity_t {
		guard let url = Bundle(for: Anchor.self).url(
			forResource: "LoopbackTestIdentity",
			withExtension: "p12"
		) else {
			throw LegacyListenerError.identityMissing
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
			throw LegacyListenerError.identityUnreadable(status)
		}

		guard let identity = sec_identity_create(secIdentity) else {
			throw LegacyListenerError.identityUnreadable(errSecInternalError)
		}

		return identity
	}
}

private enum FallbackHostEvent: Sendable {
	case didSecure(tls_ciphersuite_t)
	case didDisconnect(Error?)
	case requestInsecureCertificateTrust(TrustDecisionHandler)
}

/// The object NSXPC exports for the host's callbacks: it holds nothing but the
/// continuation, and every callback arrives on the NSXPC queue.
private final class FallbackSessionShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<FallbackHostEvent>.Continuation

	init(events: AsyncStream<FallbackHostEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func willConnect(toProxy _: String, port _: UInt16) {}
	func didConnect(toHost _: String?) {}

	func didSecureConnection(withProtocolType _: tls_protocol_version_t, cipherSuite: tls_ciphersuite_t) {
		events.yield(.didSecure(cipherSuite))
	}

	func didCloseReadStream() {}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func didReceive(_: [Data], acknowledge: @escaping @Sendable () -> Void) {
		acknowledge()
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		events.yield(.requestInsecureCertificateTrust(trustBlock))
	}

	func willSend(_: Data) {}
	func didSendData() {}
}

/** The automatic fallback, driven end to end through the real XPC service and a
 real TLS handshake against a server that offers what the owner's server offers.

 What the application asks for is the modern list on every dial. Whether a
 second dial happens, and whether it is allowed to happen twice, is decided
 inside the transport, so the listener's dial count is what says it did. */
@Suite("Legacy cipher-suite fallback over loopback TLS", .serialized)
nonisolated struct LegacyCipherSuiteFallbackLoopbackTests {
	struct Outcome {
		var negotiatedSuite: tls_ciphersuite_t?
		var disconnectError: Error?
		var dialCount = 0
		var trustRequested = false
		var disconnected = false
	}

	enum SecuredAction {
		case finish, sendOverlongLine, close
	}

	@Test("A server that offers only legacy suites is reached by the second dial")
	@concurrent
	func legacyOnlyServerIsReachedByTheFallback() async throws {
		let outcome = try await Self.dial(
			serverOffering: [0x009C], // TLS_RSA_WITH_AES_128_GCM_SHA256
			validatingCertificateChain: false
		)

		let suite = try #require(outcome.negotiatedSuite, "the connection never secured itself")

		#expect(SecureTransportSupport.isCipherSuiteLegacy(suite))
		#expect(outcome.dialCount == 2, "the transport dialled \(outcome.dialCount) times")
	}

	@Test("A server that agrees on nothing is dialled twice at most, then reported")
	@concurrent
	func aServerThatAgreesOnNothingIsNotDialledForever() async throws {
		/* An ECDSA suite against an RSA identity: the listener can satisfy it no
		 more than it can satisfy the modern list, so both dials fail. */
		let outcome = try await Self.dial(
			serverOffering: [0xC00A], // TLS_ECDHE_ECDSA_WITH_AES_256_CBC_SHA
			validatingCertificateChain: false
		)

		#expect(outcome.negotiatedSuite == nil)
		#expect(outcome.disconnectError != nil, "the failure was never reported")
		#expect(outcome.dialCount <= 2, "the transport dialled \(outcome.dialCount) times")
	}

	/** The listener's certificate is self-signed, so the application is asked and
	 says no. The handshake had already reached the certificate, which means a
	 suite was agreed on, so there is nothing for the fallback to try -- and a
	 peer that can force a handshake failure must not be able to turn a refused
	 certificate into a second attempt. */
	@Test("A refused certificate is never answered with a second dial")
	@concurrent
	func aRefusedCertificateIsNotRetried() async throws {
		let outcome = try await Self.dial(
			serverOffering: [0xC030], // TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384
			validatingCertificateChain: true
		)

		#expect(outcome.trustRequested, "the chain was never put in front of the application")
		#expect(outcome.negotiatedSuite == nil)
		#expect(outcome.dialCount == 1, "the transport dialled \(outcome.dialCount) times")

		let error = try #require(outcome.disconnectError as NSError?)

		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("A protocol failure after a successful fallback retains its actual error")
	@concurrent
	func establishedFallbackReportsItsOwnFailure() async throws {
		let outcome = try await Self.dial(
			serverOffering: [0x009C],
			validatingCertificateChain: false,
			afterSecuring: .sendOverlongLine
		)

		#expect(outcome.negotiatedSuite != nil)
		#expect(outcome.dialCount == 2)
		#expect(outcome.disconnected)
		let error = try #require(outcome.disconnectError as NSError?)
		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.other.rawValue))
	}

	@Test("Rejecting the fallback peer's certificate retains the certificate error")
	@concurrent
	func fallbackCertificateRejectionIsReported() async throws {
		let outcome = try await Self.dial(serverOffering: [0x009C], validatingCertificateChain: true)

		#expect(outcome.trustRequested)
		#expect(outcome.negotiatedSuite == nil)
		#expect(outcome.dialCount == 2)
		let error = try #require(outcome.disconnectError as NSError?)
		#expect(error.domain == connectionErrorDomain)
		#expect(error.code == Int(ConnectionErrorCode.badCertificate.rawValue))
	}

	@Test("Closing an established fallback reports a clean disconnect")
	@concurrent
	func establishedFallbackClosesCleanly() async throws {
		let outcome = try await Self.dial(
			serverOffering: [0x009C],
			validatingCertificateChain: false,
			afterSecuring: .close
		)

		#expect(outcome.negotiatedSuite != nil)
		#expect(outcome.dialCount == 2)
		#expect(outcome.disconnected)
		#expect(outcome.disconnectError == nil)
	}

	// MARK: - The harness

	static func dial(
		serverOffering suites: [UInt16],
		validatingCertificateChain: Bool,
		afterSecuring: SecuredAction = .finish
	) async throws -> Outcome {
		let server = try LegacyCipherSuiteListener(offering: suites)
		let port = try await server.start()

		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true
		config.connectionShouldValidateCertificateChain = validatingCertificateChain
		config.cipherSuites = .modern

		let (events, continuation) = AsyncStream<FallbackHostEvent>.makeStream()
		let shim = FallbackSessionShim(events: continuation)

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

		/* A test that hangs tells nobody anything. Both dials are on loopback, so
		 everything that is going to happen has happened well inside this. */
		let deadline = Task {
			try? await Task.sleep(for: .seconds(10), clock: .continuous)
			guard Task.isCancelled == false else { return }

			continuation.finish()
		}

		defer { deadline.cancel() }

		host.open(with: ConnectionConfigEnvelope(config: config))

		var outcome = Outcome()

		for await event in events {
			switch event {
			case let .didSecure(suite):
				outcome.negotiatedSuite = suite
				switch afterSecuring {
				case .finish:
					continuation.finish()
				case .sendOverlongLine:
					try await server.sendOverlongLine()
				case .close:
					host.close()
				}
			case let .didDisconnect(error):
				outcome.disconnectError = error
				outcome.disconnected = true
				continuation.finish()
			case let .requestInsecureCertificateTrust(answer):
				outcome.trustRequested = true
				answer(false)
			}
		}

		host.close()

		/* Read after the stream ends, and after a beat: a dial the transport gave
		 up on can reach the listener's handler a moment later, and a count taken
		 too early would hide it. */
		try? await Task.sleep(for: .milliseconds(250), clock: .continuous)
		outcome.dialCount = await server.dialCount

		return outcome
	}
}
