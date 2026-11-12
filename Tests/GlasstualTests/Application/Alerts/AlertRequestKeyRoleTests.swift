// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** Which button Return presses, which one Escape presses and which ones are
 destructive, for every question the prompt port raises.

 The macOS roles: the default button answers Return, the way out answers
 Escape and Command-period, and a destructive button is marked and never the
 default. A routine destructive confirmation therefore has no default button.
 A security question keeps its own rule: Return presses only its way out, so a
 changed or missing certificate, a credential sent to an unverified server and
 every other security question is never accepted by Return. */
@Suite("Alert key roles")
@MainActor
struct AlertRequestKeyRoleTests {
	/// What the keyboard does with one question.
	struct Roles: Equatable, Sendable {
		var returnKey: AlertResponse?
		var escapeKey: AlertResponse
		var destructive: Set<AlertResponse> = []
	}

	struct PromptKind: Sendable, CustomTestStringConvertible {
		let name: String
		let roles: Roles
		let make: @MainActor @Sendable () throws -> AlertRequest

		var testDescription: String {
			name
		}
	}

	private nonisolated static let routine = Roles(returnKey: .default, escapeKey: .alternate)
	private nonisolated static let notice = Roles(returnKey: .default, escapeKey: .default)
	private nonisolated static let destructiveConfirmation = Roles(returnKey: nil, escapeKey: .alternate, destructive: [.default])
	private nonisolated static let discardEdits = Roles(returnKey: nil, escapeKey: .default, destructive: [.alternate])
	private nonisolated static let securityCancelFirst = Roles(returnKey: .default, escapeKey: .default, destructive: [.alternate])
	private nonisolated static let securityCancelSecond = Roles(returnKey: .alternate, escapeKey: .alternate)

