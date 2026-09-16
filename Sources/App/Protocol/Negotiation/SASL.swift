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

/** One SASL exchange.

 The mechanisms the server offered, the one being tried, the ones already
 refused, and the payload waiting to be answered. It is a value the client
 owns: the exchange is per connection and is thrown away whole on a reset. */
@MainActor
struct SASLSession {
	var offeredMechanisms: [String]?
	var mechanism: String?
	var triedMechanisms: [String] = []
	var incomingPayload: String?
	var scramTask: Task<Void, Never>?
	var scramClient: SCRAMClient? {
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
	var timeoutTimer: ClientTimer!
}

/// The SASL half of capability negotiation: which mechanism is chosen, the
/// exchange itself, and what happens when the server refuses one.
@MainActor
extension Client {
	private var supportedSASLMechanisms: [String] {
		guard config.usesSASL else { return [] }
		return ClientNegotiationUtilities.supportedSASLMechanisms(
			hasClientCertificate: socket?.isConnectedWithClientSideCertificate ?? false,
			externalMechanismDisabled: config.saslAuthenticationDisableExternalMechanism,
			hasPassword: sessionNicknamePassword?.isEmpty == false,
			sendsPasswordInClear: permitsCredentialsInClear,
			preferredMechanism: config.saslMechanismPreference
		)
	}

	func nextSASLMechanism(from offered: [String]) -> String? {
		ClientNegotiationUtilities.nextSASLMechanism(
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

	@MainActor func receiveSASLAuthenticatePayload(_ payload: String) {
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

		guard accumulated <= ClientNegotiationUtilities.maximumSASLPayloadLength else {
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

	@MainActor private func sendSASLIdentificationInformation(forServerData serverData: String) {
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

	@MainActor private func sendSASLScramInformation(forServerData serverData: String) {
		guard sasl.scramTask == nil else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
			return
		}
		let username = config.username.nonEmpty ?? config.nickname

		guard let scramClient = sasl.scramClient else {
			let client = SCRAMClient(username: username, password: sessionNicknamePassword ?? "")
			sasl.scramClient = client
			sendSASLPayloadInChunks(client.clientFirstMessage)
			return
		}

		guard let decoded = Data(base64Encoded: serverData),
		      let message = String(data: decoded, encoding: .utf8)
		else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
			return
		}

		if scramClient.state == .sentClientFinal {
			do {
				try scramClient.verifyServerFinalMessage(message)
				sendCapabilityAuthenticate("+")
			} catch {
				abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailed(error.localizedDescription)))
			}

			return
		}

		// The key derivation is deliberately expensive, so it runs off the
		// main actor; the client object itself stays main-actor bound.
		sasl.scramTask = Task { @MainActor [weak self, weak connection = socket] in
			defer {
				if self?.sasl.scramClient === scramClient {
					self?.sasl.scramTask = nil
				}
			}
			guard !Task.isCancelled, let connection,
			      self?.socket === connection, self?.sasl.scramClient === scramClient,
			      self?.isConnected == true, self?.isTerminating == false else { return }

			do {
				let final = try await scramClient.clientFinalMessage(forServerFirstMessage: message)
				guard !Task.isCancelled, let self,
				      socket === connection, sasl.scramClient === scramClient,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				sendSASLPayloadInChunks(final)
			} catch {
				guard !Task.isCancelled, let self,
				      socket === connection, sasl.scramClient === scramClient,
				      isConnected, !isQuitting, !isDisconnecting, !isTerminating,
				      isCapabilityEnabled(.isInSASLNegotiation) else { return }
				abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailed(error.localizedDescription)))
			}
		}
	}

	@MainActor private func sendSASLPayloadInChunks(_ payload: String) {
		for chunk in ClientNegotiationUtilities.saslWireChunks(for: payload) {
			sendCapabilityAuthenticate(chunk)
		}
	}

	/** SCRAM only buys mutual authentication if the client verified the
	 server's final message. A server that jumps straight to 900/903 without one
	 has proved nothing, so its success must not be believed.

	 The question only exists during a SCRAM exchange. Once SASL has finished,
	 a 900 is the answer to something else — a NickServ `IDENTIFY` after a
	 failed login, say — and a mechanism left over from the exchange must not
	 turn it away. */
	@MainActor func scramMutualAuthenticationIsSatisfied() -> Bool {
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

		return sasl.scramClient?.state == .authenticated
	}

	/// Ends SASL after a success numeric that the SCRAM exchange did not back up.
	@MainActor func abortUnverifiedSASLSuccess() {
		abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServerDidNot))
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
		sasl.timeoutTimer.stop()
		sasl.timeoutTimer.start(ClientNegotiationUtilities.saslTimeout, repeats: false)
	}

	@MainActor func stopSASLTimeoutTimer() {
		sasl.timeoutTimer.stop()
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
		sasl.mechanism = nil
		sasl.scramClient = nil
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

	@MainActor
	func retrySASLNegotiation(withMechanisms mechanisms: [String]) -> Bool {
		if let mechanism = sasl.mechanism,
		   sasl.triedMechanisms.contains(where: {
		   	$0.caseInsensitiveCompare(mechanism) == .orderedSame
		   }) == false
		{
			sasl.triedMechanisms.append(mechanism)
		}

		sasl.scramClient = nil
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

	@MainActor func sendSASLIdentificationRequest() -> Bool {
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
		sasl.scramClient = nil
		sasl.incomingPayload = nil
	}
}
