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

extension ServerSession {
	/// Resolves the current pending edit over the session's stored snapshot.
	var sessionNicknamePassword: String? {
		guard sessionCredentials.withholdsAccountCredentials == false else { return nil }
		return config.pendingNicknamePassword.value(orStored: sessionCredentials.password(for: config.nicknamePasswordKeychainItem))
	}

	/// The OAUTHBEARER token, resolved the same way as the nickname password.
	var sessionSASLBearerToken: String? {
		guard sessionCredentials.withholdsAccountCredentials == false else { return nil }
		return config.pendingSASLBearerToken.value(orStored: sessionCredentials.password(for: config.saslBearerTokenKeychainItem))
	}

	var sessionServerPassword: String? {
		guard let server = endpoints.current else { return nil }
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
	 that was not checked, the user has to have allowed this host and port with
	 the certificate it presents now. */
	var permitsCredentialsInClear: Bool {
		if isSecured {
			guard socket?.certificateAssurance == .unverified else { return true }

			return hasCredentialConsent
		}

		let endpointWantsTLS = socket?.config.connectionPrefersSecuredConnection ?? false

		return endpointWantsTLS == false && endpoints.current?.prefersSecuredConnection != true
	}

	/// Whether the user allowed the host and port this connection is open to,
	/// presenting the certificate it presents now, to receive the account
	/// password without that certificate being checked.
	var hasCredentialConsent: Bool {
		guard let socket else { return false }

		return credentialConsent?.covers(
			host: socket.config.serverAddress,
			port: socket.config.serverPort,
			certificateFingerprint: socket.peerCertificateFingerprint
		) == true
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

	 `sent` runs when the user allows it, after the host, port and certificate
	 are recorded; `declined` runs for any other answer. Neither runs for an
	 answer that arrives after the connection it was about is gone. When the
	 host and port were allowed before with another certificate, the question
	 says so. */
	func askToSendCredentials(
		sent: @escaping @MainActor (ServerSession) -> Void,
		declined: @escaping @MainActor (ServerSession) -> Void = { _ in }
	) {
		guard let socket else { return }
		let host = socket.config.serverAddress
		let port = socket.config.serverPort
		let fingerprint = socket.peerCertificateFingerprint
		let certificateChanged = credentialConsent?.covers(host: host, port: port) == true
		requestResponse(
			Self.credentialConsentAlert(host: host, certificateChanged: certificateChanged),
			isCurrent: {
				$0.socket?.config.serverAddress == host && $0.socket?.config.serverPort == port
					&& $0.socket?.peerCertificateFingerprint == fingerprint
			},
			answer: { session, response in
				guard response == .alternate else {
					declined(session)
					return
				}
				session.credentialConsent = CredentialConsent(host: host, port: port, certificateFingerprint: fingerprint)
				sent(session)
			}
		)
	}

	/// The question about sending the password to a server whose certificate
	/// nobody checked. "Don't Send" is the default and the Escape button;
	/// "Send" is destructive, because the password cannot be taken back.
	/// `certificateChanged` says the host was allowed before with another certificate.
	static func credentialConsentAlert(host: String, certificateChanged: Bool = false) -> AlertRequest {
		var request = AlertRequest(
			title: ConnectionSafetyStrings.Credentials.unverifiedCertificateTitle,
			body: certificateChanged
				? ConnectionSafetyStrings.Credentials.changedCertificateBody(host: host)
				: ConnectionSafetyStrings.Credentials.unverifiedCertificateBody(host: host),
			defaultButton: ConnectionSafetyStrings.Credentials.dontSend,
			alternateButton: ConnectionSafetyStrings.Credentials.send,
			destructiveButton: .alternate,
			cancelButton: .default,
			style: .warning,
			sensitivity: .security,
			keywords: [.default: .dontSend, .alternate: .send]
		)
		request.accessibilityIdentifier = AccessibilityIdentifier.credentialConsent
		return request
	}
}

/** A host and port the user allowed to receive the account password although
 its certificate was not checked, bound to the certificate it presented then.

 The certificate is the one thing an impostor at the same address cannot
 present, so a consent covers a connection only while the server shows the
 same one. A consent recorded without a certificate covers nothing beyond the
 answer it came with. */
struct CredentialConsent: Equatable {
	let host: String
	let port: UInt16
	/// SHA-256 of the DER of the server's certificate when the user answered.
	let certificateFingerprint: Data?

	/// Whether this consent was given for the host and port, whatever certificate it showed.
	func covers(host: String, port: UInt16) -> Bool {
		self.port == port && self.host.caseInsensitiveCompare(host) == .orderedSame
	}

	/// Whether this consent lets the password go to the host and port while it
	/// presents the certificate with this fingerprint.
	func covers(host: String, port: UInt16, certificateFingerprint: Data?) -> Bool {
		guard let recorded = self.certificateFingerprint, recorded == certificateFingerprint else { return false }

		return covers(host: host, port: port)
	}
}