	nonisolated static let kinds: [PromptKind] = [
		PromptKind(name: "quit", roles: routine) { ApplicationTermination.quitConfirmationRequest },
		PromptKind(name: "potential flood", roles: routine) { ServerSession.potentialFloodAlert },
		PromptKind(name: "multiline choice", roles: Roles(returnKey: .default, escapeKey: .other)) {
			ServerSession.multilineChoiceAlert(for: MultilineProposal(lines: lines(2), limits: limits))
		},
		PromptKind(name: "multiline truncation", roles: Roles(returnKey: .default, escapeKey: .other)) {
			ServerSession.multilineChoiceAlert(for: MultilineProposal(lines: lines(11), limits: limits))
		},
		PromptKind(name: "connection link", roles: routine) {
			ServerConnection.mergeChoiceRequest(
				address: "irc.example.test", channelNames: "#a", includesMultipleChannels: false, sessionName: "Example"
			)
		},
		PromptKind(name: "existing query deletion", roles: destructiveConfirmation) {
			ServerSession.existingQueryDeletionRequest(name: "alice")
		},
		PromptKind(name: "delete server", roles: destructiveConfirmation) {
			MenuActionController.deleteServerRequest(name: "Example", body: "Body")
		},
		PromptKind(name: "delete channel", roles: destructiveConfirmation) {
			MenuActionController.deleteChannelRequest(name: "#a")
		},
		PromptKind(name: "kick", roles: destructiveConfirmation) { moderation(.kick) },
		PromptKind(name: "ban", roles: destructiveConfirmation) { moderation(.ban) },
		PromptKind(name: "ban account", roles: destructiveConfirmation) { moderation(.banAccount) },
		PromptKind(name: "kickban", roles: destructiveConfirmation) { moderation(.kickban) },
		PromptKind(name: "message deletion", roles: destructiveConfirmation) { TranscriptMessageDeletion.request },
		PromptKind(name: "channel properties changed", roles: discardEdits) {
			ChannelPropertiesSheet.configurationChangedRequest
		},
		PromptKind(name: "profile removal", roles: discardEdits) {
			ServerProfileModel.removalRequest(networkName: "Example")
		},
		PromptKind(name: "virtual host", roles: routine) { MenuActionController.virtualHostRequest },
		PromptKind(name: "SASL token", roles: routine) {
			ServerSession.saslBearerTokenRequest(connectionName: "Example")
		},
		PromptKind(name: "registration password", roles: routine) {
			ServerSession.registrationPasswordRequest(account: "alice", connectionName: "Example")
		},
		PromptKind(name: "configuration secret", roles: routine) {
			ConfigurationCommands.secretRequest(title: "Password", connectionName: "Example")
		},
		PromptKind(name: "keychain retry", roles: routine) {
			KeychainAlerts.failureAlert(CocoaError(.fileWriteUnknown), canRetry: true)
		},
		PromptKind(name: "keychain failure", roles: notice) {
			KeychainAlerts.failureAlert(CocoaError(.fileWriteUnknown), canRetry: false)
		},
		PromptKind(name: "keychain failure at quit", roles: notice) {
			KeychainAlerts.terminationFailureAlert(CocoaError(.fileWriteUnknown))
		},
		PromptKind(name: "no certificates", roles: notice) { ServerPropertiesEditor.noCertificatesRequest },
		PromptKind(name: "certificate summary", roles: notice) {
			CertificatePresenter.summaryRequest(title: "Title", body: "Body", closeButton: "Close")
		},
		PromptKind(name: "open link", roles: notice) {
			try TranscriptCommands.openLinkRequest(for: #require(URL(string: "https://example.test")))
		},
		PromptKind(name: "credential consent", roles: securityCancelFirst) {
			ServerSession.credentialConsentAlert(host: "irc.example.test")
		},
		PromptKind(name: "dropped files", roles: securityCancelSecond) {
			MenuActionController.dropSendRequest(names: ["a.txt"], nickname: "alice")
		},
		PromptKind(name: "direct chat offer", roles: securityCancelSecond) {
			ServerSession.directChatOfferRequest(
				DirectChatOffer(address: "192.0.2.1", port: 5000, token: nil), from: "alice", id: "d1"
			)
		},
		PromptKind(name: "secure DCC first use", roles: securityCancelSecond) {
			try ServerSession.dccFirstUseRequest("d1", peer: "alice", network: "Example", fingerprint: fingerprint())
		},
		PromptKind(name: "secure DCC changed certificate", roles: securityCancelFirst) {
			try ServerSession.dccChangedCertificateRequest("d1", peer: "alice", saved: pin(), presented: fingerprint())
		},
		PromptKind(name: "secure DCC without certificate", roles: securityCancelFirst) {
			try ServerSession.dccUnidentifiedPeerRequest("d1", peer: "alice", saved: pin())
		},
	]

	private nonisolated static let limits = MultilineLimits(maximumBytes: 4096, maximumLines: 10)

	private static func lines(_ count: Int) -> [MultilineWireLine] {
		(0 ..< count).map { MultilineWireLine(text: "line \($0)", continuesPrevious: false) }
	}

	private static func moderation(_ kind: MenuActionController.ChannelModeration) -> AlertRequest {
		kind.request(members: "alice", channel: "#a")
	}

	private static func certificate() throws -> DCCPeerCertificate {
		try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
	}

	private static func fingerprint() throws -> DCCCertificateFingerprint {
		try certificate().fingerprint
	}

	private static func pin() throws -> DCCPeerPin {
		try DCCPeerPin(certificate: certificate(), nickname: "alice", account: nil, at: .now)
	}

	@Test("Each question gives Return, Escape and the destructive role to the right buttons", arguments: kinds)
	func keyRoles(_ kind: PromptKind) throws {
		let request = try kind.make()
		let roles = Roles(
			returnKey: request.returnButton,
			escapeKey: request.escapeButton,
			destructive: Set(request.responses.filter(request.isDestructive))
		)
		#expect(roles == kind.roles)
	}

	@Test("No question puts a destructive button on Return or Escape", arguments: kinds)
	func keysAreNeverDestructive(_ kind: PromptKind) throws {
		let request = try kind.make()
		if let returnButton = request.returnButton {
			#expect(request.isDestructive(returnButton) == false)
		}
		#expect(request.isDestructive(request.escapeButton) == false)
	}

	@Test("A security question's Return presses only its way out", arguments: kinds)
	func securityReturnIsTheWayOut(_ kind: PromptKind) throws {
		let request = try kind.make()
		guard request.sensitivity == .security else { return }
		#expect(request.returnButton == request.escapeButton)
		#expect(request.returnIsEscape)
	}

	@Test("Escape and Command-period cancel; other keys do not")
	func cancelKeys() throws {
		func key(_ characters: String, _ modifiers: NSEvent.ModifierFlags = []) throws -> NSEvent {
			try #require(NSEvent.keyEvent(
				with: .keyDown, location: .zero, modifierFlags: modifiers, timestamp: 0, windowNumber: 0,
				context: nil, characters: characters, charactersIgnoringModifiers: characters,
				isARepeat: false, keyCode: 0
			))
		}
		#expect(try EscapeKeyRoute.isCancelKey(key("\u{1b}")))
		#expect(try EscapeKeyRoute.isCancelKey(key(".", .command)))
		#expect(try EscapeKeyRoute.isCancelKey(key(".")) == false)
		#expect(try EscapeKeyRoute.isCancelKey(key("\r")) == false)
		#expect(try EscapeKeyRoute.isCancelKey(key("\u{1b}", .option)) == false)
	}
}
