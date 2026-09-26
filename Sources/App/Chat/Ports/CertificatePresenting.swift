// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Security

@MainActor
protocol CertificatePresenting: AnyObject {
	/// Reserves a prompt. A nil result leaves the caller responsible for refusing trust.
	func beginTrustRequest(decided: @escaping (Bool) -> Void) -> CertificateTrustRequest?
	func presentSummary(for information: SecureConnectionInformation)
	func presentChain(_ trust: SecTrust, title: String, closeButton: String)
}
