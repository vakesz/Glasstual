// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation

/// The SASL ECDSA key the Identity pane edits. Every change is a pending
/// keychain edit on the configuration, so it is written when the sheet is saved
/// and discarded when it is cancelled, like the passwords beside it.
extension ServerPropertiesModel {
	/// The key as the keychain stores it: an unflushed edit if there is one, and
	/// otherwise what the one keychain read found.
	private var storedSigningKey: String? {
		config.pendingSASLSigningKey.value(orStored: loadedSecrets[config.saslSigningKeyKeychainItem])
	}

	var signingKey: P256.Signing.PrivateKey? {
		storedSigningKey.flatMap(ECDSASigningKey.privateKey(fromStored:))
	}

	var hasSigningKey: Bool {
		signingKey != nil
	}

	/// The public key a person registers with the network's account service.
	var signingPublicKey: String? {
		signingKey.map(ECDSASigningKey.registrationPublicKey(of:))
	}

	func generateSigningKey() {
		installSigningKey(ECDSASigningKey.generate())
	}

	func removeSigningKey() {
		signingKeyError = nil
		config.pendingSASLSigningKey = .cleared
	}

	/// Replaces the key with the one in `data`, reporting why it could not.
	func importSigningKey(from data: Data) {
		do {
			try installSigningKey(ECDSASigningKey.privateKey(importing: data))
		} catch {
			signingKeyError = String(localized: .ServerProperties.saslEcdsaImportUnsupported)
		}
	}

	/// Reads the file the importer returned and replaces the key with it.
	func importSigningKey(fromFile result: Result<URL, any Error>) {
		guard case let .success(url) = result else {
			if case let .failure(error) = result, (error as? CocoaError)?.code != .userCancelled {
				signingKeyError = String(localized: .ServerProperties.saslEcdsaImportUnreadable)
			}
			return
		}

		let scoped = url.startAccessingSecurityScopedResource()
		defer {
			if scoped {
				url.stopAccessingSecurityScopedResource()
			}
		}

		do {
			let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
			guard size <= ECDSASigningKey.maximumImportLength else {
				signingKeyError = String(localized: .ServerProperties.saslEcdsaImportUnsupported)
				return
			}
			try importSigningKey(from: Data(contentsOf: url))
		} catch {
			signingKeyError = String(localized: .ServerProperties.saslEcdsaImportUnreadable)
		}
	}

	private func installSigningKey(_ key: P256.Signing.PrivateKey) {
		signingKeyError = nil
		config.pendingSASLSigningKey = .set(ECDSASigningKey.storedRepresentation(of: key))
	}
}
