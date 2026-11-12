// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A certificate the user decided to trust for one nickname on one network.
nonisolated struct DCCPeerPin: Codable, Hashable, Sendable {
	let fingerprint: DCCCertificateFingerprint
	/// Shown beside the fingerprint; never compared.
	let sha1: Data
	/// The nickname as it was written when the certificate was pinned. The
	/// store files the pin under its casefolded form.
	let nickname: String
	let subjectSummary: String?
	let firstTrusted: Date
	var lastSeen: Date
	/// The services account the peer was logged in as when pinned, if the
	/// server said. Shown, never decided on.
	let account: String?

	init(certificate: DCCPeerCertificate, nickname: String, account: String?, at date: Date) {
		fingerprint = certificate.fingerprint
		sha1 = certificate.sha1
		self.nickname = nickname
		subjectSummary = certificate.subjectSummary
		firstTrusted = date
		lastSeen = date
		self.account = account
	}
}

/// What a secure DCC connection's peer certificate means for whether it may
/// go ahead.
nonisolated enum DCCPeerTrustVerdict: Equatable, Sendable {
	/// The certificate matches a pin, so the connection proceeds unasked.
	case pinned(DCCPeerPin)
	/// Nothing is pinned for this nickname yet: the user is asked whether to
	/// trust it, once or from now on.
	case firstUse
	/// Pins exist and none matches. Someone may be impersonating the peer, so
	/// this never proceeds without the user replacing the pin, and automatic
	/// flows never proceed at all.
	case changed(previous: [DCCPeerPin])
	/// The peer presented no certificate, which only a TLS client can do, and
	/// none is saved for the nickname. The connection is encrypted but nobody
	/// is verified.
	case unidentified
	/// The peer presented no certificate although one is saved for the
	/// nickname. The user is asked every time, and automatic flows never
	/// proceed unasked.
	case unidentifiedDespitePins(saved: [DCCPeerPin])
	/// The peer presented no certificate and the user requires one.
	case certificateRequired
	/// The certificate's key is too weak to be worth pinning.
	case weakKey(DCCPeerCertificate.KeyAlgorithm, bits: Int)
}

/// The trust-on-first-use decision table for secure DCC peers.
nonisolated enum DCCPeerTrust {
	static func evaluate(
		presented certificate: DCCPeerCertificate?,
		pins: [DCCPeerPin],
		requirePeerCertificate: Bool
	) -> DCCPeerTrustVerdict {
		guard let certificate else {
			if requirePeerCertificate {
				return .certificateRequired
			}
			return pins.isEmpty ? .unidentified : .unidentifiedDespitePins(saved: pins)
		}
		guard certificate.keyStrength == .acceptable else {
			return .weakKey(certificate.keyAlgorithm, bits: certificate.keySize)
		}
		if let pin = pins.first(where: { $0.fingerprint == certificate.fingerprint }) {
			return .pinned(pin)
		}
		return pins.isEmpty ? .firstUse : .changed(previous: pins)
	}
}
