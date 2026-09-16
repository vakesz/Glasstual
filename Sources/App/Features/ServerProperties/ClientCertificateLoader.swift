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

/// Loads certificate choices and details for Server Properties.
nonisolated enum ClientCertificateLoader { // nonisolated: value
	/// Transfers newly created, non-Sendable identity handles exclusively to
	/// the caller. The native picker becomes their only owner after this hop.
	@concurrent
	static func identities() async -> sending [SecIdentity] {
		guard !Task.isCancelled else { return [] }
		let query: [CFString: Any] = [kSecClass: kSecClassIdentity, kSecMatchLimit: kSecMatchLimitAll,
		                              kSecReturnRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      !Task.isCancelled else { return [] }
		return result as? [SecIdentity] ?? []
	}

	@concurrent
	static func persistentReference(for certificate: SecCertificate) async -> Data? {
		guard !Task.isCancelled else { return nil }
		let query: [CFString: Any] = [kSecClass: kSecClassCertificate, kSecValueRef: certificate,
		                              kSecReturnPersistentRef: true]
		var result: CFTypeRef?
		guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
		      !Task.isCancelled else { return nil }
		return result as? Data
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
