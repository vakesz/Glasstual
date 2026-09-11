/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

extension Notification.Name {
	static let ircClientCapabilitiesDidChange = Notification.Name("IRCClientCapabilitiesDidChange")
}

private let negotiationLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCCapabilityNegotiation"
)

enum ClientNegotiationUtilities {
	/// Ceiling on the reassembled `AUTHENTICATE` payload. Every mechanism the
	/// client supports fits in a fraction of this; without it a server can
	/// grow the buffer 400 characters at a time forever.
	static let maximumSASLPayloadLength = 16384

	/// Ceiling on what a multi-line `CAP LS` may offer. The names are arbitrary
	/// server-controlled tokens and only a final, non-`*` line clears the
	/// table, so a server sending nothing but continuations grows it forever.
	/// The largest advertisement any real network sends is a few dozen.
	static let maximumOfferedCapabilities = 256

	static func supportedSASLMechanisms(
		hasClientCertificate: Bool,
		externalMechanismDisabled: Bool,
		hasPassword: Bool,
		preferredMechanism: String?
	) -> [String] {
		var mechanisms: [String] = []

		if hasClientCertificate, externalMechanismDisabled == false {
			mechanisms.append("EXTERNAL")
		}

		if hasPassword {
			mechanisms.append(SCRAMClient.mechanismName)
			mechanisms.append("PLAIN")
		}

		guard let preferredMechanism,
		      let preferredIndex = mechanisms.firstIndex(where: {
		      	$0.caseInsensitiveCompare(preferredMechanism) == .orderedSame
		      })
		else {
			return mechanisms
		}

		let preferred = mechanisms.remove(at: preferredIndex)
		mechanisms.insert(preferred, at: 0)

		return mechanisms
	}

	static func nextSASLMechanism(
		from supported: [String],
		offered: [String],
		tried: [String]
	) -> String? {
		supported.first { mechanism in
			let wasTried = tried.contains {
				$0.caseInsensitiveCompare(mechanism) == .orderedSame
			}
			let wasOffered = offered.isEmpty || offered.contains {
				$0.caseInsensitiveCompare(mechanism) == .orderedSame
			}

			return wasTried == false && wasOffered
		}
	}

	/// How long the client waits for the server's half of a SASL exchange.
	static let saslTimeout: TimeInterval = 30

	static func saslWireChunks(for payload: String) -> [String] {
		let encoded = Data(payload.utf8).base64EncodedString()

		guard encoded.isEmpty == false else {
			return ["+"]
		}

		var chunks: [String] = []
		var start = encoded.startIndex

		while start < encoded.endIndex {
			let end = encoded.index(start, offsetBy: 400, limitedBy: encoded.endIndex) ?? encoded.endIndex
			chunks.append(String(encoded[start ..< end]))
			start = end
		}

		if chunks.last?.count == 400 {
			chunks.append("+")
		}

		return chunks
	}
}

extension IRCClient {
	var isBrokenIRCdKnownAsTwitch: Bool {
		serverAddress?.hasSuffix(IRCServerQuirks.twitchAddressSuffix) ?? false
	}

	var supportsAdvancedTracking: Bool {
		isCapabilityEnabled(.monitorCommand) || isCapabilityEnabled(.watchCommand)
	}

	var monitorAwayStatus: Bool {
		isCapabilityEnabled(.awayNotify) || environment.preferences.trackUserAwayStatusMaximumChannelSize > 0
	}

	public var lastLine: LogLine? {
		presentation?.lastPrintedLine()
	}

	func messageIsFromMyself(_ message: Message) -> Bool {
		nicknameIsMyself(message.senderNickname ?? "")
	}

	public func nicknameIsMyself(_ nickname: String) -> Bool {
		casefoldNickname(userNickname) == casefoldNickname(nickname)
	}

	public func casefoldNickname(_ nickname: String) -> String {
		supportInfo.casefoldString(nickname)
	}

	public func stringIsNickname(_ string: String) -> Bool {
		string.isHostmaskNickname(on: self) && string.isChannelName(on: self) == false
	}

	public func stringIsChannelName(_ string: String) -> Bool {
		string.isChannelName(on: self)
	}

