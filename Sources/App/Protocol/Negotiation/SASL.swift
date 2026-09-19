// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** What the session will speak for SASL, and how much of it.

 Pure decisions over the mechanisms and the payload: which mechanisms are on
 offer from this side, which one to try next, how long to wait for the server's
 half, and how the payload is cut into `AUTHENTICATE` lines. */
enum SASLPolicy {
	/// Ceiling on the reassembled `AUTHENTICATE` payload. Every mechanism the
	/// session supports fits in a fraction of this; without it a server can
	/// grow the buffer 400 characters at a time forever.
	static let maximumPayloadLength = 16384

	/** The mechanisms the session can speak, in the order it tries them.

	 - Parameter sendsPasswordInClear: Whether the connection may carry the
	   password itself. `PLAIN` sends it as typed, so it is left out where the
	   answer is no; SCRAM proves knowledge of the password without sending it
	   and stays available. */
	static func supportedMechanisms(
		hasClientCertificate: Bool,
		externalMechanismDisabled: Bool,
		hasPassword: Bool,
		sendsPasswordInClear: Bool = true,
		preferredMechanism: String?
	) -> [String] {
		var mechanisms: [String] = []

		if hasClientCertificate, externalMechanismDisabled == false {
			mechanisms.append("EXTERNAL")
		}

		if hasPassword {
			mechanisms.append(SCRAMClient.mechanismName)
			if sendsPasswordInClear {
				mechanisms.append("PLAIN")
			}
		}

		guard let preferredMechanism else {
			return mechanisms
		}

		guard let preferredIndex = mechanisms.firstIndex(where: {
			$0.caseInsensitiveCompare(preferredMechanism) == .orderedSame
		}) else {
			return mechanisms
		}

		let preferred = mechanisms.remove(at: preferredIndex)
		mechanisms.insert(preferred, at: 0)

		return mechanisms
	}

	static func nextMechanism(
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

	/// How long the session waits for the server's half of a SASL exchange.
	static let timeout: TimeInterval = 30

	static func wireChunks(for payload: String) -> [String] {
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

/** One SASL exchange.

 The mechanisms the server offered, the one being tried, the ones already
 refused, and the payload waiting to be answered. It is a value the session
 owns: the exchange is per connection and is thrown away whole on a reset. */
struct SASLSession {
	var offeredMechanisms: [String]?
	var mechanism: String?
	var triedMechanisms: [String] = []
	var incomingPayload: String?
	var scramTask: Task<Void, Never>?
	var scramSession: SCRAMClient? {
		didSet {
			// Every reset or replacement invalidates work from the old exchange.
			scramTask?.cancel()
			scramTask = nil
		}
	}

	/** Bounds the exchange.

	 A server that acknowledges `sasl` and then never answers `AUTHENTICATE`
	 leaves registration paused, and the only thing that ever noticed was the
	 four-minute retry timer taking the whole connection down. */
	let timeoutTimer: SessionTimer
}

/// The SASL half of capability negotiation: which mechanism is chosen, the
/// exchange itself, and what happens when the server refuses one.
extension ServerSession {
	private var supportedSASLMechanisms: [String] {
		guard config.usesSASL else { return [] }
		return SASLPolicy.supportedMechanisms(
			hasClientCertificate: socket?.isConnectedWithClientSideCertificate ?? false,
			externalMechanismDisabled: config.saslAuthenticationDisableExternalMechanism,
			hasPassword: sessionNicknamePassword?.isEmpty == false,
			sendsPasswordInClear: permitsCredentialsInClear,
			preferredMechanism: config.saslMechanismPreference
		)
	}

	func nextSASLMechanism(from offered: [String]) -> String? {
		SASLPolicy.nextMechanism(
			from: supportedSASLMechanisms,
			offered: offered,
			tried: sasl.triedMechanisms
		)
	}

	func selectSASLMechanism(fromOffered mechanisms: [String]) -> Bool {
		sasl.offeredMechanisms = mechanisms
		sasl.mechanism = nextSASLMechanism(from: mechanisms)
		return sasl.mechanism != nil
	}

	func receiveSASLAuthenticatePayload(_ payload: String) {
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

		if sasl.incomingPayload == nil {
			sasl.incomingPayload = ""
		}

		let accumulated = ((sasl.incomingPayload ?? "") as NSString).length + (chunk as NSString).length

		guard accumulated <= SASLPolicy.maximumPayloadLength else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslAuthenticationFailedTheServerSent))
			return
		}

		sasl.incomingPayload? += chunk

		guard chunk.count != 400 else {
			return
		}

		let assembled = sasl.incomingPayload ?? ""
		sasl.incomingPayload = nil
		sendSASLIdentificationInformation(forServerData: assembled)
	}

	private func sendSASLIdentificationInformation(forServerData serverData: String) {
		switch sasl.mechanism {
		case "PLAIN":
			let username = config.username.nonEmpty ?? config.nickname
			let password = sessionNicknamePassword ?? ""
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

	private func sendSASLScramInformation(forServerData serverData: String) {
		guard sasl.scramTask == nil else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
			return
		}
		let username = config.username.nonEmpty ?? config.nickname

		guard let scramSession = sasl.scramSession else {
			let scram = SCRAMClient(username: username, password: sessionNicknamePassword ?? "")
			sasl.scramSession = scram
			sendSASLPayloadInChunks(scram.clientFirstMessage)
			return
		}

		guard let decoded = Data(base64Encoded: serverData),
		      let message = String(data: decoded, encoding: .utf8)
		else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
			return
		}

		if scramSession.state == .sentClientFinal {
			do {
				try scramSession.verifyServerFinalMessage(message)
				sendCapabilityAuthenticate("+")
			} catch {
				abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailed(error.localizedDescription)))
			}

