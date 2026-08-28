/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import Foundation

enum ClientNegotiationUtilities {
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
	@objc(isBrokenIRCd_aka_Twitch) var isBrokenIRCdKnownAsTwitch: Bool {
		serverAddress?.hasSuffix(".twitch.tv") ?? false
	}

	@objc var supportsAdvancedTracking: Bool {
		isCapabilityEnabled(.monitorCommand) || isCapabilityEnabled(.watchCommand)
	}

	@objc var monitorAwayStatus: Bool {
		isCapabilityEnabled(.awayNotify) || TextualPreferences.trackUserAwayStatusMaximumChannelSize() > 0
	}

	@objc public var lastLine: LogLine? {
		(viewController as AnyObject as? LogController)?.lastLine()
	}

	@objc(messageIsFromMyself:)
	func messageIsFromMyself(_ message: Message) -> Bool {
		nicknameIsMyself(message.senderNickname ?? "")
	}

	@objc(nicknameIsMyself:)
	public func nicknameIsMyself(_ nickname: String) -> Bool {
		casefoldNickname(userNickname) == casefoldNickname(nickname)
	}

	@objc(casefoldNickname:)
	public func casefoldNickname(_ nickname: String) -> String {
		supportInfo.casefoldString(nickname)
	}

	@objc(stringIsNickname:)
	public func stringIsNickname(_ string: String) -> Bool {
		string.isHostmaskNickname(on: self) && string.isChannelName(on: self) == false
	}

	@objc(stringIsChannelName:)
	public func stringIsChannelName(_ string: String) -> Bool {
		string.isChannelName(on: self)
	}

	@objc(stringIsChannelNameOrZero:)
	func stringIsChannelNameOrZero(_ string: String) -> Bool {
		stringIsChannelName(string) || string == "0"
	}

	@objc(redactedServiceMessage:sentTo:)
	class func redactedServiceMessage(_ message: String, sentTo target: String?) -> String {
		ClientWireUtilities.redactedServiceMessage(message, sentTo: target)
	}

	@objc(targetLooksLikeService:)
	class func targetLooksLikeService(_ target: String?) -> Bool {
		ClientWireUtilities.targetLooksLikeService(target)
	}

	func setCapabilityEnabled(_ capability: ClientIRCv3SupportedCapability) {
		capabilities.formUnion(capability)
	}

	func enableCapability(_ capability: ClientIRCv3SupportedCapability) {
		setCapabilityEnabled(capability)
	}

	func setCapabilityDisabled(_ capability: ClientIRCv3SupportedCapability) {
		capabilities.subtract(capability)
	}

	func disableCapability(_ capability: ClientIRCv3SupportedCapability) {
		setCapabilityDisabled(capability)
	}

	public func isCapabilityEnabled(_ capability: ClientIRCv3SupportedCapability) -> Bool {
		capabilities.contains(capability)
	}

	func capabilityIsEnabled(_ capability: ClientIRCv3SupportedCapability) -> Bool {
		isCapabilityEnabled(capability)
	}

	private var capabilityRegistry: CapabilityRegistry {
		.defaultRegistry
	}

	@objc(isCapabilitySupported:)
	public func isCapabilitySupported(_ capability: String) -> Bool {
		capabilityRegistry.isCapabilitySupported(capability)
	}

	@objc(pendingCapabilityRequests) public var queuedCapabilityRequests: [String] {
		synchronized(pendingCapabilityRequestsMutable) {
			pendingCapabilityRequestsMutable.compactMap { $0 as? String }
		}
	}

	@objc public var enabledCapabilitiesStringValue: String {
		var enabled = enabledCapabilityNames.array.compactMap { $0 as? String }

		if isCapabilityEnabled(.isIdentifiedWithSASL), enabled.contains("sasl") == false {
			enabled.append("sasl")
		}

		return enabled.joined(separator: ", ")
	}

