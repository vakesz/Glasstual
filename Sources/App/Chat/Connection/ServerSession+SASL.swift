// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import CryptoKit
import Foundation
import os

/// The SASL half of capability negotiation: which mechanism is chosen, the
/// exchange itself, and what happens when the server refuses one.
extension ServerSession {
	/** The key ECDSA signs with: an unflushed edit if there is one, and
	 otherwise the keychain snapshot the connection loaded. Nil when none is
	 configured, when the stored value is not a P-256 key, and when the
	 connection went to a host outside the network's configured servers —
	 naming the account to one is what the password rules already refuse. */
	private var saslSigningKey: P256.Signing.PrivateKey? {
		guard sessionCredentials.withholdsAccountCredentials == false else { return nil }
		let stored = config.pendingSASLSigningKey.value(
			orStored: sessionCredentials.password(for: config.saslSigningKeyKeychainItem)
		)

		return stored.flatMap(ECDSASigningKey.privateKey(fromStored:))
	}

	/// The credentials this connection could sign in with right now.
	var saslCredentialInventory: SASLCredentialInventory {
		SASLCredentialInventory(
			hasClientCertificate: socket?.isConnectedWithClientSideCertificate ?? false,
			externalMechanismDisabled: config.saslAuthenticationDisableExternalMechanism,
			hasPassword: sessionNicknamePassword?.isEmpty == false,
			hasSigningKey: saslSigningKey != nil,
			hasBearerToken: sessionSASLBearerToken?.isEmpty == false
		)
	}

	/// How far the open connection vouches for the server, in the terms
	/// ``permitsCredentialsInClear`` and the consent alert already use.
	var saslTransportAssurance: SASLTransportAssurance {
		guard isSecured else {
			return .plaintext(clearCredentialsAllowed: permitsCredentialsInClear)
		}
		guard socket?.certificateAssurance == .unverified else {
			return .verifiedTLS
		}
		return .unverifiedTLS(consented: hasCredentialConsent, mayAsk: mayAskToSendCredentials)
	}

	func saslAvailability(of mechanism: SASLMechanism) -> SASLAvailability {
		SASLPolicy.availability(
			of: mechanism,
			inventory: saslCredentialInventory,
			transport: saslTransportAssurance,
			withholdsAccountCredentials: sessionCredentials.withholdsAccountCredentials
		)
	}

	private var supportedSASLMechanisms: [SASLMechanism] {
		guard config.usesSASL else { return [] }
		return SASLPolicy.supportedMechanisms(
			inventory: saslCredentialInventory,
			transport: saslTransportAssurance,
			withholdsAccountCredentials: sessionCredentials.withholdsAccountCredentials,
			preferred: config.saslMechanismPreference,
			onlyPreferred: config.saslUsesOnlyPreferredMechanism
		)
	}

