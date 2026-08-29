/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Network

/// What the connection host knows about the TLS session it negotiated.
///
/// This used to reach the app as five positional arguments of one reply block,
/// where a `nil` policy name in the first position was the only signal that
/// the other four meant nothing. As one value the "nothing negotiated" case is
/// a single `nil`, and the array no longer crosses the boundary loose.
@objc(RCMSecureConnectionInformation)
public final nonisolated class SecureConnectionInformation: NSObject, NSSecureCoding, Sendable { // nonisolated: value
	/// The name the certificate chain was evaluated against.
	@objc public let policyName: String?

	/// Why the chain failed to validate, when it did.
	@objc public let trustFailureDescription: String?

	/// The DER-encoded chain, leaf first.
	@objc public let certificateChain: [Data]

	private let protocolVersionRawValue: UInt16
	private let cipherSuiteRawValue: UInt16

	public var protocolVersion: tls_protocol_version_t {
		tls_protocol_version_t(rawValue: protocolVersionRawValue) ?? tlsProtocolVersionUnknown
	}

	public var cipherSuite: tls_ciphersuite_t {
		tls_ciphersuite_t(rawValue: cipherSuiteRawValue) ?? tlsCipherSuiteUnknown
	}

	public init(
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
	public static var none: SecureConnectionInformation {
		SecureConnectionInformation(
			policyName: nil,
			protocolVersion: tlsProtocolVersionUnknown,
			cipherSuite: tlsCipherSuiteUnknown,
			certificateChain: [],
			trustFailureDescription: nil
		)
	}

	// MARK: - NSSecureCoding

	public static var supportsSecureCoding: Bool {
		true
	}

	private enum CodingKey {
		static let policyName = "policyName"
		static let protocolVersion = "protocolVersion"
		static let cipherSuite = "cipherSuite"
		static let certificateChain = "certificateChain"
		static let trustFailureDescription = "trustFailureDescription"
	}

	public init?(coder: NSCoder) {
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

	public func encode(with coder: NSCoder) {
		coder.encode(policyName as NSString?, forKey: CodingKey.policyName)
		coder.encode(trustFailureDescription as NSString?, forKey: CodingKey.trustFailureDescription)
		coder.encode(certificateChain as NSArray, forKey: CodingKey.certificateChain)
		coder.encode(Int(protocolVersionRawValue), forKey: CodingKey.protocolVersion)
		coder.encode(Int(cipherSuiteRawValue), forKey: CodingKey.cipherSuite)
	}
}
