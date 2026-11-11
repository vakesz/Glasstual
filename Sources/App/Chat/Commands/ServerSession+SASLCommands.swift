// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What a `/sasl` line asks for.
enum SASLCommandRequest: Equatable {
	case status
	/// `nil` is Automatic. `only` stops the session falling back to other mechanisms.
	case mechanism(SASLMechanism?, only: Bool)
	/// The name typed after `mechanism` is not one the session speaks.
	case unknownMechanism(String)
	case setToken(String)
	case clearToken
	/// Sign in again now, with one mechanism or with the usual order.
	case authenticate(SASLMechanism?)
	case invalid

	init(_ arguments: CommandArguments) {
		var arguments = arguments
		switch arguments.next().lowercased() {
		case "", "status":
			self = arguments.isEmpty ? .status : .invalid
		case "mechanism":
			self = Self.mechanismRequest(&arguments)
		case "auth":
			let name = arguments.next()
			guard arguments.isEmpty else {
				self = .invalid
				return
			}
			if name.isEmpty {
				self = .authenticate(nil)
			} else if let mechanism = SASLMechanism(wireName: name) {
				self = .authenticate(mechanism)
			} else {
				self = .unknownMechanism(name)
			}
		case "token":
			let token = arguments.next()
			guard token.isEmpty == false, arguments.isEmpty else {
				self = .invalid
				return
			}
			self = token.lowercased() == "clear" ? .clearToken : .setToken(token)
		default:
			self = .invalid
		}
	}

	private static func mechanismRequest(_ arguments: inout CommandArguments) -> SASLCommandRequest {
		let name = arguments.next()
		let modifier = arguments.next().lowercased()
		guard name.isEmpty == false, arguments.isEmpty, modifier.isEmpty || modifier == "only" else {
			return .invalid
		}
		if name.caseInsensitiveCompare("automatic") == .orderedSame {
			return modifier.isEmpty ? .mechanism(nil, only: false) : .invalid
		}
		guard let mechanism = SASLMechanism(wireName: name) else {
			return .unknownMechanism(name)
		}
		return .mechanism(mechanism, only: modifier == "only")
	}
}

extension ServerSession {
	func dispatchSASLCommand(_ parsed: ParsedUserCommand) {
		switch SASLCommandRequest(parsed.arguments) {
		case .status:
			printSASLStatus()
		case let .mechanism(mechanism, only):
			setSASLMechanismPreference(mechanism, only: only)
		case let .unknownMechanism(name):
			let names = SASLMechanism.defaultOrder.map(\.wireName).joined(separator: ", ")
			printDebugInformation(toConsole: String(localized: .IRC.saslMechanismUnknown(name, names)))
		case let .setToken(token):
			guard OAuthBearerClient.isValidToken(token) else {
				printDebugInformation(toConsole: String(localized: .IRC.saslTokenInvalid))
				return
			}
			storeSASLBearerToken(.set(token))
			printDebugInformation(toConsole: String(localized: .IRC.saslTokenSaved))
		case .clearToken:
			storeSASLBearerToken(.cleared)
			printDebugInformation(toConsole: String(localized: .IRC.saslTokenCleared))
		case let .authenticate(mechanism):
			if let refusal = beginSASLReauthentication(using: mechanism) {
				reportSASLReauthenticationRefusal(refusal)
			}
		case .invalid:
			printInvalidSyntaxMessage(for: parsed.command)
		}
	}

	/// Hands the token to the keychain through the same path the connection
	/// sheet uses. It is never printed, logged or kept in input history.
	private func storeSASLBearerToken(_ edit: PendingKeychainSecret) {
		var mutableConfig = config
		mutableConfig.pendingSASLBearerToken = edit
		updateConfig(mutableConfig)
		chatSession?.save()
	}

	/// Writes the preference the way the connection sheet does, so it persists
	/// and reaches the next authentication.
	private func setSASLMechanismPreference(_ mechanism: SASLMechanism?, only: Bool) {
		var mutableConfig = config
		mutableConfig.saslMechanismPreference = mechanism
		mutableConfig.saslUsesOnlyPreferredMechanism = mechanism != nil && only
		updateConfig(mutableConfig)
		chatSession?.save()

		let text = switch (mechanism, only) {
		case (nil, _): String(localized: .IRC.saslMechanismSetAutomatic)
		case let (mechanism?, false): String(localized: .IRC.saslMechanismSet(mechanism.wireName))
		case let (mechanism?, true): String(localized: .IRC.saslMechanismSetOnly(mechanism.wireName))
		}
		printDebugInformation(toConsole: text)
	}

	/// The account, what the server offers, the preference, and what each
	/// mechanism would do on this connection, one line each.
	func printSASLStatus() {
		for line in saslStatusLines() {
			printDebugInformation(toConsole: line)
		}
	}

	func saslStatusLines() -> [String] {
		var lines: [String] = []

		if let account = identity.account {
			lines.append(String(localized: .IRC.saslStatusAccount(account)))
		} else {
			lines.append(String(localized: .IRC.saslStatusNotSignedIn))
		}
		if let mechanism = sasl.lastAuthenticatedMechanism {
			lines.append(String(localized: .IRC.saslStatusLastMechanism(mechanism.wireName)))
		}

		if let offered = capabilityNegotiation.offeredCapabilities["sasl"] {
			let names = offered.isEmpty ? String(localized: .IRC.saslStatusOfferedUnlisted) : offered.joined(separator: ", ")
			lines.append(String(localized: .IRC.saslStatusOffered(names)))
		} else {
			lines.append(String(localized: .IRC.saslStatusNotOffered))
		}

		lines.append(saslPreferenceStatusLine)

		for mechanism in SASLMechanism.defaultOrder {
			let availability = saslAvailability(of: mechanism)
			lines.append(String(localized: .IRC.saslStatusMechanismLine(
				mechanism.wireName,
				SASLAvailabilityText.describe(availability)
			)))
		}

		return lines
	}

	private var saslPreferenceStatusLine: String {
		guard let preference = config.saslMechanismPreference else {
			return String(localized: .IRC.saslStatusPreferenceAutomatic)
		}
		return config.saslUsesOnlyPreferredMechanism
			? String(localized: .IRC.saslStatusPreferenceOnly(preference.wireName))
			: String(localized: .IRC.saslStatusPreference(preference.wireName))
	}
}

/// How the console names a mechanism's availability.
enum SASLAvailabilityText {
	static func describe(_ availability: SASLAvailability) -> String {
		switch availability {
		case .usable: String(localized: .IRC.saslAvailabilityUsable)
		case .needsConsent: String(localized: .IRC.saslAvailabilityNeedsConsent)
		case let .unavailable(reason): describe(reason)
		}
	}

	static func describe(_ reason: SASLUnavailableReason) -> String {
		switch reason {
		case .noClientCertificate: String(localized: .IRC.saslUnavailableNoClientCertificate)
		case .externalDisabled: String(localized: .IRC.saslUnavailableExternalDisabled)
		case .noSigningKey: String(localized: .IRC.saslUnavailableNoSigningKey)
		case .noPassword: String(localized: .IRC.saslUnavailableNoPassword)
		case .noBearerToken: String(localized: .IRC.saslUnavailableNoBearerToken)
		case .requiresTLS: String(localized: .IRC.saslUnavailableRequiresTls)
		case .clearTextNotPermitted: String(localized: .IRC.saslUnavailableClearTextNotPermitted)
		case .accountCredentialsWithheld: String(localized: .IRC.saslUnavailableCredentialsWithheld)
		}
	}
}
