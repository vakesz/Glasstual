// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server properties SASL ECDSA key")
struct ServerPropertiesSigningKeyTests {
	private static func model() -> ServerPropertiesModel {
		ServerPropertiesModel(config: ServerConfig(connectionName: "Keyed"))
	}

	@Test("Generating a key stages it as a pending keychain edit and shows its public key")
	func generateStagesAKey() throws {
		let model = Self.model()
		#expect(model.hasSigningKey == false)

		model.generateSigningKey()

		let key = try #require(model.signingKey)
		#expect(model.config.pendingSASLSigningKey == .set(ECDSASigningKey.storedRepresentation(of: key)))
		#expect(model.signingPublicKey == ECDSASigningKey.registrationPublicKey(of: key))
	}

	@Test("Importing a PEM replaces the key, and a bad file leaves it alone with an error")
	func importReplacesOrReports() {
		let model = Self.model()
		model.generateSigningKey()
		let before = model.config.pendingSASLSigningKey
		let other = ECDSASigningKey.generate()

		model.importSigningKey(from: Data("nonsense".utf8))
		#expect(model.signingKeyError != nil)
		#expect(model.config.pendingSASLSigningKey == before)

		model.importSigningKey(from: Data(other.pemRepresentation.utf8))
		#expect(model.signingKeyError == nil)
		#expect(model.signingKey?.rawRepresentation == other.rawRepresentation)
	}

	@Test("Removing the key clears it through the keychain edit")
	func removeClearsTheKey() {
		let model = Self.model()
		model.generateSigningKey()

		model.removeSigningKey()

		#expect(model.config.pendingSASLSigningKey == .cleared)
		#expect(model.hasSigningKey == false)
		#expect(model.signingPublicKey == nil)
	}

	@Test("A stored key that the keychain read found is shown until it is edited")
	func storedKeyIsShown() {
		let model = Self.model()
		let key = ECDSASigningKey.generate()
		model.loadedSecrets[model.config.saslSigningKeyKeychainItem] = ECDSASigningKey.storedRepresentation(of: key)

		#expect(model.signingKey?.rawRepresentation == key.rawRepresentation)
		#expect(model.config.pendingSASLSigningKey == .unchanged)

		model.removeSigningKey()
		#expect(model.hasSigningKey == false)
	}
}
