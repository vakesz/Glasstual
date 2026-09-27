// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network
import Security
import Synchronization
import Testing

@Suite("Client TLS identity chains", .serialized, .timeLimit(.minutes(1)))
nonisolated struct TLSClientIdentityTests {
	@Test("A self-signed client identity does not repeat its own certificate")
	func selfSignedIdentityContainsNoAdditionalLeaf() throws {
		let identity = try TLSClientIdentityFixture.load("LoopbackTestIdentity")
		let prepared = try SecureTransportSupport.localIdentity(identity.value)
		let additional = try #require(sec_identity_copy_certificates_ref(prepared)?.takeRetainedValue() as? [SecCertificate])
		#expect(additional.isEmpty)
	}

	@Test("Client authentication sends one leaf followed by its issuers", arguments: [tls_protocol_version_t.TLSv12, .TLSv13])
	@concurrent
	func completeClientChainAuthenticates(protocolVersion: tls_protocol_version_t) async throws {
		let result = try await TLSClientIdentityPeer().handshake(includingIssuers: true, protocolVersion: protocolVersion)
		#expect(result.trusted)
		#expect(result.connected)
		#expect(result.presentedCertificates == result.expectedCertificates)
	}

	@Test("Missing local intermediates send only the leaf and cannot satisfy a root-only server")
	@concurrent
	func missingIntermediatesRemainATrustFailure() async throws {
		let result = try await TLSClientIdentityPeer().handshake(includingIssuers: false, protocolVersion: .TLSv13)
		#expect(!result.trusted)
		#expect(!result.connected)
		#expect(result.presentedCertificates == Array(result.expectedCertificates.prefix(1)))
	}
}

private nonisolated enum TLSClientIdentityFixture {
	private final class Anchor {}

	/// The generic cast retains a runtime type check for Core Foundation values.
	private static func cast<Value>(_ object: Any) -> Value? {
		object as? Value
	}

	static func load(_ name: String) throws -> (value: SecIdentity, certificates: [SecCertificate]) {
		let url = try #require(Bundle(for: Anchor.self).url(forResource: name, withExtension: "p12"))
		let data = try Data(contentsOf: url)
		var imported: CFArray?
		let status = SecPKCS12Import(data as CFData, [
			kSecImportExportPassphrase as String: "glasstual",
			kSecImportToMemoryOnly as String: true,
		] as CFDictionary, &imported)
		try #require(status == errSecSuccess)
		let item = try #require((imported as? [[String: Any]])?.first)
		let object = try #require(item[kSecImportItemIdentity as String])
		let identity: SecIdentity = try #require(cast(object))
		let chain = try #require(item[kSecImportItemCertChain as String] as? [SecCertificate])
		return (identity, chain)
	}
}

private actor TLSClientIdentityPeer {
	struct Result: Sendable {
		var trusted = false
		var connected = false
		var presentedCertificates: [Data] = []
		var expectedCertificates: [Data] = []
	}

	private enum Event: Sendable {
		case trust(accepted: Bool, certificates: [Data])
		case finished(connected: Bool)
	}

	private var peer: NWConnection?

	func handshake(includingIssuers: Bool, protocolVersion: tls_protocol_version_t) async throws -> Result {
		let serverIdentity = try TLSClientIdentityFixture.load("LoopbackTestIdentity")
		let clientIdentity = try TLSClientIdentityFixture.load("ClientChainTestIdentity")
		let root = try #require(clientIdentity.certificates.last)
		let rootData = SecCertificateCopyData(root) as Data
		let (events, continuation) = AsyncStream<Event>.makeStream()
		let serverOptions = NWProtocolTLS.Options()
		try sec_protocol_options_set_local_identity(
			serverOptions.securityProtocolOptions,
			#require(sec_identity_create(serverIdentity.value))
		)
		sec_protocol_options_set_min_tls_protocol_version(serverOptions.securityProtocolOptions, protocolVersion)
		sec_protocol_options_set_max_tls_protocol_version(serverOptions.securityProtocolOptions, protocolVersion)
		sec_protocol_options_set_peer_authentication_required(serverOptions.securityProtocolOptions, true)
		sec_protocol_options_set_verify_block(serverOptions.securityProtocolOptions, { metadata, trust, complete in
			let trust = sec_trust_copy_ref(trust).takeRetainedValue()
			guard let root = SecCertificateCreateWithData(nil, rootData as CFData),
			      SecTrustSetPolicies(trust, SecPolicyCreateSSL(false, nil)) == errSecSuccess,
			      SecTrustSetAnchorCertificates(trust, [root] as CFArray) == errSecSuccess,
			      SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
			      SecTrustSetNetworkFetchAllowed(trust, false) == errSecSuccess
			else {
				complete(false)
				return
			}
			let trusted = SecTrustEvaluateWithError(trust, nil)
			let presented = Mutex<[Data]>([])
			sec_protocol_metadata_access_peer_certificate_chain(metadata) { certificate in
				let certificate = sec_certificate_copy_ref(certificate).takeRetainedValue()
				presented.withLock { $0.append(SecCertificateCopyData(certificate) as Data) }
			}
			continuation.yield(.trust(accepted: trusted, certificates: presented.withLock { $0 }))
			complete(trusted)
		}, .global())
		let listener = try NWListener(using: NWParameters(tls: serverOptions))
		listener.newConnectionHandler = { [weak self] connection in
			Task { await self?.accept(connection, events: continuation) }
		}
		listener.start(queue: .global())
		defer {
			listener.cancel()
			peer?.cancel()
			peer = nil
			continuation.finish()
		}
		for _ in 0 ..< 200 {
			if listener.state == .ready {
				break
			}
			try await Task.sleep(for: .milliseconds(10))
		}
		let port = try #require(listener.port, "The mTLS listener did not become ready")

		let clientOptions = NWProtocolTLS.Options()
		let prepared = try SecureTransportSupport.localIdentity(
			clientIdentity.value,
			certificateChain: includingIssuers ? clientIdentity.certificates : []
		)
		sec_protocol_options_set_local_identity(clientOptions.securityProtocolOptions, prepared)
		// The peer is this fixture's self-signed listener. Only the server's
		// evaluation of the client chain is under test.
		sec_protocol_options_set_verify_block(clientOptions.securityProtocolOptions, { _, _, complete in complete(true) }, .global())
		let client = NWConnection(host: "127.0.0.1", port: port, using: NWParameters(tls: clientOptions))
		client.start(queue: .global())
		defer { client.cancel() }
		let deadline = Task {
			do { try await Task.sleep(for: .seconds(8)) } catch { return }
			continuation.finish()
		}
		defer { deadline.cancel() }

		var result = Result(expectedCertificates: clientIdentity.certificates.map { SecCertificateCopyData($0) as Data })
		for await event in events {
			switch event {
			case let .trust(accepted, certificates):
				result.trusted = accepted
				result.presentedCertificates = certificates
			case let .finished(connected):
				result.connected = connected
				return result
			}
		}
		Issue.record("The mTLS peer did not finish its handshake")
		return result
	}

	private func accept(_ connection: NWConnection, events: AsyncStream<Event>.Continuation) {
		peer = connection
		connection.stateUpdateHandler = { state in
			switch state {
			case .ready: events.yield(.finished(connected: true))
			case .failed: events.yield(.finished(connected: false))
			default: break
			}
		}
		connection.start(queue: .global())
	}
}
