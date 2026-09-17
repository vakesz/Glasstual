// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Network

/// What the connection host knows about the TLS session it negotiated.
///
/// This used to reach the app as five positional arguments of one reply block,
/// where a `nil` policy name in the first position was the only signal that
/// the other four meant nothing. As one value the "nothing negotiated" case is
/// a single `nil`, and the array no longer crosses the boundary loose.
///
/// The explicit Objective-C name is the archive's: `Sources/Shared` is compiled
/// into each target, so without one the class is `Glasstual.…` on one side of
/// the connection and `IRC_Connection_Host.…` on the other, and the decode
/// fails.
@objc(RCMSecureConnectionInformation)
final nonisolated class SecureConnectionInformation: // nonisolated: immutable
	NSObject, NSSecureCoding, Sendable
{
	/// The name the certificate chain was evaluated against.
	let policyName: String?

	/// Why the chain failed to validate, when it did.
	let trustFailureDescription: String?

	/// The DER-encoded chain, leaf first.
	let certificateChain: [Data]

	private let protocolVersionRawValue: UInt16
	private let cipherSuiteRawValue: UInt16

	var protocolVersion: tls_protocol_version_t {
		tls_protocol_version_t(rawValue: protocolVersionRawValue) ?? tlsProtocolVersionUnknown
	}

	var cipherSuite: tls_ciphersuite_t {
		tls_ciphersuite_t(rawValue: cipherSuiteRawValue) ?? tlsCipherSuiteUnknown
	}

	init(
		policyName: String?,
		protocolVersion: tls_protocol_version_t,
		cipherSuite: tls_ciphersuite_t,
		certificateChain: [Data],
		trustFailureDescription: String?
	) {
		self.policyName = policyName
		protocolVersionRawValue = protocolVersion.rawValue
		cipherSuiteRawValue = cipherSuite.rawValue
		self.certificateChain = certificateChain
		self.trustFailureDescription = trustFailureDescription

		super.init()
	}

	/// The answer for a connection that never negotiated TLS.
	static var none: SecureConnectionInformation {
		SecureConnectionInformation(
			policyName: nil,
			protocolVersion: tlsProtocolVersionUnknown,
			cipherSuite: tlsCipherSuiteUnknown,
			certificateChain: [],
			trustFailureDescription: nil
		)
	}

	// MARK: - NSSecureCoding

	static var supportsSecureCoding: Bool {
		true
	}

	private enum CodingKey {
		static let policyName = "policyName"
		static let protocolVersion = "protocolVersion"
		static let cipherSuite = "cipherSuite"
		static let certificateChain = "certificateChain"
		static let trustFailureDescription = "trustFailureDescription"
	}

	init?(coder: NSCoder) {
		policyName = coder.decodeObject(of: NSString.self, forKey: CodingKey.policyName) as String?
		trustFailureDescription = coder.decodeObject(
			of: NSString.self,
			forKey: CodingKey.trustFailureDescription
		) as String?
		let chain = coder.decodeObject(
			of: [NSArray.self, NSData.self],
			forKey: CodingKey.certificateChain
		) as? [Data]
		certificateChain = chain ?? []
		protocolVersionRawValue = UInt16(
			clamping: coder.decodeInteger(forKey: CodingKey.protocolVersion)
		)
		cipherSuiteRawValue = UInt16(clamping: coder.decodeInteger(forKey: CodingKey.cipherSuite))

		super.init()
	}

	func encode(with coder: NSCoder) {
		coder.encode(policyName as NSString?, forKey: CodingKey.policyName)
		coder.encode(trustFailureDescription as NSString?, forKey: CodingKey.trustFailureDescription)
		coder.encode(certificateChain as NSArray, forKey: CodingKey.certificateChain)
		coder.encode(Int(protocolVersionRawValue), forKey: CodingKey.protocolVersion)
		coder.encode(Int(cipherSuiteRawValue), forKey: CodingKey.cipherSuite)
	}
}