			return
		}

		// The exchange stays on the main actor; only the PBKDF2 derivation
		// leaves it, inside SCRAMClient.pbkdf2Offloaded.
		sasl.scramTask = Task { [weak self, weak connection = socket] in
			defer {
				if self?.sasl.scramSession === scramSession {
					self?.sasl.scramTask = nil
				}
			}
			guard !Task.isCancelled, let connection,
			      self?.socket === connection, self?.sasl.scramSession === scramSession,
			      self?.isConnected == true, self?.isTerminating == false else { return }

			do {
				let final = try await scramSession.clientFinalMessage(forServerFirstMessage: message)
				guard !Task.isCancelled, let self,
				      socket === connection, sasl.scramSession === scramSession,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				sendSASLPayloadInChunks(final)
			} catch {
				guard !Task.isCancelled, let self,
				      socket === connection, sasl.scramSession === scramSession,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailed(error.localizedDescription)))
			}
		}
	}

	private func sendSASLPayloadInChunks(_ payload: String) {
		for chunk in SASLPolicy.wireChunks(for: payload) {
			sendCapabilityAuthenticate(chunk)
		}
	}

	/** SCRAM only buys mutual authentication if the session verified the
	 server's final message. A server that jumps straight to 900/903 without one
	 has proved nothing, so its success must not be believed.

	 The question only exists during a SCRAM exchange. Once SASL has finished,
	 a 900 is the answer to something else — a NickServ `IDENTIFY` after a
	 failed login, say — and a mechanism left over from the exchange must not
	 turn it away. */
	func scramMutualAuthenticationIsSatisfied() -> Bool {
		guard isCapabilityEnabled(.isIdentifiedWithSASL) == false,
		      isCapabilityEnabled(.isInSASLNegotiation)
		else {
			return true
		}
		guard let mechanism = sasl.mechanism,
		      mechanism.caseInsensitiveCompare(SCRAMClient.mechanismName) == .orderedSame
		else {
			return true
		}

		return sasl.scramSession?.state == .authenticated
	}

	/// Ends SASL after a success numeric that the SCRAM exchange did not back up.
	func abortUnverifiedSASLSuccess() {
		abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServerDidNot))
	}

	private func abortSASLNegotiation(reason: String) {
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
	 challenges, each of which the session answers and then waits again; a single
	 timer for the whole exchange gave the last round whatever was left of the
	 thirty seconds the first one had already spent, so a slow but working
	 login was aborted partway through. */
	func startSASLTimeoutTimer() {
		sasl.timeoutTimer.stop()
		sasl.timeoutTimer.start(SASLPolicy.timeout, repeats: false)
	}

	func stopSASLTimeoutTimer() {
		sasl.timeoutTimer.stop()
	}

	/// Gives up on the exchange and lets negotiation finish. `disconnectOnSASLFailure`
	/// still decides whether that means carrying on unauthenticated or quitting,
	/// because a timeout is a failure to authenticate like any other.
	func onSASLTimeoutTimer() {
		stopSASLTimeoutTimer()
		abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.timedOut)
	}

	func finishSASLNegotiation(failed: Bool) {
		stopSASLTimeoutTimer()
		disableCapability(.isInSASLNegotiation)
		sasl.mechanism = nil
		sasl.scramSession = nil
		sasl.incomingPayload = nil
		if failed {
			disableCapability(.isIdentifiedWithSASL)
			if config.disconnectOnSASLFailure {
				printDebugInformation(String(localized: .IRC.saslAuthenticationFailedDisconnecting))
				quit()
				return
			}
		}
		resumeCapabilityNegotiation()
	}

	func retrySASLNegotiation(withMechanisms mechanisms: [String]) -> Bool {
		if let mechanism = sasl.mechanism,
		   sasl.triedMechanisms.contains(where: {
		   	$0.caseInsensitiveCompare(mechanism) == .orderedSame
		   }) == false
		{
			sasl.triedMechanisms.append(mechanism)
		}

		sasl.scramSession = nil
		sasl.incomingPayload = nil

		let offered = mechanisms.isEmpty ? sasl.offeredMechanisms ?? [] : mechanisms

		guard let mechanism = nextSASLMechanism(from: offered) else {
			return false
		}

		sasl.mechanism = mechanism
		sasl.offeredMechanisms = offered
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(mechanism)

		return true
	}

	func sendSASLIdentificationRequest() -> Bool {
		guard isCapabilityEnabled(.isIdentifiedWithSASL) == false,
		      isCapabilityEnabled(.isInSASLNegotiation) == false,
		      let mechanism = sasl.mechanism
		else {
			return false
		}

		enableCapability(.isInSASLNegotiation)
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(mechanism)

		return true
	}

	func resetSASLNegotiation() {
		stopSASLTimeoutTimer()
		disableCapability(.isInSASLNegotiation)
		disableCapability(.isIdentifiedWithSASL)
		sasl.mechanism = nil
		sasl.scramSession = nil
		sasl.incomingPayload = nil
	}
}