	func nextSASLMechanism(from offered: [String]) -> SASLMechanism? {
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
		case .plain:
			guard permitsCredentialsInClear else {
				holdSASLCredentialForConsent(serverData: serverData)
				return
			}
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
		case .external:
			sendCapabilityAuthenticate("+")
		case .scramSHA512, .scramSHA256:
			sendSASLScramInformation(forServerData: serverData)
		case .ecdsaNIST256PChallenge:
			sendSASLECDSAInformation(forServerData: serverData)
		case .oauthBearer:
			sendSASLOAuthBearerInformation(forServerData: serverData)
		case nil:
			break
		}
	}

	/** `PLAIN` and `OAUTHBEARER` put the credential itself on the wire, so when
	 the connection cannot vouch for the server they wait for the user. The
	 server has asked for the payload and the exchange's own timer bounds the
	 wait; an answer that comes after SASL has ended, or after it moved on to
	 another mechanism, sends nothing. */
	private func holdSASLCredentialForConsent(serverData: String) {
		let mechanism = sasl.mechanism
		guard mayAskToSendCredentials else {
			abortSASLNegotiation(reason: isSecured
				? ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate
				: ConnectionSafetyStrings.Credentials.withheldOverPlaintext)
			return
		}
		sessionCredentials.reportedWithheldCredentials = true
		askToSendCredentials(sent: { session in
			guard session.isCapabilityEnabled(.isInSASLNegotiation), session.sasl.mechanism == mechanism else { return }
			session.sendSASLIdentificationInformation(forServerData: serverData)
		}, declined: { session in
			session.abortSASLNegotiation(reason: ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate)
		})
	}

	/** OAUTHBEARER (RFC 7628): the token goes out once, over TLS only. A server
	 that refuses it answers with a JSON error, which the client acknowledges
	 with a lone `%x01`; the 904 that follows moves on to the next mechanism. */
	private func sendSASLOAuthBearerInformation(forServerData serverData: String) {
		switch sasl.oauthExchange {
		case nil:
			switch saslAvailability(of: .oauthBearer) {
			case .usable:
				break
			case .needsConsent:
				holdSASLCredentialForConsent(serverData: serverData)
				return
			case .unavailable(.requiresTLS):
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.oauthRequiresTLS)
				return
			case .unavailable:
				abortSASLNegotiation(reason: ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate)
				return
			}
			guard let socket, let token = sessionSASLBearerToken,
			      let response = try? OAuthBearerClient.initialResponse(
			      	token: token,
			      	host: socket.config.serverAddress,
			      	port: socket.config.serverPort
			      )
			else {
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.oauthExchangeInvalid)
				return
			}
			sasl.oauthExchange = .sentInitialResponse
			sendSASLPayloadInChunks(response)
		case .sentInitialResponse:
			guard serverData.isEmpty == false else {
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.oauthExchangeInvalid)
				return
			}
			sasl.oauthExchange = .acknowledgedError(OAuthBearerClient.failure(fromServerPayload: serverData))
			sendSASLPayloadInChunks(OAuthBearerClient.errorAcknowledgement)
		case .acknowledgedError:
			abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.oauthExchangeInvalid)
		}
	}

	/// Says why the server refused the token, once its 904 has arrived.
	func reportOAuthBearerRejection() {
		guard case let .acknowledgedError(failure) = sasl.oauthExchange else { return }
		let status = failure.map { String(ControlCharacterDisposition.singleLine($0.status).prefix(64)) }
		if let status, status.isEmpty == false {
			printDebugInformation(toConsole: ConnectionSafetyStrings.SASL.oauthTokenRejected(status: status))
		} else {
			printDebugInformation(toConsole: ConnectionSafetyStrings.SASL.oauthTokenRejectedWithoutStatus)
		}
	}

	private func sendSASLECDSAInformation(forServerData serverData: String) {
		switch sasl.ecdsaExchange {
		case nil:
			guard let key = saslSigningKey else {
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.ecdsaKeyUnavailable)
				return
			}
			let client = ECDSAChallengeClient(
				privateKey: key,
				authorizationIdentity: config.username.nonEmpty ?? config.nickname
			)
			sasl.ecdsaExchange = .sentIdentity(client)
			sendSASLPayloadInChunks(client.identityPayload)
		case let .sentIdentity(client):
			do {
				let response = try client.response(forEncodedChallenge: serverData)
				sasl.ecdsaExchange = .answered
				sendSASLPayloadInChunks(response)
			} catch {
				abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.ecdsaChallengeInvalid)
			}
		case .answered:
			// The signature is the last message; another challenge is not part of the exchange.
			abortSASLNegotiation(reason: ConnectionSafetyStrings.SASL.ecdsaChallengeInvalid)
		}
	}

	private func sendSASLScramInformation(forServerData serverData: String) {
		guard sasl.scramTask == nil else {
			abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
			return
		}
		let username = config.username.nonEmpty ?? config.nickname

		guard let scramSession = sasl.scramSession else {
			guard let hash = sasl.mechanism.flatMap(SCRAMHash.init(mechanism:)) else {
				abortSASLNegotiation(reason: String(localized: .IRC.saslScramAuthenticationFailedTheServer))
				return
			}
			let scram = SCRAMClient(hash: hash, username: username, password: sessionNicknamePassword ?? "")
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

	private func sendSASLPayloadInChunks(_ payload: Data) {
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
		      isCapabilityEnabled(.isInSASLNegotiation),
		      sasl.mechanism?.credential == .passwordProof
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
		sasl.ecdsaExchange = nil
		sasl.oauthExchange = nil
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
		if let mechanism = sasl.mechanism, sasl.triedMechanisms.contains(mechanism) == false {
			sasl.triedMechanisms.append(mechanism)
		}

		sasl.scramSession = nil
		sasl.ecdsaExchange = nil
		sasl.oauthExchange = nil
		sasl.incomingPayload = nil

		let offered = mechanisms.isEmpty ? sasl.offeredMechanisms ?? [] : mechanisms

		guard let mechanism = nextSASLMechanism(from: offered) else {
			return false
		}

		sasl.mechanism = mechanism
		sasl.offeredMechanisms = offered
		startSASLTimeoutTimer()
		sendCapabilityAuthenticate(mechanism.wireName)

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
		sendCapabilityAuthenticate(mechanism.wireName)

		return true
	}

	func resetSASLNegotiation() {
		stopSASLTimeoutTimer()
		disableCapability(.isInSASLNegotiation)
		disableCapability(.isIdentifiedWithSASL)
		sasl.mechanism = nil
		sasl.scramSession = nil
		sasl.ecdsaExchange = nil
		sasl.oauthExchange = nil
		sasl.incomingPayload = nil
	}
}
