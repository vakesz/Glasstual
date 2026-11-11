// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server properties SASL mechanism")
struct ServerPropertiesSASLMechanismTests {
	private static func model() -> ServerPropertiesModel {
		ServerPropertiesModel(config: ServerConfig(connectionName: "Mechanism"))
	}

	@Test("The picker writes the preference, and Automatic clears it with the only switch")
	func choiceWritesAndClears() {
		let model = Self.model()
		#expect(model.saslMechanismChoice == .automatic)

		model.saslMechanismChoice = .mechanism(.scramSHA256)
		model.config.saslUsesOnlyPreferredMechanism = true
		#expect(model.config.saslMechanismPreference == .scramSHA256)
		#expect(model.saslMechanismChoice == .mechanism(.scramSHA256))

		model.saslMechanismChoice = .automatic
		#expect(model.config.saslMechanismPreference == nil)
		#expect(model.config.saslUsesOnlyPreferredMechanism == false)
	}

	@Test("A mechanism with nothing to sign in with is warned about")
	func missingCredentialWarns() {
		let model = Self.model()
		#expect(model.saslMechanismWarning == nil)

		model.saslMechanismChoice = .mechanism(.external)
		let certificateWarning = String(localized: .ServerProperties.saslMechanismMissingCertificate)
		#expect(model.saslMechanismWarning?.hasPrefix(certificateWarning) == true)

		model.saslMechanismChoice = .mechanism(.ecdsaNIST256PChallenge)
		let keyWarning = String(localized: .ServerProperties.saslMechanismMissingSigningKey)
		#expect(model.saslMechanismWarning?.hasPrefix(keyWarning) == true)
		#expect(model.saslMechanismWarning?.hasSuffix(String(localized: .ServerProperties.saslMechanismMissingFallback)) == true)

		model.config.saslUsesOnlyPreferredMechanism = true
		#expect(model.saslMechanismWarning?.hasSuffix(String(localized: .ServerProperties.saslMechanismMissingOnly)) == true)
	}

	@Test("A mechanism whose credential is present is not warned about")
	func presentCredentialDoesNotWarn() {
		let model = Self.model()
		model.setSecretText("secret", for: .nicknamePassword)
		model.saslMechanismChoice = .mechanism(.plain)
		#expect(model.saslMechanismWarning == nil)

		model.config.usesSASL = false
		model.saslMechanismChoice = .mechanism(.external)
		#expect(model.saslMechanismWarning == nil)
	}
}