	func stringIsChannelNameOrZero(_ string: String) -> Bool {
		stringIsChannelName(string) || string == "0"
	}

	class func redactedServiceMessage(_ message: String, sentTo target: String?) -> String {
		ClientWireUtilities.redactedServiceMessage(message, sentTo: target)
	}

	func enableCapability(_ capability: ClientIRCv3SupportedCapability) {
		let couldTrackPresence = supportsAdvancedTracking
		capabilityNegotiation.enable(capability)
		/* ISUPPORT lands after login has already marked every query active. The
		 moment the server offers MONITOR or WATCH, ask about the peers; it
		 answers at once with who is really there, well before the tracked-user
		 list is built ten seconds in. */
		if couldTrackPresence == false, supportsAdvancedTracking {
			modifyWatchList(byAdding: true, nicknames: queryPeerNicknames)
		}
	}

	func disableCapability(_ capability: ClientIRCv3SupportedCapability) {
		capabilityNegotiation.disable(capability)
	}

	/** Capability bits that did not come from `CAP`.

	 ISUPPORT stands in for a handful of capabilities on servers that never
	 offered them, and SASL records its result the same way. They are kept
	 apart from the acknowledged names so that withdrawing one never withdraws
	 the other. */
	var capabilityFacts: ClientIRCv3SupportedCapability {
		capabilityNegotiation.facts
	}

	func addCapabilityFacts(_ capability: ClientIRCv3SupportedCapability) {
		capabilityNegotiation.addFacts(capability)
	}

	func removeCapabilityFacts(_ capability: ClientIRCv3SupportedCapability) {
		capabilityNegotiation.removeFacts(capability)
	}

	public func isCapabilityEnabled(_ capability: ClientIRCv3SupportedCapability) -> Bool {
		capabilities.contains(capability)
	}

	private var capabilityRegistry: CapabilityRegistry {
		.defaultRegistry
	}

	public func isCapabilitySupported(_ capability: String) -> Bool {
		capabilityRegistry.isCapabilitySupported(capability, preferences: environment.preferences)
	}

	public var enabledCapabilitiesStringValue: String {
		capabilityNegotiation.enabledCapabilitiesStringValue
	}

	/// What the server has offered that can be asked for right now: the client
	/// implements it, the user leaves it on, the server has not refused or
	/// withdrawn it, and every dependency it names is already acknowledged.
	@MainActor private func eligibleCapabilityRequests() -> [String] {
		let offer = capabilityNegotiation.requestableOffer
		let requestable = capabilityRegistry.capabilitiesToRequest(
			fromOffered: offer,
			preferences: environment.preferences,
			enabledCapabilities: capabilities
		)

		return requestable.compactMap { capability in
			let name = capability.name

			guard capabilityNegotiation.isAcknowledged(name) == false,
			      capabilityNegotiation.isOutstanding(name) == false,
			      capabilityNegotiation.isWithdrawn(name) == false,
			      capabilityRegistry.dependenciesSatisfied(for: capability, by: capabilities)
			else {
				return nil
			}

			/* Asking whether SASL can be requested is a question, not a place to
			 pick the mechanism: this runs again on every `CAP NEW` and `CAP DEL`,
			 and choosing here overwrote the mechanism of an exchange already in
			 flight. The choice is made once, on the ACK. */
			if capability.negotiation == .sasl,
			   nextSASLMechanism(from: offer[name] ?? []) == nil
			{
				return nil
			}

			/* `name` matched the offer exactly — capability names are
			 case-sensitive — so it is already the spelling to echo back. */
			return name
		}
	}

