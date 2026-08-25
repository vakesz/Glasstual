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

public let tls_protocol_version_unknown = tls_protocol_version_t(rawValue: 0)!
public let tls_ciphersuite_unknown = tls_ciphersuite_t(rawValue: 0)!

private enum CipherCollection: UInt {
	case `default` = 0
	case mozilla2015 = 1
	case mozilla2017 = 2
	case none = 100
}

@objc(RCMSecureTransport)
public final class SecureTransportSupport: NSObject {
	@objc public class var minimumProtocolType: UInt16 {
		0x0303
	}

	@objc(descriptionForProtocolType:)
	public class func description(forProtocol type: UInt16) -> String? {
		switch type {
		case 0x0303: "Transport Layer Security (TLS), version 1.2"
		case 0x0304: "Transport Layer Security (TLS), version 1.3"
		case 0xFEFD: "Datagram Transport Layer Security (DTLS), version 1.2"
		default: "Unknown"
		}
	}

	@objc(descriptionForCipherSuite:)
	public class func description(forCipherSuite suite: UInt16) -> String? {
		description(forCipherSuite: suite, withProtocol: false)
	}

	@objc(descriptionForCipherSuite:withProtocol:)
	public class func description(forCipherSuite suite: UInt16, withProtocol: Bool) -> String? {
		guard let name = cipherNames[suite] else { return "Unknown" }
		return withProtocol && (0x1301 ... 0x1303).contains(suite) ? "\(name) (TLS 1.3)" : name
	}

	@objc(isCipherSuiteDeprecated:)
	public class func isCipherSuiteDeprecated(_ suite: UInt16) -> Bool {
		deprecatedSuites.contains(suite)
	}

	@objc(descriptionsForCipherListCollection:)
	public class func descriptions(forCipherListCollection collection: UInt) -> [String] {
		descriptions(forCipherListCollection: collection, withProtocol: false)
	}

	@objc(descriptionsForCipherListCollection:withProtocol:)
	public class func descriptions(forCipherListCollection collection: UInt, withProtocol: Bool) -> [String] {
		cipherSuites(inCollection: collection).map { description(
			forCipherSuite: $0.uint16Value,
			withProtocol: withProtocol
		) ?? "Unknown" }
	}

	@objc(cipherSuitesInCollection:)
	public class func cipherSuites(inCollection collection: UInt) -> [NSNumber] {
		let suites: [UInt16] = switch CipherCollection(rawValue: collection) ?? .default {
		case .none:
			[]
		case .mozilla2015:
			mozilla2015Suites
		case .default, .mozilla2017:
			modernSuites
		}
		return suites.map(NSNumber.init(value:))
	}

	@objc(cipherSuitesInCollection:includeDeprecated:)
	public class func cipherSuites(inCollection collection: UInt, includeDeprecated: Bool) -> [NSNumber] {
		guard includeDeprecated else { return cipherSuites(inCollection: collection) }
		var suites = cipherSuites(inCollection: collection).map(\.uint16Value)
		suites.append(contentsOf: [0x009F, 0x009E])
		suites.append(contentsOf: deprecatedSuites)
		return suites.map(NSNumber.init(value:))
	}

	@objc(appendCipherSuitesInCollection:includeDeprecated:toOptions:)
	public class func appendCipherSuites(
		inCollection collection: UInt,
		includeDeprecated: Bool,
		to options: sec_protocol_options_t
	) {
		let suites = cipherSuites(inCollection: collection, includeDeprecated: includeDeprecated).map(\.uint16Value)
		for suite in suites {
			guard let value = tls_ciphersuite_t(rawValue: suite) else { continue }
			sec_protocol_options_append_tls_ciphersuite(options, value)
		}
	}

	@objc(isTLSError:)
	public class func isTLSError(_ error: NSError) -> Bool {
		error.domain == "kCFStreamErrorDomainSSL"
	}

	@objc(descriptionForErrorCode:)
	public class func description(forErrorCode originalCode: Int) -> String {
		let code = (-9890 ... -9800).contains(originalCode) && !(-9889 ... -9886).contains(originalCode)
			? originalCode : -9999
		let bundle = Bundle(for: self)
		let heading = bundle.localizedString(forKey: "heading", value: nil, table: "SecureTransportErrorCodes")
		let reason = bundle.localizedString(forKey: String(code), value: nil, table: "SecureTransportErrorCodes")
		return String(format: heading, reason, code)
	}

	@objc(descriptionForBadCertificateErrorCode:)
	public class func description(forBadCertificateErrorCode code: Int) -> String? {
		isBadCertificateErrorCode(code) ? description(forErrorCode: code) : nil
	}

	@objc(isBadCertificateErrorCode:)
	public class func isBadCertificateErrorCode(_ code: Int) -> Bool {
		badCertificateErrors.contains(code)
	}

	@objc(trustFromCertificateChain:withPolicyName:)
	public class func trust(fromCertificateChain chain: [Data], policyName: String) -> SecTrust? {
		let certificates = chain.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
		guard certificates.isEmpty == false else { return nil }
		let policy = SecPolicyCreateSSL(true, policyName as CFString)
		var trust: SecTrust?
		guard SecTrustCreateWithCertificates(certificates as CFArray, policy, &trust) == errSecSuccess
		else { return nil }
		return trust
	}

	@objc(certificatesInTrust:)
	public class func certificates(in trust: SecTrust) -> [Data]? {
		guard let certificates = SecTrustCopyCertificateChain(trust) as? [SecCertificate] else { return nil }
		return certificates.map { SecCertificateCopyData($0) as Data }
	}

	@objc(policyNameInTrust:)
	public class func policyName(in trust: SecTrust) -> String? {
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
