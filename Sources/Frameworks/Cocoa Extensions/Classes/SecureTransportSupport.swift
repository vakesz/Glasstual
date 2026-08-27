/* *********************************************************************
 *
 *            Copyright (c) 2024 Codeux Software, LLC
 *     Please see ACKNOWLEDGEMENT for additional information.
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
 *  * Neither the name of "Codeux Software, LLC", nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
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

/*
 Portions of the cipher-suite naming logic derive from Chromium's
 ssl_cipher_suite_names.cc.

 Copyright (c) 2013 The Chromium Authors. All rights reserved.

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are
 met:

  * Redistributions of source code must retain the above copyright
    notice, this list of conditions and the following disclaimer.
  * Redistributions in binary form must reproduce the above copyright
    notice, this list of conditions and the following disclaimer in the
    documentation and/or other materials provided with the distribution.
  * Neither the name of Google Inc. nor the names of its contributors may
    be used to endorse or promote products derived from this software
    without specific prior written permission.

 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS
 IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
 THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 EXEMPLARY, OR CONSEQUENTIAL DAMAGES INCLUDING PROCUREMENT OF SUBSTITUTE
 GOODS OR SERVICES, LOSS OF USE, DATA, OR PROFITS, OR BUSINESS INTERRUPTION
 HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 LIABILITY, OR TORT INCLUDING NEGLIGENCE OR OTHERWISE ARISING IN ANY WAY OUT
 OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 DAMAGE.
 */

import Foundation
import Security

public let tlsProtocolVersionUnknown = tls_protocol_version_t(rawValue: 0)!
public let tlsCipherSuiteUnknown = tls_ciphersuite_t(rawValue: 0)!

@objc
public enum CipherSuiteCollection: UInt, Sendable {
	case `default` = 0
	case mozilla2015 = 1
	case mozilla2017 = 2
	case none = 100
}

public enum SecureTransportSupport {
	public static var minimumProtocolType: tls_protocol_version_t {
		.TLSv12
	}

	public static func description(forProtocolType type: tls_protocol_version_t) -> String? {
		switch type.rawValue {
		case 0x0303: "Transport Layer Security (TLS), version 1.2"
		case 0x0304: "Transport Layer Security (TLS), version 1.3"
		case 0xFEFD: "Datagram Transport Layer Security (DTLS), version 1.2"
		default: "Unknown"
		}
	}

	public static func description(forCipherSuite suite: tls_ciphersuite_t) -> String? {
		description(forCipherSuite: suite, withProtocol: false)
	}

	public static func description(forCipherSuite suite: tls_ciphersuite_t, withProtocol: Bool) -> String? {
		guard let name = cipherNames[suite.rawValue] else { return "Unknown" }
		return withProtocol && (0x1301 ... 0x1303).contains(suite.rawValue) ? "\(name) (TLS 1.3)" : name
	}

	public static func isCipherSuiteDeprecated(_ suite: tls_ciphersuite_t) -> Bool {
		deprecatedSuites.contains(suite.rawValue)
	}

	public static func descriptions(forCipherListCollection collection: CipherSuiteCollection) -> [String] {
		descriptions(forCipherListCollection: collection, withProtocol: false)
	}

	public static func descriptions(forCipherListCollection collection: CipherSuiteCollection,
	                                withProtocol: Bool) -> [String]
	{
		cipherSuites(inCollection: collection).map { description(
			forCipherSuite: tls_ciphersuite_t(rawValue: $0.uint16Value)!,
			withProtocol: withProtocol
		) ?? "Unknown" }
	}

	public static func cipherSuites(inCollection collection: CipherSuiteCollection) -> [NSNumber] {
		let suites: [UInt16] = switch collection {
		case .none:
			[]
		case .mozilla2015:
			mozilla2015Suites
		case .default, .mozilla2017:
			modernSuites
		}
		return suites.map(NSNumber.init(value:))
	}

	public static func cipherSuites(inCollection collection: CipherSuiteCollection,
	                                includeDeprecated: Bool) -> [NSNumber]
	{
		guard includeDeprecated else { return cipherSuites(inCollection: collection) }
		var suites = cipherSuites(inCollection: collection).map(\.uint16Value)
		suites.append(contentsOf: [0x009F, 0x009E])
		suites.append(contentsOf: deprecatedSuites)
		return suites.map(NSNumber.init(value:))
	}

	public static func appendCipherSuites(
		inCollection collection: CipherSuiteCollection,
		includeDeprecated: Bool,
		to options: sec_protocol_options_t
	) {
		let suites = cipherSuites(inCollection: collection, includeDeprecated: includeDeprecated).map(\.uint16Value)
		for suite in suites {
			guard let value = tls_ciphersuite_t(rawValue: suite) else { continue }
			sec_protocol_options_append_tls_ciphersuite(options, value)
		}
	}

	public static func isTLSError(_ error: NSError) -> Bool {
		error.domain == "kCFStreamErrorDomainSSL"
	}

	public static func description(forErrorCode originalCode: Int) -> String {
		SecureTransportErrorLocalization.description(for: SecureTransportErrorCode(normalizing: originalCode))
	}

	public static func description(forBadCertificateErrorCode code: Int) -> String? {
		isBadCertificateErrorCode(code) ? description(forErrorCode: code) : nil
	}