	@MainActor private func handleSTSCapability(from offered: [String: [String]]) {
		guard let values = offered["sts"],
		      let parsed = STSCapabilityValues.values(fromCapabilityValues: values)
		else {
			return
		}

		let host = socket?.config.serverAddress.nonEmpty ?? serverAddress?.nonEmpty

		guard let host else {
			return
		}

		let connectedPort = socket?.config.serverPort ?? 0
		let action = STSPolicyStore.shared.applyCapabilityValues(
			parsed,
			forHost: host,
			connectedPort: connectedPort,
			secured: isSecured,
			certificateChainValidated: socket?.isSecuredWithValidatedCertificate ?? false
		)

		switch action {
		case let .upgrade(upgradePort):
			guard performedSTSUpgrade == false, upgradePort > 0 else {
				return
			}

			performedSTSUpgrade = true
			printDebugInformation(toConsole: IRCTransportSecurityStrings.offeredPolicy(port: upgradePort))

			// Snapshot the pending secret too: teardown may retire its keychain item.
			var origin = server
			origin?.pendingServerPassword = PendingKeychainSecret(server?.serverPassword)
			let endpoint = PendingIRCEndpoint(host: host, port: upgradePort, origin: origin, reason: .stsUpgrade)
			addDisconnectCallback { [weak self] in
				guard let self else { return }
				pendingEndpoint = endpoint
				connect()
			}

			disconnect()
		case let .stored(policyPort):
			printDebugInformation(toConsole: IRCTransportSecurityStrings.storedPolicy(port: policyPort))
		case .cleared:
			printDebugInformation(toConsole: IRCTransportSecurityStrings.policyWithdrawn)
		case .none:
			break
		}
	}

	/** Sends every request the negotiation is ready for, then closes it.

	 The requests go out together rather than one at a time: a server that
	 never answers one of them cannot hold the rest of the negotiation, and the
	 answers are matched back by name as they arrive. `CAP END` follows once
	 nothing is outstanding and nothing else is eligible, which is also what a
	 `NAK` or a `CAP DEL` of the last outstanding request brings about. */
	@MainActor func advanceCapabilityNegotiation() {
		guard capabilityNegotiation.isPaused == false,
		      capabilityNegotiation.isCollectingList == false
		else {
			return
		}

		for group in CapabilityRequestBatching.groups(eligibleCapabilityRequests()) {
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

		return lastAwayMessage
	}

	@MainActor private func sendPreAwayIfNeeded() {
		guard isCapabilityEnabled(.preAway), let awayMessageForRegistration else {
			return
		}

		send("AWAY", arguments: [awayMessageForRegistration])
	}

	private func pauseCapabilityNegotiation() {
		capabilityNegotiation.isPaused = true
	}

	@MainActor func resumeCapabilityNegotiation() {
		capabilityNegotiation.isPaused = false
		advanceCapabilityNegotiation()
	}

	@MainActor private func toggleCapability(_ capabilityString: String, enabled initialValue: Bool) {
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

		NotificationCenter.default.post(name: .ircClientCapabilitiesDidChange, object: self)
	}

	/// Matches an `ACK` or `NAK` back to the outstanding requests it names.
	@MainActor
	private func receiveCapabilityAnswer(_ actions: String, accepted: Bool) {
		for token in LineParser.wireTokens(in: actions) {
			let name = String(token.drop(while: { $0 == "-" }).prefix(while: { $0 != "=" }))

			capabilityNegotiation.resolveRequest(name)

			if accepted {
				toggleCapability(token, enabled: true)
				if token.hasPrefix("-") {
					capabilityNegotiation.refuse(name)
				}
			} else {
				capabilityNegotiation.refuse(name)
			}
		}
	}

	@MainActor
	func handleCapabilityOrAuthenticationRequest(_ message: Message) {
		guard message.paramsCount > 0 else {
			return
		}

		let command = message.command

		if command.caseInsensitiveCompare("CAP") == .orderedSame {
			handleCapabilitySubcommand(message)
		} else if command.caseInsensitiveCompare("AUTHENTICATE") == .orderedSame {
			receiveSASLAuthenticatePayload(message.param(at: 0))
		}

		_ = postReceivedMessage(message)
	}

	@MainActor private func handleCapabilitySubcommand(_ message: Message) {
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
			receiveCapabilityAdvertisement(actions)
		default:
			break
		}

		advanceCapabilityNegotiation()
	}

