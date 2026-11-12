// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("DCC peer trust decision")
struct DCCPeerTrustTests {
	private static func certificate() throws -> DCCPeerCertificate {
		try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
	}

	private static func pin(_ certificate: DCCPeerCertificate) -> DCCPeerPin {
		DCCPeerPin(certificate: certificate, nickname: "peer", account: nil, at: .now)
	}

	@Test("No certificate and nothing saved is unidentified, or refused when one is required", arguments: [false, true])
	func noCertificate(required: Bool) {
		let verdict = DCCPeerTrust.evaluate(presented: nil, pins: [], requirePeerCertificate: required)
		#expect(verdict == (required ? .certificateRequired : .unidentified))
	}

	@Test("No certificate from a nickname with one saved is asked about, or refused when one is required", arguments: [false, true])
	func noCertificateDespitePins(required: Bool) throws {
		let pins = try [Self.pin(Self.certificate())]
		let verdict = DCCPeerTrust.evaluate(presented: nil, pins: pins, requirePeerCertificate: required)
		#expect(verdict == (required ? .certificateRequired : .unidentifiedDespitePins(saved: pins)))
	}

	@Test("A certificate with no pins is first use")
	func firstUse() throws {
		let verdict = try DCCPeerTrust.evaluate(presented: Self.certificate(), pins: [], requirePeerCertificate: true)
		#expect(verdict == .firstUse)
	}

	@Test("A matching pin among several is pinned")
	func pinned() throws {
		let presented = try Self.certificate()
		let pins = try [Self.pin(Self.certificate()), Self.pin(presented)]
		let verdict = DCCPeerTrust.evaluate(presented: presented, pins: pins, requirePeerCertificate: false)
		#expect(verdict == .pinned(pins[1]))
	}

	@Test("Pins that do not match mean the certificate changed")
	func changed() throws {
		let pins = try [Self.pin(Self.certificate())]
		let verdict = try DCCPeerTrust.evaluate(presented: Self.certificate(), pins: pins, requirePeerCertificate: false)
		#expect(verdict == .changed(previous: pins))
	}

	@Test("A weak key is refused even when it is pinned")
	func weakKey() throws {
		let weak = try #require(DCCPeerCertificate(der: PeerCertificateFixture.rsa(bits: 1024)))
		let verdict = DCCPeerTrust.evaluate(presented: weak, pins: [Self.pin(weak)], requirePeerCertificate: false)
		#expect(verdict == .weakKey(.rsa, bits: 1024))
	}
}
