/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation

/** Where a server's certificate is put in front of the user.

 Two panels, both `SFCertificateTrustPanel`: the one a failed chain raises,
 which the connection blocks on until the user answers, and the read-only
 summary the user asks for from the menu. The connection owns one of these and
 decides what to do with the answer; nothing about AppKit belongs on its side
 of that line.

 The failure panel runs before any window exists in the common case — a
 connection opened at launch — so it is presented application-modal rather than
 as a sheet. */
@MainActor
final class CertificateTrustPanel {
	private var panel: TrustPanelPresenter?

	/** Whether a panel is already up.

	 Assigned synchronously when one is asked for, because the certificate
	 export that precedes the panel is asynchronous and a second request can
	 arrive before the first one has a panel to check. */
	private(set) var isPresenting = false

	/// Reserves the panel for a request that is still exporting its
	/// certificate. `false` when one is already up or pending.
	func reserve() -> Bool {
		guard isPresenting == false else {
			return false
		}

		isPresenting = true

		return true
	}

	/// Gives the reservation back without having presented anything.
	func cancelReservation() {
		isPresenting = false
	}

	/** Asks the user whether to trust `information`'s chain anyway.

	 `false` means the chain could not be rebuilt and nothing was shown, which
	 is a refusal. Otherwise `decided` is called once with the answer. */
	func present(
		for information: SecureConnectionInformation,
		decided: @escaping (Bool) -> Void
	) -> Bool {
		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else {
			isPresenting = false

			return false
		}

		panel = TrustPanelPresenter.present(
			in: nil,
			body: PromptStrings.TransportSecurity.certificateFailureBody(serverName: policyName),
			title: PromptStrings.TransportSecurity.certificateFailureTitle(serverName: policyName),
			defaultButton: PromptStrings.TransportSecurity.invalidCertificateContinueButtonTitle,
			alternateButton: PromptStrings.Action.cancel,
			trust: trust
		) { [weak self] trusted in
			self?.panel = nil
			self?.isPresenting = false

			decided(trusted)
		}

		return true
	}

	/// Takes the panel down without an answer. The caller answers whatever was
	/// waiting on it.
	func close() {
		isPresenting = false
		panel?.dismiss()
		panel = nil
	}

	/// The read-only summary of a connection the system did vouch for: which
	/// protocol version and cipher suite it settled on, and the chain itself.
	static func presentSummary(for information: SecureConnectionInformation) {
		let cipherSuite = information.cipherSuite

		guard
			let policyName = information.policyName,
			let trust = SecureTransportSupport.trust(
				fromCertificateChain: information.certificateChain,
				policyName: policyName
			)
		else { return }

		let cipherStatus: PromptCipherStatus = SecureTransportSupport.isCipherSuiteDeprecated(cipherSuite)
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
