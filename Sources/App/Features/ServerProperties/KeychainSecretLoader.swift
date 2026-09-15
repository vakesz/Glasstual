/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Security

/// The client-side certificate a connection sends, as the Client Certificate
/// pane shows it.
struct ClientCertificateDetails: Equatable, Sendable {
	let commonName: String
	let sha512: String
	let sha256: String
	let sha1: String
}

/** Reads keychain secrets away from the main actor.

 Every `KeychainItem.password` is a synchronous `SecItemCopyMatching`, and a
 sheet needs several at once: read them together, off the main actor, and let
 the sheet cache the answers for as long as it is open. */
nonisolated enum KeychainSecretLoader { // nonisolated: value
	@concurrent
	static func passwords(for items: [KeychainItem]) async -> [KeychainItem: String] {
		var passwords: [KeychainItem: String] = [:]

		for item in Set(items) {
			if let password = item.password {
				passwords[item] = password
			}
		}

		return passwords
	}

	/// The name and fingerprints of the certificate a persistent keychain
	/// reference names, or nil when the keychain no longer has it.
	@concurrent
	static func certificate(for reference: Data) async -> ClientCertificateDetails? {
		let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValuePersistentRef: reference,
		                              kSecReturnRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      let result, CFGetTypeID(result) == SecCertificateGetTypeID() else { return nil }
		let certificate = unsafeDowncast(result, to: SecCertificate.self)
		var commonNameReference: CFString?
		guard SecCertificateCopyCommonName(certificate, &commonNameReference) == errSecSuccess,
		      let commonName = commonNameReference as String? else { return nil }
		let data = SecCertificateCopyData(certificate) as Data
		return ClientCertificateDetails(
			commonName: commonName,
			sha512: (data as NSData).textualSha512.uppercased(),
			sha256: (data as NSData).textualSha256.uppercased(),
			sha1: (data as NSData).textualSha1.uppercased()
		)
	}
}
