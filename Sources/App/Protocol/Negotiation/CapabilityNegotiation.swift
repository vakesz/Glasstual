// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

extension Notification.Name {
	static let sessionCapabilitiesDidChange = Notification.Name("Glasstual.sessionCapabilitiesDidChange")
}

private let negotiationLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "CapabilityNegotiation"
)

/// How a capability is negotiated: on its own, or as part of a SASL exchange
/// the negotiation waits for.
enum CapabilityNegotiationKind: Sendable, Equatable {
	case automatic
	case sasl
}

/// How the requested names are split across `CAP REQ` lines. Registration uses
/// the base IRC line limit, including CRLF and the trailing-parameter prefix.
nonisolated enum CapabilityRequestBatching {
	static func groups(_ names: [String], maximumLineBytes: Int = 512) -> [[String]] {
		let budget = maximumLineBytes - "CAP REQ :\r\n".utf8.count
		// A name that cannot fit a line of its own has no request to go in.
		let requestable = names.filter { $0.isEmpty == false && $0.utf8.count <= budget }

		return WireBatching.pack(requestable, budget: budget, cost: { name, group in
			(group.isEmpty ? 0 : 1) + name.utf8.count
		})
	}
}

extension ServerSession {
	func enableCapability(_ capability: CapabilitySet) {
		let couldTrackPresence = supportsAdvancedTracking
		capabilityNegotiation.enable(capability)
		/* ISUPPORT lands after login has already marked every direct conversation
		 active. The moment the server offers MONITOR or WATCH, ask about the
		 peers; it answers at once with who is really there, well before the
		 tracked-user list is built ten seconds in. */
		if couldTrackPresence == false, supportsAdvancedTracking {
			modifyWatchList(byAdding: true, nicknames: directPeerNicknames)
		}
	}

	func disableCapability(_ capability: CapabilitySet) {
		capabilityNegotiation.disable(capability)
	}

	/** Capability bits that did not come from `CAP`.

	 ISUPPORT stands in for a handful of capabilities on servers that never
	 offered them, and SASL records its result the same way. They are kept
	 apart from the acknowledged names so that withdrawing one never withdraws
	 the other. */
	var capabilityFacts: CapabilitySet {
		capabilityNegotiation.facts
	}

	func addCapabilityFacts(_ capability: CapabilitySet) {
		capabilityNegotiation.addFacts(capability)
	}

	func removeCapabilityFacts(_ capability: CapabilitySet) {
		capabilityNegotiation.removeFacts(capability)
	}

	/** Applies what an ISUPPORT line asked for.

	 ``ISupport`` only reads tokens, so this is the one place a token reaches
	 the capability state or the wire. A legacy `PROTOCTL` line goes out once:
	 the fact the session records is what stops the next 005 repeating it. */
	func apply(_ effects: ISupportEffects) {
		if effects.withdrawnCapabilities.isEmpty == false {
			removeCapabilityFacts(effects.withdrawnCapabilities)
		}

		for legacy in effects.legacyCapabilities where capabilityFacts.contains(legacy.capability) == false {
			sendLine(legacy.command)
			addCapabilityFacts(legacy.capability)
		}

		if effects.enabledCapabilities.isEmpty == false {
			enableCapability(effects.enabledCapabilities)
		}
	}

	/// What the server has offered that can be asked for right now: the session
	/// implements it, the user leaves it on, the server has not refused or
	/// withdrawn it, and every dependency it names is already acknowledged.
	private func eligibleCapabilityRequests() -> [String] {
		let offer = capabilityNegotiation.requestableOffer
		let requestable = CapabilityRegistry.defaultRegistry.capabilitiesToRequest(
			fromOffered: offer,
			settings: environment.settings,
			enabledCapabilities: capabilities
		)

		return requestable.compactMap { capability in
			let name = capability.name

			guard capabilityNegotiation.isAcknowledged(name) == false,
			      capabilityNegotiation.isOutstanding(name) == false,
			      capabilityNegotiation.isWithdrawn(name) == false,
			      CapabilityRegistry.defaultRegistry.dependenciesSatisfied(for: capability, by: capabilities)
			else {
				return nil
			}

			/* Asking whether SASL can be requested is a question, not a place to
			 pick the mechanism: this runs again on every `CAP NEW` and `CAP DEL`,
			 and choosing here overwrote the mechanism of an exchange already in
			 flight. The choice is made once, on the ACK. */
			if capability.negotiation == .sasl {
				if config.usesSASL, sessionNicknamePassword?.isEmpty == false, permitsCredentialsInClear == false {
					reportWithheldCredentials()
				}
				guard nextSASLMechanism(from: offer[name] ?? []) != nil else {
					return nil
				}
			}

			/* `name` matched the offer exactly — capability names are
			 case-sensitive — so it is already the spelling to echo back. */
			return name
		}
	}

