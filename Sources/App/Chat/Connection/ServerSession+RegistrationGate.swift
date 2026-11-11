// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** How far a connection has got with sending `CAP LS`, `PASS`, `NICK` and `USER`.

 The server password is often a bouncer's login, so it is held to the same
 rule as the account password: it goes only where the connection can vouch for
 the server. Bouncers expect `PASS` before registration completes, so the lines
 after it wait with it rather than go out without it. */
enum RegistrationGate: Equatable {
	/// Nothing has been sent on this connection yet.
	case notStarted
	/// The connection is to be TLS and the handshake has not finished.
	case awaitingTLS
	/// The user is being asked whether the password may go to a server whose
	/// certificate was not checked.
	case awaitingCredentialConsent
	/// The registration lines are on their way.
	case sent
}

extension ServerSession {
	/// Sends the registration lines, or asks first when the server password
	/// cannot go out on this connection as it stands.
	func beginRegistration() {
		guard let password = sessionServerPassword, password.isEmpty == false else {
			sendRegistration(password: nil)
			return
		}
		if permitsCredentialsInClear {
			sendRegistration(password: password)
			return
		}
		guard mayAskToSendCredentials else {
			reportWithheldCredentials()
			sendRegistration(password: nil)
			return
		}

		/* One question for every credential this connection would carry: the
		 answer is recorded for the host and port, and SASL `PLAIN` reads it. */
		registrationGate = .awaitingCredentialConsent
		sessionCredentials.reportedWithheldCredentials = true
		askToSendCredentials(
			sent: { session in
				guard session.registrationGate == .awaitingCredentialConsent else { return }
				session.sendRegistration(password: session.sessionServerPassword)
			},
			declined: { session in
				guard session.registrationGate == .awaitingCredentialConsent else { return }
				session.printDebugInformation(toConsole: ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate)
				session.sendRegistration(password: nil)
			}
		)
	}

	private func sendRegistration(password: String?) {
		registrationGate = .sent

		/* What `USER` sends: an empty username or real name falls back to the
		 nickname, and the mode bits are the RFC 2812 ones for invisible and
		 plain. */
		let username = config.username.isEmpty ? config.nickname : config.username
		let realName = config.realName.isEmpty ? config.nickname : config.realName
		let modeSymbols = config.setInvisibleModeOnConnect ? "8" : "0"
		sendCapability("LS", data: "302")
		if let password {
			sendPassword(password)
		}
		changeNickname(config.nickname)
		send(.user, arguments: [username, modeSymbols, "*", realName])
	}
}
