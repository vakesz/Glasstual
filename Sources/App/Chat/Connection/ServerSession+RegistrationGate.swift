// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

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
		registration.gate = .awaitingCredentialConsent
		sessionCredentials.reportedWithheldCredentials = true
		askToSendCredentials(
			sent: { session in
				guard session.registration.gate == .awaitingCredentialConsent else { return }
				session.sendRegistration(password: session.sessionServerPassword)
			},
			declined: { session in
				guard session.registration.gate == .awaitingCredentialConsent else { return }
				session.printDebugInformation(toConsole: ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate)
				session.sendRegistration(password: nil)
			}
		)
	}

	private func sendRegistration(password: String?) {
		registration.gate = .sent

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
