/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** The account credentials one connection authenticates with.

 The nickname password lives in the keychain, and a keychain read on the main
 actor is not free: it can wait on the security daemon or on an access prompt.
 SASL asks for the password every time it decides whether `sasl` can be
 requested, and NickServ asked on every notice it sent, so the read is made
 once and kept for the session. The client forgets it when the session ends and
 whenever its configuration changes, so an edited password is what the next
 read sees. */
struct SessionCredentials {
	private enum CachedSecret {
		case unread
		case read(String?)
	}

	private var nicknamePassword = CachedSecret.unread

	/// Whether the notice saying a password was withheld from an unencrypted
	/// connection has been printed for this session.
	var reportedWithheldCredentials = false

	/// The cached nickname password, reading it with `read` the first time.
	mutating func nicknamePassword(reading read: () -> String?) -> String? {
		if case let .read(password) = nicknamePassword {
			return password
		}

		let password = read()
		nicknamePassword = .read(password)

		return password
	}

	mutating func forget() {
		self = SessionCredentials()
	}
}

@MainActor
extension IRCClient {
	/// The nickname password for this session, read from the keychain at most
	/// once until ``SessionCredentials/forget()``.
	var sessionNicknamePassword: String? {
		sessionCredentials.nicknamePassword { config.nicknamePassword }
	}

	/** Whether a password may be written to the socket as it stands.

	 An encrypted connection always may. An unencrypted one may only when
	 nothing about it asked for encryption: neither the endpoint it was opened
	 for nor the server entry it came from. A connection that was meant to be
	 TLS and is not has lost its encryption somewhere, and SASL `PLAIN` or a
	 NickServ `IDENTIFY` would put the account password on the wire in clear. */
	var permitsCredentialsInClear: Bool {
		if isSecured {
			return true
		}

		let endpointWantsTLS = socket?.config.connectionPrefersSecuredConnection ?? false

		return endpointWantsTLS == false && server?.prefersSecuredConnection != true
	}

	/// Says, once per session, that a password was kept off an unencrypted
	/// connection that should have been encrypted.
	func reportWithheldCredentials() {
		guard sessionCredentials.reportedWithheldCredentials == false else { return }
		sessionCredentials.reportedWithheldCredentials = true
		printDebugInformation(toConsole: ConnectionSafetyStrings.Credentials.withheldOverPlaintext)
	}
}
