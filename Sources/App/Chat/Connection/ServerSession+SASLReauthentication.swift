// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Posted when the status of a connection's SASL exchange changes.
struct SASLExchangeStatusDidChange: SubjectMessage {
	typealias Subject = ServerSession

	nonisolated static let name = Notification.Name("Glasstual.saslExchangeStatusDidChange")

	let subject: ServerSession
}

/// Why signing in again cannot start.
enum SASLReauthenticationRefusal: Equatable {
	case notRegistered
	case exchangeInProgress
	case saslNotOffered
	case mechanismNotOffered(SASLMechanism)
	case mechanismUnavailable(SASLMechanism, SASLUnavailableReason)
	case noUsableMechanism

	var localizedDescription: String {
		switch self {
		case .notRegistered: String(localized: .IRC.saslReauthenticationRefusedNotRegistered)
		case .exchangeInProgress: String(localized: .IRC.saslReauthenticationRefusedInProgress)
		case .saslNotOffered: String(localized: .IRC.saslStatusNotOffered)
		case let .mechanismNotOffered(mechanism):
			String(localized: .IRC.saslReauthenticationRefusedMechanismNotOffered(mechanism.wireName))
		case let .mechanismUnavailable(mechanism, reason):
			String(localized: .IRC.saslReauthenticationRefusedMechanismUnavailable(
				mechanism.wireName,
				SASLAvailabilityText.describe(reason)
			))
		case .noUsableMechanism: String(localized: .IRC.saslReauthenticationRefusedNoUsableMechanism)
		}
	}
}

/** SASL 3.2 re-authentication: signing in again on a registered connection.

 The exchange is the one registration runs, with three differences. It never
 pauses capability negotiation, a failure never ends the connection, and a
 failure leaves the session signed in as it was before. */
extension ServerSession {
	/// The mechanisms the server offers right now, as `sasl=` named them.
	var offeredSASLMechanisms: [String]? {
		capabilityNegotiation.offeredCapabilities["sasl"]
	}

	/// What the user may sign in again with. Unlike registration this does
	/// not read the "Sign in with SASL" switch: asking is the user's choice.
	var reauthenticationSASLMechanisms: [SASLMechanism] {
		SASLPolicy.supportedMechanisms(
			inventory: saslCredentialInventory,
			transport: saslTransportAssurance,
			withholdsAccountCredentials: sessionCredentials.withholdsAccountCredentials,
			preferred: config.saslMechanismPreference,
			onlyPreferred: config.saslUsesOnlyPreferredMechanism
		)
	}

	/// Whether the Sign In Again command can act now.
	var canBeginSASLReauthentication: Bool {
		isLoggedIn && offeredSASLMechanisms != nil
			&& isCapabilityEnabled(.isInSASLNegotiation) == false && sasl.pendingReauthentication == nil
	}

	/** Starts signing in again, or says why it cannot.

	 With `explicit` only that mechanism is tried. When `sasl` was offered but
	 never acknowledged, it is requested first and the exchange starts on the
	 acknowledgement. */
	@discardableResult
	func beginSASLReauthentication(using explicit: SASLMechanism?) -> SASLReauthenticationRefusal? {
		guard isLoggedIn else { return .notRegistered }
		guard isCapabilityEnabled(.isInSASLNegotiation) == false, sasl.pendingReauthentication == nil else {
			return .exchangeInProgress
		}
		guard let offered = offeredSASLMechanisms else { return .saslNotOffered }

		if let explicit {
			if offered.isEmpty == false, SASLPolicy.knownMechanisms(in: offered).contains(explicit) == false {
				return .mechanismNotOffered(explicit)
			}
			if case let .unavailable(reason) = saslAvailability(of: explicit) {
				return .mechanismUnavailable(explicit, reason)
			}
		}

		guard capabilityNegotiation.isAcknowledged("sasl") else {
			guard SASLPolicy
				.nextMechanism(from: explicit.map { [$0] } ?? reauthenticationSASLMechanisms, offered: offered, tried: []) != nil
			else {
				return .noUsableMechanism
			}
			sasl.pendingReauthentication = SASLReauthenticationRequest(explicit: explicit)
			capabilityNegotiation.noteRequested("sasl")
			sendCapability("REQ", data: "sasl")
			return nil
		}

		return startSASLReauthentication(explicit: explicit, offered: offered)
	}

	/// The `sasl` acknowledgement after registration: a re-authentication the
	/// user asked for starts now, and so does an automatic one.
	func receivedSASLAcknowledgementAfterRegistration() {
		let offered = offeredSASLMechanisms ?? []
		if let request = sasl.pendingReauthentication {
			sasl.pendingReauthentication = nil
			if let refusal = startSASLReauthentication(explicit: request.explicit, offered: offered) {
				reportSASLReauthenticationRefusal(refusal)
			}
		} else if shouldReauthenticateAutomatically(offering: SASLPolicy.knownMechanisms(in: offered)) {
			startSASLReauthentication(explicit: nil, offered: offered)
		}
	}

