// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// The SASL mechanism picker's selection: Automatic, or one mechanism.
enum SASLMechanismChoice: Hashable {
	case automatic
	case mechanism(SASLMechanism)
}

extension ServerPropertiesModel {
	/// The stored preference as the picker selects it. Choosing Automatic also
	/// clears "Use Only This Mechanism", which has nothing to apply to then.
	var saslMechanismChoice: SASLMechanismChoice {
		get {
			config.saslMechanismPreference.map(SASLMechanismChoice.mechanism) ?? .automatic
		}
		set {
			switch newValue {
			case .automatic:
				config.saslMechanismPreference = nil
				config.saslUsesOnlyPreferredMechanism = false
			case let .mechanism(mechanism):
				config.saslMechanismPreference = mechanism
			}
		}
	}

	/// The credentials the sheet holds right now, typed-in edits included.
	var saslCredentialInventory: SASLCredentialInventory {
		SASLCredentialInventory(
			hasClientCertificate: config.identityClientSideCertificate != nil,
			externalMechanismDisabled: config.saslAuthenticationDisableExternalMechanism,
			hasPassword: secretText(.nicknamePassword).isEmpty == false,
			hasSigningKey: hasSigningKey
		)
	}

	/** Why the chosen mechanism cannot sign in with what is configured, and
	 what SASL does about it. `nil` when nothing is missing.

	 Asked over a trusted connection: the transport is not known until the
	 connection opens, and the sheet only says what is missing from it. */
	var saslMechanismWarning: String? {
		guard config.usesSASL, let mechanism = config.saslMechanismPreference else { return nil }
		let availability = SASLPolicy.availability(
			of: mechanism,
			inventory: saslCredentialInventory,
			transport: .verifiedTLS,
			withholdsAccountCredentials: false
		)
		guard case let .unavailable(reason) = availability, let missing = Self.missingCredentialText(reason) else {
			return nil
		}
		let consequence = config.saslUsesOnlyPreferredMechanism
			? String(localized: .ServerProperties.saslMechanismMissingOnly)
			: String(localized: .ServerProperties.saslMechanismMissingFallback)
		return "\(missing) \(consequence)"
	}

	private static func missingCredentialText(_ reason: SASLUnavailableReason) -> String? {
		switch reason {
		case .noClientCertificate: String(localized: .ServerProperties.saslMechanismMissingCertificate)
		case .externalDisabled: String(localized: .ServerProperties.saslMechanismExternalDisabled)
		case .noSigningKey: String(localized: .ServerProperties.saslMechanismMissingSigningKey)
		case .noPassword: String(localized: .ServerProperties.saslMechanismMissingPassword)
		case .clearTextNotPermitted, .accountCredentialsWithheld: nil
		}
	}
}

extension SASLMechanism {
	/// The picker's name for the mechanism. The wire name stays beside it.
	var localizedTitle: String {
		switch self {
		case .external: String(localized: .ServerProperties.saslMechanismExternalTitle)
		case .ecdsaNIST256PChallenge: String(localized: .ServerProperties.saslMechanismEcdsaTitle)
		case .scramSHA512, .scramSHA256: String(localized: .ServerProperties.saslMechanismScramTitle)
		case .plain: String(localized: .ServerProperties.saslMechanismPlainTitle)
		}
	}
}
