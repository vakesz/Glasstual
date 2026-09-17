// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os
import Security

/// The client side identity a connection presents, when one is configured.
///
/// A pure function of the configuration: the keychain lookup depends on nothing
/// else, so it is done where it is needed rather than cached on an object.
enum ClientSideCertificate {
	static func load(from config: ConnectionConfig) -> (identity: SecIdentity, certificate: SecCertificate)? {
		guard let certificateDataIn = config.identityClientSideCertificate else {
			return nil
		}

		var certificateObject: CFTypeRef?

		var status = SecItemCopyMatching(
			[
				kSecClass: kSecClassCertificate,
				kSecValuePersistentRef: certificateDataIn,
				kSecReturnRef: true,
			] as CFDictionary, &certificateObject
		)

		if status != errSecSuccess {
			ConnectionHostLog.connection.error("Client certificate lookup failed: \(status, privacy: .public)")

			return nil
		}

		guard let certificateObject,
		      CFGetTypeID(certificateObject) == SecCertificateGetTypeID()
		else {
			return nil
		}
		// Security exposes the typed certificate through a CFTypeRef result.
		let certificateRef = unsafeDowncast(certificateObject, to: SecCertificate.self)

		var identityRef: SecIdentity?

		status = SecIdentityCreateWithCertificate(nil, certificateRef, &identityRef)

		guard status == noErr, let identityRef else {
			ConnectionHostLog.connection.error("Client identity lookup failed: \(status, privacy: .public)")

			return nil
		}

		return (identity: identityRef, certificate: certificateRef)
	}
}