	/** Takes one line of a `CAP LS`, reporting whether the listing is complete.

	 With version 302 the server may split the advertisement over several
	 lines, marking every line but the last with a lone `*`; nothing may be
	 requested until the last one lands. An advertisement that grows past the
	 ceiling is dropped whole and negotiation ends, which is also a complete
	 listing as far as the caller is concerned. */
	@MainActor private func receiveCapabilityListing(_ message: Message) -> Bool {
		capabilityNegotiation.beginListing()

		let moreToCome = message.param(at: 2) == "*"
		let actions = moreToCome ? message.sequence(3) : message.sequence(2)

		for (name, values) in CapabilityRegistry.parseCapabilityList(actions) {
			capabilityNegotiation.offer(name, values: values)
		}

		let offeredCount = capabilityNegotiation.offeredCapabilities.count

		guard offeredCount <= ClientNegotiationUtilities.maximumOfferedCapabilities else {
			negotiationLogger.error("Ended negotiation: CAP LS offered more capabilities than the limit")
			capabilityNegotiation.discardListing()
			return true
		}

		guard moreToCome == false else {
			return false
		}

		capabilityNegotiation.finishListing()
		handleSTSCapability(from: capabilityNegotiation.offeredCapabilities)

		return true
	}

	/// `CAP DEL`: the capability stops being available at once, and a request
	/// still waiting for its answer will never get one, so the withdrawal
	/// stands in for the refusal.
	@MainActor private func receiveCapabilityWithdrawal(_ actions: String) {
		for name in CapabilityRegistry.parseCapabilityList(actions).keys {
			capabilityNegotiation.withdraw(name)
			toggleCapability(name, enabled: false)
		}
	}

	/// `CAP NEW`: an advertisement made after the initial listing. It is
	/// requested the same way, but without reopening registration.
	@MainActor private func receiveCapabilityAdvertisement(_ actions: String) {
		let offered = CapabilityRegistry.parseCapabilityList(actions)
		let ceiling = ClientNegotiationUtilities.maximumOfferedCapabilities

		for (name, values) in offered {
			let alreadyOffered = capabilityNegotiation.offeredCapabilities[name] != nil

			guard alreadyOffered || capabilityNegotiation.offeredCapabilities.count < ceiling else { continue }

			capabilityNegotiation.offer(name, values: values)
		}

		handleSTSCapability(from: offered)
	}

	private var supportedSASLMechanisms: [String] {
		guard config.usesSASL else { return [] }
		return ClientNegotiationUtilities.supportedSASLMechanisms(
			hasClientCertificate: socket?.isConnectedWithClientSideCertificate ?? false,
			externalMechanismDisabled: config.saslAuthenticationDisableExternalMechanism,
			hasPassword: config.nicknamePassword?.isEmpty == false,
			preferredMechanism: config.saslMechanismPreference
		)
	}

	private func nextSASLMechanism(from offered: [String]) -> String? {
		ClientNegotiationUtilities.nextSASLMechanism(
			from: supportedSASLMechanisms,
			offered: offered,
			tried: saslTriedMechanisms
		)
	}

	func selectSASLMechanism(fromOffered mechanisms: [String]) -> Bool {
		saslOfferedMechanisms = mechanisms
		saslMechanism = nextSASLMechanism(from: mechanisms)
		return saslMechanism != nil
	}

	@MainActor private func receiveSASLAuthenticatePayload(_ payload: String) {
		guard isCapabilityEnabled(.isInSASLNegotiation) else {
			return
		}

		/* The server answered, so this round is over and the next one starts:
		 the clock is what bounds the wait for the server's next word, not the
		 exchange as a whole. A 400-byte continuation is the same round still
		 arriving, and re-arming for it is right too — the payload is not
		 complete until the short chunk that ends it lands. */
		startSASLTimeoutTimer()

		let chunk = payload == "+" ? "" : payload

		if saslIncomingPayload == nil {
			saslIncomingPayload = ""
		}

		let accumulated = ((saslIncomingPayload ?? "") as NSString).length + (chunk as NSString).length

		guard accumulated <= ClientNegotiationUtilities.maximumSASLPayloadLength else {
			abortSASLNegotiation(reason: IRCTransportSecurityStrings.saslPayloadTooLarge)
			return
		}

		saslIncomingPayload? += chunk

		guard chunk.count != 400 else {
			return
		}

		let assembled = saslIncomingPayload ?? ""
		saslIncomingPayload = nil
		sendSASLIdentificationInformation(forServerData: assembled)
	}

