// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** What the user is asked about the peer's certificate, and what is done with
 the answer.

 The connection host blocks its handshake on that answer, so every path out of
 here answers exactly once — including the ones where the connection is going
 away before the user has looked at the panel. */
extension Connection {
	/// Where the user is asked about a certificate. Reached through the
	/// environment so that nothing here presents AppKit itself.
	private var trustPanel: CertificateTrustPanel? {
		session?.environment.services.certificateTrust
	}

	func openSecuredConnectionCertificateModal() {
		exportSecureConnectionInformation { [weak self] information in
			/* The hop comes first, and the `SecTrust` is rebuilt on the other
			 side of it. What crosses is `SecureConnectionInformation`, which is
			 `Sendable` and already carries the DER chain. */
			Task { @MainActor [weak self] in
				self?.trustPanel?.presentSummary(for: information)
			}
		}
	}

	/// Puts a certificate the system would not vouch for in front of the user.
	/// Called from the event loop in Connection.swift.
	func openInsecureCertificateTrustPanel(_ response: @escaping TrustDecisionHandler) {
		guard terminal == false, isDisconnecting == false, session?.isTerminating == false,
		      let trustPanel, trustPanel.reserve()
		else {
			response(false)
			return
		}

		trustResponse = response

		/* Reaching this panel means the chain did not validate. Whatever the
		 user answers, this connection is no longer one whose certificate the
		 system vouched for, and policies that outlive it must not be taken
		 from it. */
		noteCertificateTrustOverridden()

		exportSecureConnectionInformation { [weak self] information in
			Task { @MainActor [weak self] in
				/* Only a deallocated connection cannot answer, and that has
				 already invalidated the service the handshake belongs to. */
				guard let self else { return }

				guard terminal == false, isDisconnecting == false, session?.socket === self else {
					trustPanel.cancelReservation()
					resolveTrust(false)
					return
				}

				guard trustResponse != nil else {
					trustPanel.cancelReservation()
					return
				}

				let presented = trustPanel.present(for: information) { [weak self] trusted in
					guard let self else { return }

					resolveTrust(trusted && terminal == false && isDisconnecting == false)
				}

				if presented == false {
					resolveTrust(false)
				}
			}
		}
	}

	/// Answers whatever was waiting on the panel with a refusal and takes it
	/// down: the connection is going away, and the host is still blocked.
	/// Called from the close and disconnect paths in Connection.swift.
	func closeInsecureCertificateTrustPanel() {
		resolveTrust(false)
		trustPanel?.close()
	}

	private func resolveTrust(_ trusted: Bool) {
		let response = trustResponse
		trustResponse = nil
		response?(trusted)
	}

	private func exportSecureConnectionInformation(_ receiver: @escaping SecureConnectionInformationReceiver) {
		remoteObjectProxy()?.exportSecureConnectionInformation(receiver)
	}
}