	/** Applies an `sts` advertisement, reporting whether it abandoned the connection.

	 An upgrade closes the unencrypted socket and reconnects over TLS. Whatever
	 negotiation that socket still had to do is abandoned with it: a `CAP REQ`
	 or `CAP END` written after the upgrade was decided goes to a server the
	 session has just resolved not to talk to in clear. */
	private func handleSTSCapability(from offered: [String: [String]]) -> Bool {
		guard let values = offered["sts"],
		      let parsed = STSCapabilityValues.values(fromCapabilityValues: values)
		else {
			return false
		}

		let host = socket?.config.serverAddress.nonEmpty ?? serverAddress?.nonEmpty

		guard let host else {
			return false
		}

		let connectedPort = socket?.config.serverPort ?? 0
		let action = environment.services.stsPolicies.applyCapabilityValues(
			parsed,
			forHost: host,
			connectedPort: connectedPort,
			secured: isSecured,
			certificateChainValidated: socket?.isSecuredWithValidatedCertificate ?? false
		)

		switch action {
		case let .upgrade(upgradePort):
			guard performedSTSUpgrade == false, upgradePort > 0 else {
				return false
			}

			performedSTSUpgrade = true
			printDebugInformation(toConsole: String(localized: .IRC.serverOffersStrictTransportSecurityReconnecting(String(upgradePort))))

			// Snapshot the pending secret too: teardown may retire its keychain item.
			var origin = server
			origin?.pendingServerPassword = PendingKeychainSecret(sessionServerPassword)
			let endpoint = PendingIRCEndpoint(
				host: host,
				port: upgradePort,
				secured: true,
				origin: origin,
				reason: .stsUpgrade
			)
			addDisconnectCallback { [weak self] in
				guard let self else { return }
				pendingEndpoint = endpoint
				connect()
			}

			disconnect()

			return true
		case let .stored(policyPort):
			printDebugInformation(toConsole: String(localized: .IRC.storedAStrictTransportSecurityPolicy(String(policyPort))))
		case .cleared:
			printDebugInformation(toConsole: String(localized: .IRC.serverWithdrewItsStrictTransportSecurity))
		case .none:
			break
		}

		return false
	}

	/** Sends every request the negotiation is ready for, then closes it.

	 The requests go out together rather than one at a time: a server that
	 never answers one of them cannot hold the rest of the negotiation, and the
	 answers are matched back by name as they arrive. `CAP END` follows once
	 nothing is outstanding and nothing else is eligible, which is also what a
	 `NAK` or a `CAP DEL` of the last outstanding request brings about. */
	func advanceCapabilityNegotiation() {
		guard capabilityNegotiation.isPaused == false,
		      capabilityNegotiation.isCollectingList == false
		else {
			return
		}

		let eligible = eligibleCapabilityRequests()
		let (alone, batched) = eligible.reduce(into: ([String](), [String]())) { partition, name in
			if capabilityNegotiation.mustRequestAlone(name) {
				partition.0.append(name)
			} else {
				partition.1.append(name)
			}
		}

		for group in CapabilityRequestBatching.groups(batched) + alone.map({ [$0] }) {
			for name in group {
				capabilityNegotiation.noteRequested(name)
			}
			sendCapability("REQ", data: group.joined(separator: " "))
		}

		guard capabilityNegotiation.outstandingRequests.isEmpty,
		      isLoggedIn == false, capabilityNegotiation.endSent == false
		else {
			return
		}

		capabilityNegotiation.endSent = true
		socket?.config.diagnostics?.record(.capabilitiesCompleted)
		sendPreAwayIfNeeded()
		sendCapability("END", data: nil)
	}

	private var awayMessageForRegistration: String? {
		guard connectType == .reconnect || connectType == .retry else {
			return nil
		}

		return away.message
	}

	private func sendPreAwayIfNeeded() {
		guard isCapabilityEnabled(.preAway), let awayMessageForRegistration else {
			return
		}

		send(.away, arguments: [awayMessageForRegistration])
	}

	private func pauseCapabilityNegotiation() {
		capabilityNegotiation.isPaused = true
	}

	func resumeCapabilityNegotiation() {
		capabilityNegotiation.isPaused = false
		advanceCapabilityNegotiation()
	}

	private func toggleCapability(_ capabilityString: String, enabled initialValue: Bool) {
		var enabled = initialValue
		var capabilityString = capabilityString

		if capabilityString.hasPrefix("-") {
			capabilityString.removeFirst()
			enabled = false
		}

		guard let name = CapabilityRegistry.parseCapabilityList(capabilityString).keys.first
		else {
			return
		}

		if enabled {
			guard capabilityNegotiation.acknowledge(name) else { return }
		} else {
			capabilityNegotiation.revoke(name)
			if name == "sasl", isCapabilityEnabled(.isInSASLNegotiation) {
				finishSASLNegotiation(failed: true)
			}
		}

		/* The ACK is where the mechanism is chosen, and only while nothing is
		 mid-exchange: a `CAP NEW sasl` arriving during an in-flight SCRAM would
		 otherwise replace the mechanism the exchange is already speaking. */
		if enabled, name == "sasl", isCapabilityEnabled(.isInSASLNegotiation) == false,
		   selectSASLMechanism(fromOffered: capabilityNegotiation.offeredCapabilities[name] ?? []),
		   sendSASLIdentificationRequest()
		{
			pauseCapabilityNegotiation()
		}

		NotificationCenter.default.post(name: .sessionCapabilitiesDidChange, object: self)
	}

