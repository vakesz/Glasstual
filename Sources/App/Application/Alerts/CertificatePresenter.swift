// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

/// Presents native certificate panels. The requesting connection owns the decision.
@MainActor
final class CertificatePresenter: CertificatePresenting {
	private weak var activeRequest: CertificateTrustRequest?

	func beginTrustRequest(decided: @escaping (Bool) -> Void) -> CertificateTrustRequest? {
		guard activeRequest == nil else { return nil }
		let request = CertificateTrustRequest(present: Self.presentTrustPrompt) { [weak self] trusted in
			self?.activeRequest = nil
			decided(trusted)
		}
		activeRequest = request
		return request
	}

	private static func presentTrustPrompt(
		_ information: SecureConnectionInformation,
		decided: @escaping (Bool) -> Void
	) -> (() -> Void)? {
		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else { return nil }
		let panel = TrustPanelPresenter.present(
			in: nil,
			body: PromptStrings.TransportSecurity.certificateFailureBody(serverName: policyName),
			title: PromptStrings.TransportSecurity.certificateFailureTitle(serverName: policyName),
			defaultButton: PromptStrings.Action.continueAction,
			alternateButton: PromptStrings.Action.cancel,
			trust: trust,
			completion: decided
		)
		return { panel.dismiss() }
	}

	/// Shows a certificate chain forwarded by a bouncer, without a trust decision.
	func presentChain(_ trust: SecTrust, title: String, closeButton: String) {
		TrustPanelPresenter.present(
			in: NSApp.mainWindow,
			body: "",
			title: title,
			defaultButton: closeButton,
			alternateButton: nil,
			trust: trust
		)
	}

	/// Shows the negotiated protocol, cipher and certificate chain.
	func presentSummary(for information: SecureConnectionInformation) {
		let cipherSuite = information.cipherSuite

		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else { return }

		let cipherStatus: PromptCipherStatus = SecureTransportSupport.isCipherSuiteLegacy(cipherSuite)
			? .deprecated
			: .current
		let summary = PromptStrings.TransportSecurity.cipherSummary(
			policyName: SecureTransportSupport.description(forProtocolType: information.protocolVersion),
			cipherSuite: SecureTransportSupport.description(forCipherSuite: cipherSuite),
			status: cipherStatus
		)
		var body = PromptStrings.TransportSecurity.certificateSummary(
			policyName: policyName,
			cipherSummary: summary
		)

		if let failure = information.trustFailureDescription {
			body += PromptStrings.TransportSecurity.trustFailure(failure)
		}

		TrustPanelPresenter.present(
			in: NSApp.keyWindow,
			body: body,
			title: PromptStrings.TransportSecurity.encryptedConnectionTitle(policyName: policyName),
			defaultButton: PromptStrings.Action.close,
			alternateButton: nil,
			trust: trust
		)
	}
}