	@MainActor private func queueCapabilityRequests(from offered: [String: [String]]) {
		handleSTSCapability(from: offered)

		let requestable = capabilityRegistry.capabilitiesToRequest(fromOffered: offered)

		synchronized(pendingCapabilityRequestsMutable) {
			for capability in requestable {
				let name = capability.name

				guard enabledCapabilityNames.contains(name) == false else {
					continue
				}

				if let hook = capability.negotiationHook, hook(self, offered[name] ?? []) == false {
					continue
				}

				if pendingCapabilityRequestsMutable.contains(name) == false {
					pendingCapabilityRequestsMutable.add(name)
				}
			}
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
		var upgradePort: UInt16 = 0
		let action = STSPolicyStore.shared.applyCapabilityValues(
			parsed,
			forHost: host,
			connectedPort: connectedPort,
			secured: isSecured,
			upgradePort: &upgradePort
		)

		switch action {
		case .upgrade:
			guard performedSTSUpgrade == false, upgradePort > 0 else {
				return
			}

			performedSTSUpgrade = true
			printDebugInformation(toConsole: IRCTransportSecurityStrings.offeredPolicy(port: upgradePort))

			disconnectCallback = { [weak self] in
				guard let self else { return }
				temporaryServerAddressOverride = host
				temporaryServerPortOverride = upgradePort
				forceSecuredConnectionOnNextConnect = true
				connect()
			}

			disconnect()
		case .stored:
			let policyPort = STSPolicyStore.shared.policy(forHost: host)?.port ?? connectedPort
			printDebugInformation(toConsole: IRCTransportSecurityStrings.storedPolicy(port: policyPort))
		case .cleared:
			printDebugInformation(toConsole: IRCTransportSecurityStrings.policyWithdrawn)
		case .none:
			break
		@unknown default:
			break
		}
	}

	@MainActor @objc(sendNextCapability) public func sendNextQueuedCapability() {
		guard capabilityNegotiationIsPaused == false else {
			return
		}

		let capability: String? = synchronized(pendingCapabilityRequestsMutable) {
			guard let first = pendingCapabilityRequestsMutable.firstObject as? String else {
				return nil
			}

			pendingCapabilityRequestsMutable.removeObject(at: 0)
			return first
		}

		guard let capability else {
			if isLoggedIn == false {
				sendPreAwayIfNeeded()
				sendCapability("END", data: nil)
			}

			return
		}

		sendCapability("REQ", data: capability)
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
		capabilityNegotiationIsPaused = true
	}

	@MainActor @objc(resumeCapabilityNegotiation) func resumeQueuedCapabilityNegotiation() {
		capabilityNegotiationIsPaused = false
		sendNextQueuedCapability()
	}

	@MainActor private func toggleCapability(_ capabilityString: String, enabled initialValue: Bool) {
		var enabled = initialValue
		var capabilityString = capabilityString

		if capabilityString.hasPrefix("-") {
			capabilityString.removeFirst()
			enabled = false
		}

		guard let name = CapabilityRegistry.parseCapabilityList(capabilityString).keys.first,
		      let capability = capabilityRegistry.capability(named: name)
		else {
			return
		}

		if enabled {
			setCapabilityEnabled(capability.identifier)
			enabledCapabilityNames.add(name)
		} else {
			setCapabilityDisabled(capability.identifier)
			enabledCapabilityNames.remove(name)
		}

		if enabled, name == "sasl", sendSASLIdentificationRequest() {
			pauseCapabilityNegotiation()
		}
	}

	@MainActor @objc(receiveCapabilityOrAuthenticationRequest:)
	func handleCapabilityOrAuthenticationRequest(_ message: Message) {
		guard message.paramsCount > 0 else {
			return
		}

		let command = message.command
		let modifier = message.param(at: 0)
		let subcommand = message.param(at: 1)
		var actions = message.sequence(2)

		if command.caseInsensitiveCompare("CAP") == .orderedSame {
			switch subcommand.uppercased() {
			case "LS":
				let moreToCome = message.param(at: 2) == "*"

				if moreToCome {
					actions = message.sequence(3)
				}

				for (name, values) in CapabilityRegistry.parseCapabilityList(actions) {
					offeredCapabilities[name] = values
				}

				if moreToCome {
					return
				}

				queueCapabilityRequests(from: offeredCapabilities as? [String: [String]] ?? [:])
				offeredCapabilities.removeAllObjects()
			case "ACK":
				capabilityTokens(actions).forEach { toggleCapability($0, enabled: true) }
			case "NAK", "DEL":
				capabilityTokens(actions).forEach { toggleCapability($0, enabled: false) }
			case "NEW":
				queueCapabilityRequests(from: CapabilityRegistry.parseCapabilityList(actions))
			default:
				break
			}

			sendNextQueuedCapability()
		} else if command.caseInsensitiveCompare("AUTHENTICATE") == .orderedSame {
			receiveSASLAuthenticatePayload(modifier)
		}

		_ = postReceivedMessage(message)
	}

	private var supportedSASLMechanisms: [String] {
		ClientNegotiationUtilities.supportedSASLMechanisms(
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
			tried: saslTriedMechanisms.compactMap { $0 as? String }
		)
	}

	@objc(selectSASLMechanismFromOffered:)
	func chooseSASLMechanism(fromOffered mechanisms: [String]) -> Bool {
		saslOfferedMechanisms = mechanisms
		saslMechanism = nextSASLMechanism(from: mechanisms)
		return saslMechanism != nil
	}

	func selectSASLMechanism(fromOffered mechanisms: [String]) -> Bool {
		chooseSASLMechanism(fromOffered: mechanisms)
	}

	@MainActor private func receiveSASLAuthenticatePayload(_ payload: String) {
		guard isCapabilityEnabled(.isInSASLNegotiation) else {
			return
		}

		let chunk = payload == "+" ? "" : payload

		if saslIncomingPayload == nil {
			saslIncomingPayload = NSMutableString()
		}

		saslIncomingPayload?.append(chunk)

		guard chunk.count != 400 else {
			return
		}

		let assembled = saslIncomingPayload as String? ?? ""
		saslIncomingPayload = nil
		sendSASLIdentificationInformation(forServerData: assembled)
	}

	@MainActor private func sendSASLIdentificationInformation(forServerData serverData: String) {
		switch saslMechanism {
		case "PLAIN":
			let username = config.username.nonEmpty ?? config.nickname
			let authentication = "\(username)\0\(username)\0\(config.nicknamePassword ?? "")"
			sendSASLPayloadInChunks(authentication)
		case "EXTERNAL":
			sendCapabilityAuthenticate("+")
		case SCRAMClient.mechanismName:
			sendSASLScramInformation(forServerData: serverData)
		default:
			break
		}
	}

	@MainActor private func sendSASLScramInformation(forServerData serverData: String) {
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
		Task { @MainActor [weak self] in
			guard let self else { return }

			do {
				let final = try await saslScramClient.clientFinalMessage(forServerFirstMessage: message)
				sendSASLPayloadInChunks(final)
			} catch {
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
		setCapabilityDisabled(.isInSASLNegotiation)
		setCapabilityDisabled(.isIdentifiedWithSASL)
		resumeQueuedCapabilityNegotiation()
	}

	@MainActor private func abortSASLNegotiation(reason: String) {
		printDebugInformation(toConsole: reason)
		sendCapabilityAuthenticate("*")
		saslScramClient = nil
		saslIncomingPayload = nil
	}

	@MainActor @objc(retrySASLNegotiationWithMechanisms:)
	func retrySASL(withMechanisms mechanisms: [String]) -> Bool {
		if let saslMechanism,
		   saslTriedMechanisms.contains(where: {
		   	($0 as? String)?.caseInsensitiveCompare(saslMechanism) == .orderedSame
		   }) == false
		{
			saslTriedMechanisms.add(saslMechanism)
		}

		saslScramClient = nil
		saslIncomingPayload = nil

		let offered = mechanisms.isEmpty ? saslOfferedMechanisms ?? [] : mechanisms

		guard let mechanism = nextSASLMechanism(from: offered) else {
			return false
		}

		saslMechanism = mechanism
		saslOfferedMechanisms = offered
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

		setCapabilityEnabled(.isInSASLNegotiation)
		sendCapabilityAuthenticate(saslMechanism)

		return true
	}

	@objc func resetSASLNegotiation() {
		setCapabilityDisabled(.isInSASLNegotiation)
		setCapabilityDisabled(.isIdentifiedWithSASL)
		saslScramClient = nil
		saslIncomingPayload = nil
	}

	/// Swift-facing names preserve the protocol vocabulary used by callers while
	/// the Objective-C selectors remain stable for binary interoperability.
	var pendingCapabilityRequests: [String] {
		queuedCapabilityRequests
	}

	@MainActor
	func receiveCapabilityOrAuthenticationRequest(_ message: Message) {
		handleCapabilityOrAuthenticationRequest(message)
	}

	@MainActor
	func sendNextCapability() {
		sendNextQueuedCapability()
	}

	@MainActor
	func retrySASLNegotiation(withMechanisms mechanisms: [String]) -> Bool {
		retrySASL(withMechanisms: mechanisms)
	}

	private func capabilityTokens(_ string: String) -> [String] {
		string.components(separatedBy: .whitespaces).filter { $0.isEmpty == false }
	}

	private func synchronized<T>(_ lock: AnyObject, operation: () -> T) -> T {
		objc_sync_enter(lock)
		defer { objc_sync_exit(lock) }
		return operation()
	}
}

private extension String {
	var nonEmpty: String? {
		isEmpty ? nil : self
	}
}