	public static func isBadCertificateErrorCode(_ code: Int) -> Bool {
		badCertificateErrors.contains(code)
	}

	public static func trust(fromCertificateChain chain: [Data], policyName: String) -> SecTrust? {
		let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
		guard certificates.isEmpty == false else { return nil }
		let policy = SecPolicyCreateSSL(true, policyName as CFString)
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess
		else { return nil }
		return trust
	}

	public static func certificates(in trust: SecTrust) -> [Data]? {
		guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return nil }
		return certificates.map { SecCertificateCopyData($0) as Data }
	}

	public static func policyName(in trust: SecTrust) -> String? {
		var policies: CFArray?
		guard SecTrustCopyPolicies(trust, &policies) == errSecSuccess,
		      let policies = policies as? [SecPolicy]
		else { return nil }
		for policy in policies {
			guard let properties = SecPolicyCopyProperties(policy) as? [CFString: Any],
			      let name = properties[kSecPolicyName] as? String
			else { continue }
			return name
		}
		return nil
	}

	private static let modernSuites: [UInt16] = [
		0x1302, 0x1301, 0x1303,
		0xC02C, 0xC030, 0xCCA9, 0xCCA8, 0xC02B, 0xC02F,
		0xC024, 0xC028, 0xC023, 0xC027,
	]

	private static let mozilla2015Suites: [UInt16] = [
		0xC02F, 0xC02B, 0xC030, 0xC02C, 0x009E, 0x00A2, 0x00A3, 0x009F,
		0xC027, 0xC023, 0xC013, 0xC009, 0xC028, 0xC024, 0xC014, 0xC00A,
		0x0067, 0x0033, 0x0040, 0x006B, 0x0038, 0x0039,
	]

	private static let deprecatedSuites: [UInt16] = [0x009C, 0x009D, 0x003C, 0x003D, 0x002F, 0x0035]

	private static let cipherNames: [UInt16: String] = [
		0x1301: "AES-128-GCM", 0x1302: "AES-256-GCM", 0x1303: "CHACHA20-POLY1305",
		0xC02B: "ECDHE-ECDSA-AES-128-GCM", 0xC02C: "ECDHE-ECDSA-AES-256-GCM",
		0xC02F: "ECDHE-RSA-AES-128-GCM", 0xC030: "ECDHE-RSA-AES-256-GCM",
		0xCCA8: "ECDHE-RSA-CHACHA20-POLY1305", 0xCCA9: "ECDHE-ECDSA-CHACHA20-POLY1305",
		0xC023: "ECDHE-ECDSA-AES-128-CBC-SHA256", 0xC024: "ECDHE-ECDSA-AES-256-CBC-SHA384",
		0xC027: "ECDHE-RSA-AES-128-CBC-SHA256", 0xC028: "ECDHE-RSA-AES-256-CBC-SHA384",
		0xC009: "ECDHE-ECDSA-AES-128-CBC-SHA1", 0xC00A: "ECDHE-ECDSA-AES-256-CBC-SHA1",
		0xC013: "ECDHE-RSA-AES-128-CBC-SHA1", 0xC014: "ECDHE-RSA-AES-256-CBC-SHA1",
		0x009E: "DHE-RSA-AES-128-GCM", 0x009F: "DHE-RSA-AES-256-GCM",
		0x00A2: "DHE-DSS-AES-128-GCM", 0x00A3: "DHE-DSS-AES-256-GCM",
		0x0067: "DHE-RSA-AES-128-CBC-SHA256", 0x006B: "DHE-RSA-AES-256-CBC-SHA256",
		0x0033: "DHE-RSA-AES-128-CBC-SHA1", 0x0039: "DHE-RSA-AES-256-CBC-SHA1",
		0x0040: "DHE-DSS-AES-128-CBC-SHA256", 0x0038: "DHE-DSS-AES-256-CBC-SHA1",
		0x009C: "RSA-AES-128-GCM", 0x009D: "RSA-AES-256-GCM",
		0x003C: "RSA-AES-128-CBC-SHA256", 0x003D: "RSA-AES-256-CBC-SHA256",
		0x002F: "RSA-AES-128-CBC-SHA1", 0x0035: "RSA-AES-256-CBC-SHA1",
	]

	private static let badCertificateErrors: Set<Int> = [
		-9808, -9812, -9814, -9825, -9827, -9828, -9829,
		-9813, -9816, -9826, -9830, -9831, -9843,
	]
}

private struct SecureTransportErrorCode: Sendable {
	let value: Int

	init(normalizing originalValue: Int) {
		value = (-9890 ... -9800).contains(originalValue) && !(-9889 ... -9886).contains(originalValue)
			? originalValue
			: -9999
	}

	var localizationKey: String {
		String(value)
	}
}

private enum SecureTransportErrorLocalization {
	static func description(for code: SecureTransportErrorCode) -> String {
		let bundle = Bundle(for: SecureTransportLocalizationBundleToken.self)
		let reason = bundle.localizedString(
			forKey: code.localizationKey,
			value: nil,
			table: "SecureTransportErrorCodes"
		)
		let resource = LocalizedStringResource.SecureTransportErrorCodes.errorDescription(reason, code.value)
		let format = bundle.localizedString(forKey: resource.key, value: nil, table: resource.table)
		return String(format: format, reason, code.value)
	}
}

private final class SecureTransportLocalizationBundleToken {}
