// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

// MARK: - Parameters

extension ConnectionSocket {
	/// Where this connection dials, when a proxy stands in front of the server.
	var proxyEndpoint: (host: String, port: UInt16)? {
		ConnectionParameters.proxyEndpoint(for: config)
	}

	/** The configured handshake, with the one thing the configuration cannot
	 answer: whether this peer's certificate chain is acceptable.

	 The validator is the same on both dials. A downgrade to the legacy suites
	 changes what is negotiated and nothing about who the peer has to be. */
	func constructedTLS(offeringLegacyCipherSuites: Bool) throws -> TLS {
		let generation = dialGeneration

		return try ConnectionParameters.tls(
			for: config,
			offeringLegacyCipherSuites: offeringLegacyCipherSuites
		).certificateValidator { [weak self] _, trust in
			guard let self else { return false }

			let diagnostics = config.diagnostics
			diagnostics?.record(.certificateEvaluationStarted)
			let evaluation = Self.evaluateCertificate(trust)
			diagnostics?.record(.certificateEvaluationCompleted)

			return await validateCertificate(evaluation, generation: generation)
		}
	}
}
