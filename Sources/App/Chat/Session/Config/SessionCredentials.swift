// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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

	/// Set when the connection went to a host that is not one of the network's
	/// configured servers, such as a server-sent redirect. The account
	/// password is not sent to it.
	var withholdsAccountCredentials = false

	mutating func forget() {
		self = SessionCredentials()
	}
}

/** What the network's nickname service has made of the credentials this session
 sent it. Two answers, not one: a session can be waiting on a service that never
 replies, and it can be identified without having waited, because a connect
 command or a bouncer identified for it. */
struct NickServIdentification {
	/// An `IDENTIFY` has gone out, or is expected, and no answer has arrived.
	var isWaiting = false
	/// The service has confirmed the nickname.
	var isConfirmed = false
}

@MainActor
extension ServerSession {
	/// Resolves the current pending edit over the session's stored snapshot.
	var sessionNicknamePassword: String? {
		guard sessionCredentials.withholdsAccountCredentials == false else { return nil }
		return config.pendingNicknamePassword.value(orStored: sessionCredentials.password(for: config.nicknamePasswordKeychainItem))
	}

	var sessionServerPassword: String? {
		guard let server else { return nil }
		return server.pendingServerPassword.value(orStored: sessionCredentials.password(for: server.keychainItem))
	}

	/** Whether a password may be written to the socket as it stands.

	 An unencrypted connection may only carry it when nothing about it asked
	 for encryption: neither the endpoint it was opened for nor the server entry
	 it came from. A connection that was meant to be TLS and is not has lost its
	 encryption somewhere, and SASL `PLAIN` or a NickServ `IDENTIFY` would put
	 the account password on the wire in clear.

	 An encrypted connection may unless nothing vouches for the certificate:
	 the network is set not to check the chain, so anyone answering at the
	 address would receive the password. A chain the system accepted, and one
	 the user was shown failing and chose to continue with, both count. For one
	 that was not checked, the user has to have allowed this host and port. */
	var permitsCredentialsInClear: Bool {
		if isSecured {
			guard socket?.certificateAssurance == .unverified else { return true }

			return hasCredentialConsent
		}

		let endpointWantsTLS = socket?.config.connectionPrefersSecuredConnection ?? false

		return endpointWantsTLS == false && server?.prefersSecuredConnection != true
	}

	/// Whether the user allowed the host and port this connection is open to
	/// to receive the account password without its certificate being checked.
	var hasCredentialConsent: Bool {
		guard let socket else { return false }

		return credentialConsent?.covers(host: socket.config.serverAddress, port: socket.config.serverPort) == true
	}

	/// Whether the password is held back only for want of an answer the user
	/// has not been asked for yet.
	var mayAskToSendCredentials: Bool {
		isSecured && socket?.certificateAssurance == .unverified && hasCredentialConsent == false
			&& sessionCredentials.reportedWithheldCredentials == false
	}

	/** Says, once per session, that a password was kept off a connection that
	 could not vouch for where it was going. When the cause is a certificate
	 nobody checked, it also asks the user whether to send it anyway, and a
	 yes goes on to the identification services were waiting for. */
	func reportWithheldCredentials() {
		guard sessionCredentials.reportedWithheldCredentials == false else { return }
		let asksForConsent = mayAskToSendCredentials
		sessionCredentials.reportedWithheldCredentials = true
		guard asksForConsent else {
			printDebugInformation(toConsole: ConnectionSafetyStrings.Credentials.withheldOverPlaintext)
			return
		}
		printDebugInformation(toConsole: ConnectionSafetyStrings.Credentials.withheldUnverifiedCertificate)
		askToSendCredentials(sent: { $0.identifyAfterCredentialConsent() })
	}

	/** Asks whether the account password may go to this host although its
	 certificate was not checked. The button Return and Escape press keeps it
	 from being sent, and the alert offers no way to stop asking.

	 `sent` runs when the user allows it, after the host and port are recorded;
	 `declined` runs for any other answer. Neither runs for an answer that
	 arrives after the connection it was about is gone. */
	func askToSendCredentials(
		sent: @escaping @MainActor (ServerSession) -> Void,
		declined: @escaping @MainActor (ServerSession) -> Void = { _ in }
	) {
		guard let socket else { return }
		let host = socket.config.serverAddress
		let port = socket.config.serverPort
		requestResponse(
			Self.credentialConsentAlert(host: host),
			isCurrent: { $0.socket?.config.serverAddress == host && $0.socket?.config.serverPort == port },
			answer: { session, response in
				guard response == .alternate else {
					declined(session)
					return
				}
				session.credentialConsent = CredentialConsent(host: host, port: port)
				sent(session)
			}
		)
	}

	/// The question about sending the password to a server whose certificate
	/// nobody checked. "Don't Send" is the default and the Escape button.
	static func credentialConsentAlert(host: String) -> AlertRequest {
		AlertRequest(
			title: ConnectionSafetyStrings.Credentials.unverifiedCertificateTitle,
			body: ConnectionSafetyStrings.Credentials.unverifiedCertificateBody(host: host),
			defaultButton: ConnectionSafetyStrings.Credentials.dontSend,
			alternateButton: ConnectionSafetyStrings.Credentials.send,
			cancelButton: .default,
			style: .warning
		)
	}
}

/// A host and port the user allowed to receive the account password although
/// its certificate was not checked.
struct CredentialConsent: Equatable {
	let host: String
	let port: UInt16

	func covers(host: String, port: UInt16) -> Bool {
		self.port == port && self.host.caseInsensitiveCompare(host) == .orderedSame
	}
}