	@MainActor private func sendSASLIdentificationInformation(forServerData serverData: String) {
		switch saslMechanism {
		case "PLAIN":
			let username = config.username.nonEmpty ?? config.nickname
			let password = config.nicknamePassword ?? ""
			/* PLAIN is three fields separated by U+0000. A field that contains
			 one splits somewhere else on the server, which either authenticates
			 as a name the user did not type or sends the tail of the password
			 as a separate field. Neither is a login worth attempting. */
			guard username.contains("\0") == false, password.contains("\0") == false else {
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.credentialsContainNullCharacter)
				return
			}
			sendSASLPayloadInChunks("\(username)\0\(username)\0\(password)")
		case "EXTERNAL":
			sendCapabilityAuthenticate("+")
		case SCRAMClient.mechanismName:
			sendSASLScramInformation(forServerData: serverData)
		default:
			break
		}
	}

	@MainActor private func sendSASLScramInformation(forServerData serverData: String) {
		guard saslScramTask == nil else {
			abortSASLNegotiation(reason: IRCTransportSecurityStrings.malformedSCRAMMessage)
			return
		}
		let username = config.username.nonEmpty ?? config.nickname

		guard let saslScramClient else {
			let client = SCRAMClient(username: username, password: config.nicknamePassword ?? "")
			saslScramClient = client
			sendSASLPayloadInChunks(client.clientFirstMessage)
			return
		}

		guard let decoded = Data(base64Encoded: serverData),
		      let message = String(data: decoded, encoding: .utf8)
		else {
			abortSASLNegotiation(reason: IRCTransportSecurityStrings.malformedSCRAMMessage)
			return
		}

		if saslScramClient.state == .sentClientFinal {
			do {
				try saslScramClient.verifyServerFinalMessage(message)
				sendCapabilityAuthenticate("+")
			} catch {
				abortSASLNegotiation(reason: IRCTransportSecurityStrings.scramFailure(error.localizedDescription))
			}

			return
		}

		// The key derivation is deliberately expensive, so it runs off the
		// main actor; the client object itself stays main-actor bound.
		saslScramTask = Task { @MainActor [weak self, weak connection = socket] in
			defer {
				if self?.saslScramClient === saslScramClient {
					self?.saslScramTask = nil
				}
			}
			guard !Task.isCancelled, let connection,
			      self?.socket === connection, self?.saslScramClient === saslScramClient,
			      self?.isConnected == true, self?.isTerminating == false else { return }

			do {
				let final = try await saslScramClient.clientFinalMessage(forServerFirstMessage: message)
				guard !Task.isCancelled, let self,
				      socket === connection, self.saslScramClient === saslScramClient,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				sendSASLPayloadInChunks(final)
			} catch {
				guard !Task.isCancelled, let self,
				      socket === connection, self.saslScramClient === saslScramClient,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				abortSASLNegotiation(reason: IRCTransportSecurityStrings.scramFailure(error.localizedDescription))
			}
		}
	}

	@MainActor private func sendSASLPayloadInChunks(_ payload: String) {
		for chunk in ClientNegotiationUtilities.saslWireChunks(for: payload) {
			sendCapabilityAuthenticate(chunk)
		}
	}

	/// SCRAM only buys mutual authentication if the client verified the
	/// server's final message. A server that jumps straight to 900/903
	/// without one has proved nothing, so its success must not be believed.
	@MainActor func scramMutualAuthenticationIsSatisfied() -> Bool {
		if isCapabilityEnabled(.isIdentifiedWithSASL) {
			return true
		}
		guard let saslMechanism,
		      saslMechanism.caseInsensitiveCompare(SCRAMClient.mechanismName) == .orderedSame
		else {
			return true
		}

		return saslScramClient?.state == .authenticated
	}

	/// Ends SASL after a success numeric that the SCRAM exchange did not back up.
	@MainActor func abortUnverifiedSASLSuccess() {
		abortSASLNegotiation(reason: IRCTransportSecurityStrings.scramServerSignatureMissing)
	}

	@MainActor private func abortSASLNegotiation(reason: String) {
		guard isCapabilityEnabled(.isInSASLNegotiation) else { return }
		printDebugInformation(toConsole: reason)
		sendCapabilityAuthenticate("*")
		finishSASLNegotiation(failed: true)
	}

	/** Bounds the wait for the server's next word in the SASL exchange.

	 `AUTHENTICATE` has no reply the protocol obliges the server to send, so a
	 server that acknowledges `sasl` and then says nothing leaves capability
	 negotiation paused with `CAP END` unsent. Registration stalls until the
	 240-second retry timer takes the whole connection down, which reads as the
	 network being broken rather than as authentication failing.

	 Armed once per round rather than once per exchange. SCRAM is three
	 challenges, each of which the client answers and then waits again; a single
	 timer for the whole exchange gave the last round whatever was left of the
	 thirty seconds the first one had already spent, so a slow but working
	 login was aborted partway through. */
	@MainActor func startSASLTimeoutTimer() {
		saslTimeoutTimer.stop()
		saslTimeoutTimer.start(ClientNegotiationUtilities.saslTimeout, repeats: false)
	}

	@MainActor func stopSASLTimeoutTimer() {
		guard saslTimeoutTimer.isActive else { return }
		saslTimeoutTimer.stop()
	}

	/// Gives up on the exchange and lets negotiation finish. `disconnectOnSASLFailure`
	/// still decides whether that means carrying on unauthenticated or quitting,
	/// because a timeout is a failure to authenticate like any other.
	@MainActor func onSASLTimeoutTimer() {
		stopSASLTimeoutTimer()
		abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.timedOut)
	}

	@MainActor func finishSASLNegotiation(failed: Bool) {
		stopSASLTimeoutTimer()
		disableCapability(.isInSASLNegotiation)
		saslScramClient = nil
		saslIncomingPayload = nil
		if failed {
			disableCapability(.isIdentifiedWithSASL)
			if config.disconnectOnSASLFailure {
				printDebugInformation(IRCInboundStrings.Numeric.saslAuthenticationFailedDisconnecting)
				quit()
				return
			}
		}
		resumeCapabilityNegotiation()
	}

	@MainActor
	func retrySASLNegotiation(withMechanisms mechanisms: [String]) -> Bool {
		if let saslMechanism,
		   saslTriedMechanisms.contains(where: {
		   	$0.caseInsensitiveCompare(saslMechanism) == .orderedSame
		   }) == false
		{
			saslTriedMechanisms.append(saslMechanism)
		}

		saslScramClient = nil
		saslIncomingPayload = nil

		let offered = mechanisms.isEmpty ? saslOfferedMechanisms ?? [] : mechanisms

		guard let mechanism = nextSASLMechanism(from: offered) else {
			return false
		}

		saslMechanism = mechanism
		saslOfferedMechanisms = offered
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(mechanism)

		return true
	}

	@MainActor private func sendSASLIdentificationRequest() -> Bool {
		guard isCapabilityEnabled(.isIdentifiedWithSASL) == false,
		      isCapabilityEnabled(.isInSASLNegotiation) == false,
		      let saslMechanism
		else {
			return false
		}

		enableCapability(.isInSASLNegotiation)
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(saslMechanism)

		return true
	}

	func resetSASLNegotiation() {
		stopSASLTimeoutTimer()
		disableCapability(.isInSASLNegotiation)
		disableCapability(.isIdentifiedWithSASL)
		saslScramClient = nil
		saslIncomingPayload = nil
	}
}

private extension String {
	var nonEmpty: String? {
		isEmpty ? nil : self
	}
}

/// Registration uses the base IRC line limit, including CRLF and the trailing-parameter prefix.
nonisolated enum CapabilityRequestBatching { // nonisolated: value
	static func groups(_ names: [String], maximumLineBytes: Int = 512) -> [[String]] {
		let budget = maximumLineBytes - "CAP REQ :\r\n".utf8.count
		var groups: [[String]] = []
		var group: [String] = []
		var used = 0
		for name in names where !name.isEmpty && name.utf8.count <= budget {
			let cost = name.utf8.count + (group.isEmpty ? 0 : 1)
			if used + cost > budget {
				groups.append(group)
				group = []
				used = 0
			}
			used += name.utf8.count + (group.isEmpty ? 0 : 1)
			group.append(name)
		}
		if !group.isEmpty {
			groups.append(group)
		}
		return groups
	}
}
