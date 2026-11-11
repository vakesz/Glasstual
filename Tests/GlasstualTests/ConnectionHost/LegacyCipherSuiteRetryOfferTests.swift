// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Network
import Testing

/** A loopback listener that reads each ClientHello, keeps the cipher suites it
 offers, in order, and answers with a fatal `handshake_failure` alert before
 any ServerHello.

 That is what a server that shares no suite with the client sends, and what an
 on-path attacker can inject: the transport sees `errSSLPeerHandshakeFail`
 before the peer's certificate, which is the one failure the legacy retry
 answers. Reading the offers themselves, rather than which suite a server
 picks, is what says whether the retry still offers forward secrecy first. */
private actor HandshakeRefusingListener {
	private var listener: LoopbackListener?
	private let arrivals: AsyncStream<NWConnection>
	private let arrivalContinuation: AsyncStream<NWConnection>.Continuation
	private var accepting: Task<Void, Never>?
	private var peers: [NWConnection] = []
	/// The suites each ClientHello offered, one entry per dial, in arrival order.
	private(set) var offers: [[UInt16]] = []

	/// A TLS 1.2 fatal alert record: level 2 (fatal), description 40
	/// (handshake_failure).
	private static let handshakeFailureAlert = Data([0x15, 0x03, 0x03, 0x00, 0x02, 0x02, 0x28])

	init() {
		(arrivals, arrivalContinuation) = AsyncStream<NWConnection>.makeStream()
	}

	func start() async throws -> UInt16 {
		let arrivalContinuation = arrivalContinuation
		accepting = Task { [arrivals] in
			for await connection in arrivals {
				self.accept(connection)
			}
		}

		let listener = try await LoopbackListener.start(using: .tcp) { connection in
			arrivalContinuation.yield(connection)
		}
		self.listener = listener
		return listener.port
	}

	func stop() {
		arrivalContinuation.finish()
		accepting?.cancel()
		peers.forEach { $0.cancel() }
		peers.removeAll()
		listener?.stop()
	}

	private func accept(_ connection: NWConnection) {
		peers.append(connection)
		connection.start(queue: .global())
		read(connection, buffered: Data())
	}

	private func read(_ connection: NWConnection, buffered: Data) {
		connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] content, _, isComplete, error in
			let received = buffered + (content ?? Data())
			Task {
				await self?.received(received, on: connection, ended: isComplete || error != nil)
			}
		}
	}

	private func received(_ data: Data, on connection: NWConnection, ended: Bool) {
		guard let suites = Self.offeredSuites(inClientHello: data) else {
			if ended == false {
				read(connection, buffered: data)
			}
			return
		}

		// Recorded before the alert goes out, so the client cannot react first.
		offers.append(suites)
		connection.send(content: Self.handshakeFailureAlert, completion: .contentProcessed { _ in
			connection.cancel()
		})
	}

	/// The cipher suites a ClientHello offers, in its order, or `nil` until
	/// enough of it has arrived. GREASE values are left out.
	private static func offeredSuites(inClientHello data: Data) -> [UInt16]? {
		let bytes = [UInt8](data)
		// Record header (5), handshake header (4), version (2) and random (32).
		let sessionIDOffset = 5 + 4 + 2 + 32
		guard bytes.count > sessionIDOffset, bytes[0] == 0x16, bytes[5] == 0x01 else { return nil }
		let suitesOffset = sessionIDOffset + 1 + Int(bytes[sessionIDOffset])
		guard bytes.count >= suitesOffset + 2 else { return nil }
		let length = Int(bytes[suitesOffset]) << 8 | Int(bytes[suitesOffset + 1])
		let start = suitesOffset + 2
		guard bytes.count >= start + length else { return nil }

		return stride(from: start, to: start + length, by: 2)
			.map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
			.filter { $0 & 0x0F0F != 0x0A0A }
	}
}

private enum RetryOfferEvent: Sendable {
	case didSecure
	case didDisconnect(Error?)
}

/// The object NSXPC exports for the host's callbacks: it holds nothing but the
/// continuation, and every callback arrives on the NSXPC queue.
private final class RetryOfferSessionShim: NSObject, RemoteConnectionClientProtocol {
	private let events: AsyncStream<RetryOfferEvent>.Continuation

	init(events: AsyncStream<RetryOfferEvent>.Continuation) {
		self.events = events

		super.init()
	}

	func willConnect(toProxy _: String, port _: UInt16) {}
	func didConnect(toHost _: String?) {}

	func didSecureConnection(withProtocolType _: tls_protocol_version_t, cipherSuite _: tls_ciphersuite_t, leafCertificate _: Data?) {
		events.yield(.didSecure)
	}

	func didCloseReadStream() {}

	func didDisconnect(withError disconnectError: Error?) {
		events.yield(.didDisconnect(disconnectError))
	}

	func didReceive(_: [Data], acknowledge: @escaping @Sendable () -> Void) {
		acknowledge()
	}

	func requestInsecureCertificateTrust(_ trustBlock: @escaping TrustDecisionHandler) {
		trustBlock(false)
	}

	func willSend(_: Data) {}
	func didSendData() {}

	func didNegotiateWebSocketSubprotocol(_: String?) {}
}

/** What the legacy cipher-suite retry offers, and when it may run at all.

 The retry's security argument is that it only adds the static-RSA suites
 after the selected ones, so a server with anything better still picks it, and
 that an STS-pinned connection never takes it. Both are checked here against
 the real connection host and a peer that refuses every handshake. */
