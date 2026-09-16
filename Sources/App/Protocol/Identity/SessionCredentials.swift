/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation

/// Credentials resolved before a connection opens. Pending edits can replace
/// individual entries without performing Security calls on the main actor.
struct SessionCredentials {
	private var passwords: [KeychainItem: String] = [:]
	private var resolvedItems: Set<KeychainItem> = []

	func password(for item: KeychainItem) -> String? {
		passwords[item]
	}

	func hasResolved(_ item: KeychainItem) -> Bool {
		resolvedItems.contains(item)
	}

	mutating func install(_ stored: [KeychainItem: String], items: [KeychainItem], applying edits: KeychainPersistence.Edits) {
		passwords = stored
		resolvedItems = Set(items)
		apply(edits)
	}

	mutating func apply(_ edits: KeychainPersistence.Edits) {
		for (item, edit) in edits {
			if edit != .unchanged {
				resolvedItems.insert(item)
			}
			switch edit {
			case .unchanged: break
			case let .set(value): passwords[item] = value
			case .cleared: passwords[item] = nil
			}
		}
	}

	/// Whether the notice saying a password was withheld from an unencrypted
	/// connection has been printed for this session.
	var reportedWithheldCredentials = false

	mutating func forget() {
		self = SessionCredentials()
	}
}

@MainActor
extension IRCClient {
	/// Resolves the current pending edit over the session's stored snapshot.
	var sessionNicknamePassword: String? {
		config.pendingNicknamePassword.value(orStored: sessionCredentials.password(for: config.nicknamePasswordKeychainItem))
	}

	var sessionServerPassword: String? {
		guard let server else { return nil }
		return server.pendingServerPassword.value(orStored: sessionCredentials.password(for: server.keychainItem))
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
