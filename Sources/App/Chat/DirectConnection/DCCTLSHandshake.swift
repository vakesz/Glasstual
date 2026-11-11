// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Network
import Security

/// What the certificate validator saw and decided, read back once the
/// handshake has finished or failed.
actor DCCHandshakeRecord {
	private(set) var presented: DCCPeerCertificate?
	private(set) var refusal: DCCTransferError?

	func note(_ certificate: DCCPeerCertificate) {
		presented = certificate
	}

	func refuse(_ reason: DCCTransferError) {
		refusal = refusal ?? reason
	}
}

/** The TLS side of one secure DCC connection.

 Peers use self-signed certificates and address each other by IP literal, so
 nothing is evaluated against an authority or a host name: the validator reads
 the leaf, refuses a weak key, and hands the certificate to the verifier, which
 decides on its fingerprint. The handshake waits for that answer, so no
 application byte moves before it.

 The TLS role follows the TCP role, which is the only rule both ends can infer
 without negotiating: whoever accepts is the server and whoever dials is the
 client. Both present the network's identity. As a server the peer's
 certificate is requested but not required, because KVIrc as a client sends
 none; such a peer is decided on after the handshake, with no certificate.

 Each value serves one connection: the record it writes into is its own. */
nonisolated struct DCCTLSHandshake: Sendable {
	enum Role: Sendable {
		case server
		case client
	}

	let configuration: DCCTLSConfiguration
	let role: Role
	let record = DCCHandshakeRecord()

	/// The TLS protocol options, with the identity built here, in the caller's
	/// isolation, because it is not `Sendable`.
	func options(connectTimeout: Duration? = nil) throws -> TLS {
		let identity = try configuration.identity.makeSecIdentity()
		var tcp = TCP()
		if let connectTimeout {
			tcp = tcp.connectionTimeout(UInt32(clamping: connectTimeout.components.seconds))
		}
		let handshake = self
		let tls = TLS { tcp }
			.localIdentity(identity)
			.version(min: .TLSv12)
			.cipherSuiteGroups([.default])
			.ticketsEnabled(false)
			.earlyDataEnabled(false)
			.certificateValidator { _, trust in
				await handshake.validate(DCCPeerCertificate.inspect(trust))
			}
		return switch role {
		case .server: tls.peerAuthentication(.optional)
		case .client: tls.peerAuthentication(.required)
		}
	}

	/// What the validator decides about a presented certificate.
	func validate(_ certificate: DCCPeerCertificate?) async -> Bool {
		guard let certificate else {
			await record.refuse(.peerCertificateRejected)
			return false
		}
		await record.note(certificate)
		guard certificate.keyStrength == .acceptable else {
			await record.refuse(.weakPeerCertificate)
			return false
		}
		guard await decide(certificate) else {
			await record.refuse(.peerCertificateRejected)
			return false
		}
		return true
	}

	/** Finishes the decision once the handshake is complete and reports what
	 was negotiated.

	 A peer whose certificate went through the validator has already been
	 decided on. One that never presented a certificate — only a TLS client can
	 get that far without one — is decided on here, before any byte moves. */
	func establishedSession(of connection: NetworkConnection<TLS>) async throws -> DCCSecureSessionInfo {
		guard let metadata = connection.metadata(definition: NWProtocolTLS.definition) as? NWProtocolTLS.Metadata else {
			throw DCCTransferError.tlsHandshakeFailed("The connection reported no TLS metadata")
		}
		let security = metadata.securityProtocolMetadata
		let peer = await record.presented

		if peer == nil {
			guard role == .server else {
				/* A server always presents a certificate, so the validator always
				 runs for a client; reaching here without one means it did not. */
				throw DCCTransferError.peerCertificateRejected
			}
			guard configuration.requirePeerCertificate == false else {
				throw DCCTransferError.peerCertificateRequired
			}
			guard await decide(nil) else {
				throw DCCTransferError.peerCertificateRejected
			}
		}

		return DCCSecureSessionInfo(
			protocolVersion: sec_protocol_metadata_get_negotiated_tls_protocol_version(security),
			cipherSuite: sec_protocol_metadata_get_negotiated_tls_ciphersuite(security),
			peer: peer
		)
	}

	/// Why the connection failed, naming the validator's refusal when there
	/// was one rather than the TLS alert it caused.
	func failure(for error: Error) async -> DCCTransferError {
		if let refusal = await record.refusal {
			return refusal
		}
		if let error = error as? DCCTransferError {
			return error
		}
		if case let .tls(status) = error as? NWError {
			let description = SecCopyErrorMessageString(status, nil) as String? ?? String(status)
			return .tlsHandshakeFailed(description)
		}
		return DCCTransferError(mapping: error)
	}

	/** Asks the verifier, refusing when it does not answer in time or the
	 handshake is abandoned.

	 The verifier may be waiting on a person and need not notice cancellation,
	 so the answer is raced rather than awaited in a task group, which would
	 wait for the verifier however late it answered. */
	private func decide(_ certificate: DCCPeerCertificate?) async -> Bool {
		let verifier = configuration.verifier
		let timeout = configuration.decisionTimeout
		let (answers, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingOldest(1))
		let decision = Task {
			await continuation.yield(verifier.decide(certificate))
			continuation.finish()
		}
		let deadline = Task {
			try? await Task.sleep(for: timeout)
			continuation.yield(false)
			continuation.finish()
		}
		defer {
			decision.cancel()
			deadline.cancel()
		}

		for await answer in answers {
			return answer
		}
		return false
	}
}
