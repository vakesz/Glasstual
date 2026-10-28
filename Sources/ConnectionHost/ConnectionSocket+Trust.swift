// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Security

// MARK: - Trust

/// What the service learned about the peer's certificate chain.
///
/// Produced and consumed by the socket actor's async TLS validation path. The
/// `SecTrust` it came from never escapes the validator.
struct TLSTrustExport: Sendable {
	var policyName: String?
	var certificateChain: [Data] = []

	/// Why the system did not trust the chain. nil when it did, or when the
	/// chain has not been evaluated yet.
	var failureDescription: String?
}

struct TLSTrustEvaluation: Sendable {
	var export: TLSTrustExport
	var isRecoverableFailure: Bool
}

extension ConnectionSocket {
	/// Evaluates the peer inside Network.framework's async TLS handshake. A
	/// recoverable failure suspends the handshake while the application asks the
	/// user, so no traffic needs to be buffered behind a separate trust gate.
	/** A `static` member of an actor is already outside its isolation, so this
	 needs no `nonisolated` of its own — and it could not honestly carry the
	 `pure` claim the keyword used to require: `sec_trust_t` is a reference, and
	 evaluating a chain reads the trust store. */
	static func evaluateCertificate(
		_ trust: sec_trust_t
	) -> TLSTrustEvaluation {
		/* sec_trust_copy_ref() follows the Create Rule; the result is +1. */
		let trustRef = sec_trust_copy_ref(trust).takeRetainedValue()

		var evaluationError: CFError?
		let trusted = SecTrustEvaluateWithError(trustRef, &evaluationError)
		let failureDescription = trusted
			? nil
			: ((evaluationError as Error?)?.localizedDescription
				?? String(localized: .ConnectionErrors.unknownError))

		var evaluationResult: SecTrustResultType = .invalid
		SecTrustGetTrustResult(trustRef, &evaluationResult)

		return TLSTrustEvaluation(
			export: TLSTrustExport(
				policyName: SecureTransportSupport.policyName(in: trustRef),
				certificateChain: SecureTransportSupport.certificates(in: trustRef) ?? [],
				failureDescription: failureDescription
			),
			isRecoverableFailure: evaluationResult == .recoverableTrustFailure
		)
	}

	func validateCertificate(_ evaluation: TLSTrustEvaluation, generation: Int) async -> Bool {
		guard generation == dialGeneration, connecting, disconnecting == false else { return false }
		trustExport = evaluation.export

		guard let failureDescription = evaluation.export.failureDescription else {
			config.diagnostics?.record(.certificateAccepted)
			return true
		}

		let serverAddress = config.serverAddress
		guard !config.connectionRequiresTrustedCertificate else { return false }

		guard config.connectionShouldValidateCertificateChain else {
			ConnectionHostLog.connection.error(
				"Certificate chain for '\(serverAddress, privacy: .public)' failed validation but the connection is configured to ignore that: \(failureDescription, privacy: .public)"
			)

			return true
		}

		ConnectionHostLog.connection.error(
			"Certificate chain for '\(serverAddress, privacy: .public)' failed validation: \(failureDescription, privacy: .public)"
		)

		guard evaluation.isRecoverableFailure else {
			return false
		}

		return await requestInsecureTrust()
	}

	/** Asks the application whether to proceed with a chain the system refused.

	 The reply block is the application's to invoke, across XPC, and there are
	 real paths where it never is: the trust panel closed programmatically, or
	 the connection interrupted while it was open. Waiting on that forever
	 strands this actor — and with it the socket, the client proxy and the event
	 stream — for the life of a service process that every connection shares. So
	 the wait is bounded, and cancelling the connection ends it too. Both of
	 those answer `false`, which is the answer the system already gave. */
	func requestInsecureTrust() async -> Bool {
		let (answers, continuation) = AsyncStream<Bool>.makeStream(bufferingPolicy: .bufferingNewest(1))
		trustAnswer = continuation
		cancelConnectTimeout()

		client.requestInsecureCertificateTrust { trusted in
			continuation.yield(trusted)
			continuation.finish()
		}

		let deadline = Task {
			try? await Task.sleep(for: .seconds(Self.trustPromptTimeout), clock: .continuous)

			continuation.finish()
		}

		defer {
			deadline.cancel()
			trustAnswer = nil
			if connecting, disconnecting == false {
				scheduleConnectTimeout()
			}
		}

		for await trusted in answers {
			return trusted && connecting && disconnecting == false && Task.isCancelled == false
		}

		let identifier = uniqueIdentifier

		ConnectionHostLog.connection.error(
			"Certificate trust prompt for connection \(identifier, privacy: .public) went unanswered"
		)

		return false
	}
}
