// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

extension Connection {
	private var certificatePresenter: (any CertificatePresenting)? {
		session?.environment.services.certificates
	}

	private var canDecideCertificateTrust: Bool {
		!terminal && !isDisconnecting && session?.isTerminating == false && session?.socket === self
	}

	func showCertificateDetails() {
		remoteObjectProxy()?.exportSecureConnectionInformation { [weak self] information in
			Task { @MainActor [weak self] in
				self?.certificatePresenter?.presentSummary(for: information)
			}
		}
	}

	func requestCertificateTrust(_ response: @escaping TrustDecisionHandler) {
		guard
			canDecideCertificateTrust, certificateTrustRequest == nil,
			let request = certificatePresenter?.beginTrustRequest(decided: { [weak self] trusted in
				let canTrust = self?.canDecideCertificateTrust == true
				self?.certificateTrustRequest = nil
				response(trusted && canTrust)
			})
		else {
			response(false)
			return
		}
		certificateTrustRequest = request
		// User approval cannot turn a failed certificate validation into a trusted STS source.
		noteCertificateTrustOverridden()
		guard let proxy = remoteObjectProxy(errorHandler: { [weak request] _ in
			Task { @MainActor [weak request] in request?.cancel() }
		}) else {
			request.cancel()
			return
		}
		proxy.exportSecureConnectionInformation { [weak self, weak request] information in
			Task { @MainActor [weak self, weak request] in
				guard let request else { return }
				guard let self, canDecideCertificateTrust, certificateTrustRequest === request else {
					request.cancel()
					return
				}
				request.present(information)
			}
		}
	}

	func cancelCertificateTrustRequest() {
		let request = certificateTrustRequest
		certificateTrustRequest = nil
		request?.cancel()
	}
}