@Suite("Legacy cipher-suite retry offers", .serialized)
nonisolated struct LegacyCipherSuiteRetryOfferTests {
	struct Outcome {
		var offers: [[UInt16]] = []
		var secured = false
		var disconnectError: Error?
	}

	/// The TLS 1.3 suites, which the platform offers whatever the list.
	private static let tls13Suites: Set<UInt16> = [0x1301, 0x1302, 0x1303]

	/// TLS_RSA_WITH_3DES_EDE_CBC_SHA, which no list here offers.
	private static let threeDES: UInt16 = 0x000A

	private static func isForwardSecret(_ suite: UInt16) -> Bool {
		guard let value = tls_ciphersuite_t(rawValue: suite) else { return true }
		return SecureTransportSupport.isCipherSuiteLegacy(value) == false
	}

	/** The platform may leave out a selected suite it no longer implements, so
	 the retry is measured against what the first dial actually offered: every
	 forward-secret suite of it again, then the legacy suites, and never 3DES. */
	@Test(
		"The retry still offers every forward-secret suite of the first dial, ahead of the legacy ones",
		arguments: [CipherSuiteCollection.system, .modern, .intermediate]
	)
	@concurrent
	func retryOffersForwardSecretSuitesFirst(collection: CipherSuiteCollection) async throws {
		let outcome = try await Self.dial(cipherSuites: collection, pinnedByStrictTransportSecurity: false)

		try #require(outcome.offers.count == 2, "the transport dialled \(outcome.offers.count) times")
		let first = outcome.offers[0]
		let retry = outcome.offers[1]
		let selected = SecureTransportSupport.cipherSuites(inCollection: collection).map(\.uint16Value)
		let offered = "first \(first), retry \(retry)"

		#expect(first.contains { Self.isForwardSecret($0) == false } == false, "the first dial offered a legacy suite: \(offered)")
		#expect(
			selected.isEmpty || first.allSatisfy { selected.contains($0) || Self.tls13Suites.contains($0) },
			"the first dial offered an unselected suite: \(offered)"
		)
		#expect(first.allSatisfy(retry.contains), "the retry dropped a suite of the first dial: \(offered)")
		#expect(retry.contains(Self.threeDES) == false, "the retry offered 3DES: \(offered)")

		let legacyPositions = retry.indices.filter { Self.isForwardSecret(retry[$0]) == false }
		let forwardSecretPositions = retry.indices.filter { Self.isForwardSecret(retry[$0]) }
		let firstLegacy = try #require(legacyPositions.min(), "the retry offered no legacy suite: \(offered)")
		let lastForwardSecret = try #require(forwardSecretPositions.max())

		#expect(lastForwardSecret < firstLegacy, "a legacy suite was offered ahead of a forward-secret one: \(offered)")
		#expect(outcome.secured == false)
		#expect(outcome.disconnectError != nil, "the failure was never reported")
	}

	@Test("A connection pinned by an STS policy is never retried with legacy suites")
	@concurrent
	func strictTransportSecurityIsNeverRetried() async throws {
		let outcome = try await Self.dial(cipherSuites: .modern, pinnedByStrictTransportSecurity: true)

		#expect(outcome.offers.count == 1, "the transport dialled \(outcome.offers.count) times")
		#expect(outcome.offers.first?.allSatisfy(Self.isForwardSecret) == true)
		#expect(outcome.secured == false)
		#expect(outcome.disconnectError != nil, "the failure was never reported")
	}

	// MARK: - The harness

	private static func dial(
		cipherSuites: CipherSuiteCollection,
		pinnedByStrictTransportSecurity pinned: Bool
	) async throws -> Outcome {
		let server = HandshakeRefusingListener()
		let port = try await server.start()

		var config = ConnectionConfig()
		config.serverAddress = "127.0.0.1"
		config.serverPort = port
		config.connectionPrefersSecuredConnection = true
		config.connectionRequiresTrustedCertificate = pinned
		config.cipherSuites = cipherSuites

		let (events, continuation) = AsyncStream<RetryOfferEvent>.makeStream()

		let service = NSXPCConnection(serviceName: "com.vakesz.glasstual.IRCConnectionHost")
		service.remoteObjectInterface = RemoteConnectionInterface.server()
		service.exportedInterface = RemoteConnectionInterface.client()
		service.exportedObject = RetryOfferSessionShim(events: continuation)
		service.resume()

		defer {
			service.invalidate()

			Task { await server.stop() }
		}

		let host = try #require(
			service.remoteObjectProxy as? RemoteConnectionServerProtocol,
			"the connection host did not vend its proxy"
		)

		let deadline = Task {
			try? await Task.sleep(for: .seconds(10), clock: .continuous)
			guard Task.isCancelled == false else { return }

			continuation.finish()
		}

		defer { deadline.cancel() }

		host.open(with: ConnectionConfigEnvelope(config: config))

		var outcome = Outcome()

		/* The disconnect is reported only once the transport has given up, after
		 any retry, and the listener records each offer before it refuses it, so
		 the offers read after the disconnect are all there will be. */
		for await event in events {
			switch event {
			case .didSecure:
				outcome.secured = true
				continuation.finish()
			case let .didDisconnect(error):
				outcome.disconnectError = error
				continuation.finish()
			}
		}

		host.close()

		outcome.offers = await server.offers

		return outcome
	}
}