	/** `CAP NEW sasl=…` after registration.

	 Services coming back after a split re-advertise SASL. A session that is not
	 signed in signs in again by itself when a mechanism it can use is newly on
	 offer, subject to the per-server setting and the same credential rules as
	 the first sign-in. One that is signed in only hears that a stronger
	 mechanism is now available. */
	func noteSASLMechanismsChanged(from old: [String]?, to new: [String]) {
		guard isLoggedIn, isCapabilityEnabled(.isInSASLNegotiation) == false else { return }
		let previous = Set(SASLPolicy.knownMechanisms(in: old ?? []))
		let added = SASLPolicy.knownMechanisms(in: new).filter { previous.contains($0) == false }

		if isCapabilityEnabled(.isIdentifiedWithSASL) {
			guard let current = sasl.lastAuthenticatedMechanism,
			      let stronger = added.first(where: { mechanism in
			      	mechanism.strength < current.strength && reauthenticationSASLMechanisms.contains(mechanism)
			      })
			else { return }
			printDebugInformation(toConsole: String(localized: .IRC.saslStrongerMechanismOffered(stronger.wireName)))
			return
		}

		guard capabilityNegotiation.isAcknowledged("sasl"),
		      sasl.pendingReauthentication == nil,
		      shouldReauthenticateAutomatically(offering: new.isEmpty ? SASLMechanism.allCases : added)
		else { return }
		startSASLReauthentication(explicit: nil, offered: new)
	}

	private func shouldReauthenticateAutomatically(offering mechanisms: [SASLMechanism]) -> Bool {
		guard config.usesSASL, config.saslReauthenticatesAutomatically,
		      isCapabilityEnabled(.isIdentifiedWithSASL) == false
		else { return false }
		let supported = reauthenticationSASLMechanisms
		return mechanisms.contains { supported.contains($0) }
	}

	@discardableResult
	private func startSASLReauthentication(explicit: SASLMechanism?, offered: [String]) -> SASLReauthenticationRefusal? {
		let candidates = explicit.map { [$0] } ?? reauthenticationSASLMechanisms
		guard let mechanism = SASLPolicy.nextMechanism(from: candidates, offered: offered, tried: []) else {
			return .noUsableMechanism
		}

		let wasIdentified = isCapabilityEnabled(.isIdentifiedWithSASL)
		sasl.triedMechanisms = []
		sasl.offeredMechanisms = offered
		sasl.scramSession = nil
		sasl.ecdsaExchange = nil
		sasl.oauthExchange = nil
		sasl.incomingPayload = nil
		sasl.phase = .reauthentication(wasIdentified: wasIdentified, explicit: explicit)
		sasl.mechanism = mechanism
		/* Off while the exchange runs, so the SCRAM check asks for a verified
		 server signature again instead of trusting the earlier sign-in. */
		disableCapability(.isIdentifiedWithSASL)
		enableCapability(.isInSASLNegotiation)
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(mechanism.wireName)
		printDebugInformation(toConsole: String(localized: .IRC.saslReauthenticationStarted(mechanism.wireName)))
		setSASLExchangeStatus(.inProgress(mechanism))
		return nil
	}

	/// The re-authentication half of ``finishSASLNegotiation(failed:)``.
	func finishSASLReauthentication(failed: Bool, wasIdentified: Bool, mechanism: SASLMechanism?) {
		if failed {
			if wasIdentified {
				enableCapability(.isIdentifiedWithSASL)
			}
			let text = if wasIdentified, let account = identity.account {
				String(localized: .IRC.saslReauthenticationFailedKeptAccount(account))
			} else {
				String(localized: .IRC.saslReauthenticationFailed)
			}
			printDebugInformation(toConsole: text)
			setSASLExchangeStatus(.failed(reason: text))
		} else if let mechanism {
			let account = identity.account ?? userNickname
			printDebugInformation(toConsole: String(localized: .IRC.saslReauthenticationSucceeded(account, mechanism.wireName)))
			setSASLExchangeStatus(.succeeded(account: identity.account, mechanism: mechanism))
		}
		/* Only the exchange's own hold is lifted: an account registration
		 still waiting keeps `CAP END` back. */
		if capabilityNegotiation.holds.contains(.sasl) {
			resumeCapabilityNegotiation(.sasl)
		}
	}

	func reportSASLReauthenticationRefusal(_ refusal: SASLReauthenticationRefusal) {
		let text = refusal.localizedDescription
		printDebugInformation(toConsole: text)
		setSASLExchangeStatus(.failed(reason: text))
	}

	func setSASLExchangeStatus(_ status: SASLExchangeStatus) {
		guard sasl.status != status else { return }
		sasl.status = status
		SASLExchangeStatusDidChange(subject: self).post()
	}
}
