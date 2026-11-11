// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Network
import Security
import Testing

/// What a verifier was asked, in order.
actor VerifierLog {
	private(set) var calls: [DCCCertificateFingerprint?] = []

	func record(_ certificate: DCCPeerCertificate?) {
		calls.append(certificate?.fingerprint)
	}
}

/** A raw TLS peer for the secure DCC loopback tests, built directly on
 Network.framework rather than on the code under test.

 It stands in for other clients: a server presenting a certificate, a client
 that presents one or — like KVIrc by default — none, and either one capped at
 an older TLS version. Its own validator accepts whatever it is shown and
 counts the calls, which is how the tests observe when Network.framework asks. */
enum TLSLoopbackPeer {
	struct Options: Sendable {
		/// `nil` presents no certificate, which only a client can do.
		var identity: DCCLocalIdentity?
		var maximumVersion: tls_protocol_version_t?

		init(identity: DCCLocalIdentity? = nil, maximumVersion: tls_protocol_version_t? = nil) {
			self.identity = identity
			self.maximumVersion = maximumVersion
		}
	}

	struct PeerError: Error {}

	/// A range clear of the plain transfer and chat tests'.
	static let portRange: ClosedRange<UInt16> = 49670 ... 49870

	static func tls(_ options: Options, validations: VerifierLog) throws -> TLS {
		var tls = TLS()
			.version(min: .TLSv12, max: options.maximumVersion)
			.peerAuthentication(.optional)
			.certificateValidator { _, trust in
				await validations.record(DCCPeerCertificate.inspect(trust))
				return true
			}
		if let identity = options.identity {
			tls = try tls.localIdentity(identity.makeSecIdentity())
		}
		return tls
	}

	/// Dials a TLS listener on loopback and completes the handshake.
	static func dial(
		port: UInt16,
		options: Options,
		validations: VerifierLog = VerifierLog()
	) async throws -> NetworkConnection<TLS> {
		let tls = try tls(options, validations: validations)
		let endpoint = NWEndpoint.hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port) ?? .any)
		let connection = NetworkConnection<TLS>(to: endpoint, using: .parameters { tls })
		try await connection.send(Data())
		return connection
	}

	/// Listens for one TLS connection and hands it over once its handshake
	/// is done. Cancel the returned task to stop listening.
	static func listen(
		options: Options,
		validations: VerifierLog = VerifierLog()
	) async throws -> (port: UInt16, connection: Task<NetworkConnection<TLS>, Error>) {
		for candidate in portRange {
			guard let port = NWEndpoint.Port(rawValue: candidate) else { continue }
			let tls = try tls(options, validations: validations)
			guard let listener = try? NetworkListener<TLS>(using: .parameters { tls }.localPort(port)) else { continue }

			let (readiness, ready) = AsyncStream<Bool>.makeStream()
			listener.onStateUpdate { _, state in
				switch state {
				case .ready: ready.yield(true)
				case .failed, .waiting, .cancelled: ready.yield(false)
				default: return
				}
				ready.finish()
			}
			let (arrivals, arrival) = AsyncStream<NetworkConnection<TLS>>.makeStream()
			let running = Task {
				try await listener.run { connection in
					arrival.yield(connection)
				}
			}
			var isReady = false
			for await state in readiness {
				isReady = state
				break
			}
			guard isReady else {
				running.cancel()
				continue
			}

			let accepted = Task {
				defer { running.cancel() }
				for await connection in arrivals {
					try await connection.send(Data())
					return connection
				}
				throw PeerError()
			}
			return (candidate, accepted)
		}
		throw PeerError()
	}

	/// Reads until the peer has sent `count` bytes or closes.
	static func read(_ count: Int, from connection: NetworkConnection<TLS>) async throws -> Data {
		var received = Data()
		while received.count < count {
			let message = try await connection.receive(atLeast: 1, atMost: count - received.count)
			received.append(message.content)
			if message.metadata.endOfStream {
				break
			}
		}
		return received
	}
}

/// Secure configurations for the code under test.
enum SecureFixture {
	static func configuration(
		identity: DCCLocalIdentity? = nil,
		requirePeerCertificate: Bool = false,
		decisionTimeout: Duration = DCCTLSConfiguration.defaultDecisionTimeout,
		log: VerifierLog = VerifierLog(),
		decide: @escaping @Sendable (DCCPeerCertificate?) async -> Bool = { _ in true }
	) throws -> DCCTLSConfiguration {
		try DCCTLSConfiguration(
			identity: identity ?? DCCLocalIdentity.generate(),
			requirePeerCertificate: requirePeerCertificate,
			verifier: DCCPeerVerifier { certificate in
				await log.record(certificate)
				return await decide(certificate)
			},
			decisionTimeout: decisionTimeout
		)
	}

	static func transfer(
		role: DCCTransfer.Role,
		endpoint: DCCEndpoint,
		configuration: DCCTLSConfiguration,
		file: DCCTransferFile,
		fileSize: UInt64
	) -> DCCTransfer.Config {
		DCCTransfer.Config(
			role: role,
			endpoint: endpoint,
			security: .tls(configuration),
			file: file,
			fileSize: fileSize
		)
	}

	static func dialling(port: UInt16) -> DCCEndpoint {
		.connect(host: TransferFixture.loopbackHost, port: port, interfaceName: nil, timeout: .seconds(20))
	}

	static let listening = DCCEndpoint.listen(portRange: TLSLoopbackPeer.portRange)

	static func session(_ event: DCCTransferEvent) -> DCCSecureSessionInfo?? {
		guard case let .connected(session) = event else { return nil }
		return .some(session)
	}

	static func listeningPort(_ events: [DCCTransferEvent]) -> UInt16? {
		events.lazy.compactMap { event -> UInt16? in
			guard case let .listening(port) = event else { return nil }
			return port
		}.first
	}
}
