// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** What stands behind a TLS connection's certificate decides whether the account
 password may be sent over it, so the three answers have to stay apart. */
@MainActor
@Suite("Connection certificate assurance", .timeLimit(.minutes(1)))
struct ConnectionCertificateAssuranceTests {
	private func connection(validatingChain: Bool, secured: Bool = true) async throws -> Connection {
		let session = TestServerSession()
		session.setConnectionTransportForTesting(.connected)
		var config = ConnectionConfig()
		config.connectionShouldValidateCertificateChain = validatingChain
		let connection = Connection(config: config, onSession: session)
		session.socket = connection
		if secured {
			connection.callbackReceiver.didSecureConnection(withProtocolType: .TLSv12, cipherSuite: tlsCipherSuiteUnknown)
			try await Eventually.until("TLS to come up") { connection.isSecured }
		}
		return connection
	}

	@Test("A connection without TLS has no assurance")
	func plainConnectionHasNone() async throws {
		#expect(try await connection(validatingChain: true, secured: false).certificateAssurance == nil)
	}

	@Test("A chain the system accepted is validated")
	func acceptedChainIsValidated() async throws {
		#expect(try await connection(validatingChain: true).certificateAssurance == .validated)
	}

	@Test("A connection set not to check the chain is unverified")
	func uncheckedChainIsUnverified() async throws {
		#expect(try await connection(validatingChain: false).certificateAssurance == .unverified)
	}

	@Test("A chain the user chose to continue with is accepted by the user, not validated")
	func promptAcceptedChainIsNotValidated() async throws {
		let connection = try await connection(validatingChain: true)

		connection.noteCertificateTrustOverridden()

		#expect(connection.certificateAssurance == .acceptedByUser)
		#expect(connection.isSecuredWithValidatedCertificate == false)
	}
}