	/** Matches an `ACK` or `NAK` back to the outstanding requests it names.

	 A `CAP REQ` is all or nothing: the server refuses the whole line when it
	 will not grant any one name on it. A refused line of several names says
	 nothing about which of them was the problem, so each is asked for again on
	 a line of its own, and only a name refused alone is taken as refused. */
	private func receiveCapabilityAnswer(_ actions: String, accepted: Bool) {
		let tokens = LineParser.wireTokens(in: actions)
		let refusesAGroup = accepted == false && tokens.count > 1

		for token in tokens {
			let name = String(token.drop(while: { $0 == "-" }).prefix(while: { $0 != "=" }))

			capabilityNegotiation.resolveRequest(name)

			if accepted {
				toggleCapability(token, enabled: true)
				if token.hasPrefix("-") {
					capabilityNegotiation.refuse(name)
				}
			} else if refusesAGroup, capabilityNegotiation.mustRequestAlone(name) == false {
				capabilityNegotiation.requestAlone(name)
			} else {
				capabilityNegotiation.refuse(name)
			}
		}
	}

	func handleCapabilityOrAuthenticationRequest(_ message: Message) {
		guard message.params.isEmpty == false else {
			return
		}

		switch message.remoteCommand {
		case .cap:
			handleCapabilitySubcommand(message)
		case .authenticate:
			receiveSASLAuthenticatePayload(message.param(at: 0))
		default:
			break
		}

		_ = shouldPrintReceivedMessage(message)
	}

	private func handleCapabilitySubcommand(_ message: Message) {
		let actions = message.sequence(2)

		switch message.param(at: 1).uppercased() {
		case "LS":
			guard receiveCapabilityListing(message) else { return }
		case "ACK":
			receiveCapabilityAnswer(actions, accepted: true)
		case "NAK":
			receiveCapabilityAnswer(actions, accepted: false)
		case "DEL":
			receiveCapabilityWithdrawal(actions)
		case "NEW":
			guard receiveCapabilityAdvertisement(actions) else { return }
		default:
			break
		}

		advanceCapabilityNegotiation()
	}

	/** Takes one line of a `CAP LS`, reporting whether negotiation may advance.

	 With version 302 the server may split the advertisement over several
	 lines, marking every line but the last with a lone `*`; nothing may be
	 requested until the last one lands. An advertisement that grows past the
	 ceiling is dropped whole and negotiation ends, which is also a complete
	 listing as far as the caller is concerned. A complete listing that upgrades
	 to TLS abandons this connection, and nothing more is negotiated on it. */
	private func receiveCapabilityListing(_ message: Message) -> Bool {
		capabilityNegotiation.beginListing()

		let moreToCome = message.param(at: 2) == "*"
		let actions = moreToCome ? message.sequence(3) : message.sequence(2)

		for (name, values) in CapabilityRegistry.parseCapabilityList(actions) {
			capabilityNegotiation.offer(name, values: values)
		}

		let offeredCount = capabilityNegotiation.offeredCapabilities.count

		guard offeredCount <= CapabilityNegotiationState.maximumOfferedCapabilities else {
			negotiationLogger.error("Ended negotiation: CAP LS offered more capabilities than the limit")
			capabilityNegotiation.discardListing()
			return true
		}

		guard moreToCome == false else {
			return false
		}

		capabilityNegotiation.finishListing()

		return handleSTSCapability(from: capabilityNegotiation.offeredCapabilities) == false
	}

	/// `CAP DEL`: the capability stops being available at once, and a request
	/// still waiting for its answer will never get one, so the withdrawal
	/// stands in for the refusal.
	private func receiveCapabilityWithdrawal(_ actions: String) {
		for name in CapabilityRegistry.parseCapabilityList(actions).keys {
			capabilityNegotiation.withdraw(name)
			toggleCapability(name, enabled: false)
		}
	}

	/// `CAP NEW`: an advertisement made after the initial listing. It is
	/// requested the same way, but without reopening registration. Reports
	/// whether negotiation may advance, which an upgrade to TLS forbids.
	private func receiveCapabilityAdvertisement(_ actions: String) -> Bool {
		let offered = CapabilityRegistry.parseCapabilityList(actions)
		let ceiling = CapabilityNegotiationState.maximumOfferedCapabilities

		for (name, values) in offered {
			let alreadyOffered = capabilityNegotiation.offeredCapabilities[name] != nil

			guard alreadyOffered || capabilityNegotiation.offeredCapabilities.count < ceiling else { continue }

			capabilityNegotiation.offer(name, values: values)
		}

		return handleSTSCapability(from: offered) == false
	}
}
