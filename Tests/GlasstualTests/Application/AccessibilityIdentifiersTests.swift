// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** The end-to-end harness finds controls by these strings and keeps its own
 copy of them in `Tests/E2EHarness/Identifiers.swift`. A change here is a
 change to that contract, and has to be made on both sides. */
@Suite("Accessibility identifiers")
@MainActor
struct AccessibilityIdentifiersTests {
	@Test("Menu items are identified by their command")
	func menuItems() {
		#expect(AccessibilityIdentifier.menu(.connect) == "menu.connect")
		#expect(AccessibilityIdentifier.menu(.quit) == "menu.quit")
		#expect(AccessibilityIdentifier.menu(.banAccount) == "menu.banAccount")

		let item = NSMenuItem()
		item.command = .serverProperties
		#expect(item.identifier?.rawValue == "menu.serverProperties")
		#expect(item.command == .serverProperties)
	}

	@Test("The People window")
	func addressBook() {
		#expect(AccessibilityIdentifier.addressBookList == "address-book-list")
		#expect(AccessibilityIdentifier.addressBookAdd == "address-book-add")
		#expect(AccessibilityIdentifier.addressBookRemove == "address-book-remove")
		#expect(AccessibilityIdentifier.addressBookAddIgnore == "address-book-add-ignore")
		#expect(AccessibilityIdentifier.addressBookAddTracking == "address-book-add-tracking")
		#expect(AccessibilityIdentifier.addressBookEntryHostmask == "address-book-entry-hostmask")
		#expect(AccessibilityIdentifier.addressBookEntrySave == "address-book-entry-save")
		#expect(AccessibilityIdentifier.addressBookEntry("troll!*@*") == "address-book-entry-troll!*@*")
	}

	@Test("Server Properties and Settings")
	func serverPropertiesAndSettings() {
		#expect(AccessibilityIdentifier.serverPropertiesConnectionName == "server-properties-connection-name")
		#expect(AccessibilityIdentifier.serverPropertiesCloseReview == "server-properties-close-review")
		#expect(ServerPropertiesEditor.closeReviewRequest(windowTitle: "E2E").accessibilityIdentifier
			== "server-properties-close-review")
		#expect(AccessibilityIdentifier.settingsInteractionStyle(String(describing: InteractionStyle.conversation))
			== "settings-interaction-style-conversation")
		#expect(AccessibilityIdentifier.settingsThemePreset(TranscriptThemePreset.classic.rawValue)
			== "settings-theme-preset-classic")
	}

	@Test("Alerts and their buttons")
	func alerts() {
		#expect(AccessibilityIdentifier.certificateTrust == "certificate-trust")
		#expect(AccessibilityIdentifier.credentialConsent == "credential-consent")
		#expect(AccessibilityIdentifier.moderationConfirmation == "moderation-confirmation")
		#expect(AccessibilityIdentifier.alertButton("credential-consent", .default) == "credential-consent-default")
		#expect(AccessibilityIdentifier.alertButton("credential-consent", .alternate) == "credential-consent-alternate")
		#expect(AccessibilityIdentifier.alertButton("x", .other) == "x-other")
		#expect(ServerSession.credentialConsentAlert(host: "example.org").accessibilityIdentifier
			== "credential-consent")
	}

	@Test("A direct chat offer is identified whether it is plain or secure, passive or not")
	func dccChatOffer() {
		#expect(AccessibilityIdentifier.dccChatOffer == "dcc-chat-offer")
		let offers = [
			DirectChatOffer(address: "127.0.0.1", port: 0, token: "1", isSecure: true),
			DirectChatOffer(address: "127.0.0.1", port: 0, token: "1"),
			DirectChatOffer(address: "203.0.113.5", port: 5000, token: nil, isSecure: true),
			DirectChatOffer(address: "203.0.113.5", port: 5000, token: nil),
		]
		for offer in offers {
			#expect(ServerSession.directChatOfferRequest(offer, from: "fixture", id: "d1").accessibilityIdentifier
				== "dcc-chat-offer")
		}
	}

	@Test("Secure DCC certificate questions")
	func dccCertificates() throws {
		#expect(AccessibilityIdentifier.dccCertificateFirstUse == "dcc-certificate-first-use")
		#expect(AccessibilityIdentifier.dccCertificateChanged == "dcc-certificate-changed")
		let certificate = try #require(DCCPeerCertificate(der: PeerCertificateFixture.ellipticCurve()))
		let pin = DCCPeerPin(certificate: certificate, nickname: "fixture", account: nil, at: .now)
		#expect(ServerSession.dccFirstUseRequest("d1", peer: "fixture", network: "E2E", fingerprint: certificate.fingerprint)
			.accessibilityIdentifier == "dcc-certificate-first-use")
		#expect(ServerSession.dccChangedCertificateRequest(
			"d2", peer: "fixture", saved: pin, presented: certificate.fingerprint
		).accessibilityIdentifier == "dcc-certificate-changed")
		// A missing certificate has no card of its own: it is asked by number.
		#expect(ServerSession.dccUnidentifiedPeerRequest("d3", peer: "fixture", saved: pin).accessibilityIdentifier == nil)
	}

	@Test("Register Account, Sign In Again and the Profile pane")
	func accountSheets() {
		#expect(AccessibilityIdentifier.accountRegistrationSheet == "account-registration-sheet")
		#expect(AccessibilityIdentifier.accountRegistrationAccount == "account-registration-account")
		#expect(AccessibilityIdentifier.accountRegistrationEmail == "account-registration-email")
		#expect(AccessibilityIdentifier.accountRegistrationPassword == "account-registration-password")
		#expect(AccessibilityIdentifier.accountRegistrationPasswordVerify == "account-registration-password-verify")
		#expect(AccessibilityIdentifier.accountRegistrationCode == "account-registration-code")
		#expect(AccessibilityIdentifier.accountRegistrationSubmit == "account-registration-submit")
		#expect(AccessibilityIdentifier.accountRegistrationSuccess == "account-registration-success")
		#expect(AccessibilityIdentifier.saslSignInMechanism == "sasl-sign-in-mechanism")
		#expect(AccessibilityIdentifier.saslSignInSubmit == "sasl-sign-in-submit")
		#expect(AccessibilityIdentifier.saslSignInSucceeded == "sasl-sign-in-succeeded")
		#expect(AccessibilityIdentifier.saslSignInFailed == "sasl-sign-in-failed")
		#expect(AccessibilityIdentifier.serverPropertiesSASLEnabled == "server-sasl-enabled")
		#expect(AccessibilityIdentifier.serverPropertiesSASLMechanism == "server-sasl-mechanism")
		#expect(AccessibilityIdentifier.serverPropertiesSASLMechanism(SASLMechanism.plain.wireName) == "server-sasl-mechanism-PLAIN")
		#expect(AccessibilityIdentifier.serverPropertiesSASLMechanismOnly == "server-sasl-mechanism-only")
		#expect(AccessibilityIdentifier.serverPropertiesPane(String(describing: ServerPropertiesSelection.profile))
			== "server-properties-pane-profile")
		#expect(AccessibilityIdentifier.serverProfileDisplayName == "server-profile-display-name")
		#expect(AccessibilityIdentifier.serverProfileUpdate == "server-profile-update")
		#expect(AccessibilityIdentifier.serverProfileClear == "server-profile-clear")
	}

	@Test("Transcript banners, commands and XDCC requests")
	func transcript() {
		#expect(AccessibilityIdentifier.missingHistoryBanner == "missing-history-banner")
		#expect(AccessibilityIdentifier.missingHistoryLoad == "missing-history-load")
		#expect(AccessibilityIdentifier.historyWindowBanner == "history-window-banner")
		#expect(AccessibilityIdentifier.historyReturnToLive == "history-return-to-live")
		#expect(AccessibilityIdentifier.menu(.transcriptReplyPrivately) == "menu.transcriptReplyPrivately")
		#expect(AccessibilityIdentifier.menu(.transcriptShowOriginalMessage) == "menu.transcriptShowOriginalMessage")
		#expect(AccessibilityIdentifier.xdccRequestRow("A1") == "xdcc-request-row-A1")
		#expect(AccessibilityIdentifier.inputReplyBanner == "input-reply-banner")
		#expect(AccessibilityIdentifier.inputPrivateReplyBanner == "input-private-reply-banner")
		#expect(AccessibilityIdentifier.inputReplyCancel == "input-reply-cancel")
	}

	@Test("Onboarding")
	func onboarding() {
		#expect(AccessibilityIdentifier.onboardingWindow == "onboarding-window")
		#expect(AccessibilityIdentifier.onboardingStep(String(describing: OnboardingStep.network))
			== "onboarding-step-network")
		#expect(AccessibilityIdentifier.onboardingContinue == "onboarding-continue")
		#expect(AccessibilityIdentifier.onboardingFinish == "onboarding-finish")
		#expect(AccessibilityIdentifier.onboardingSkip == "onboarding-skip")
		#expect(AccessibilityIdentifier.onboardingBack == "onboarding-back")
		#expect(AccessibilityIdentifier.onboardingNetworkTLS == "onboarding-network-tls")
		#expect(AccessibilityIdentifier.onboardingNetworkSASL == "onboarding-network-sasl")
		#expect(AccessibilityIdentifier.onboardingConnectWhenFinished == "onboarding-connect-when-finished")
		#expect(AccessibilityIdentifier.networkPickerCustomServer == "network-picker-custom-server")
		#expect(AccessibilityIdentifier.onboardingStep(String(describing: OnboardingStep.interaction))
			== "onboarding-step-interaction")
		#expect(AccessibilityIdentifier.onboardingInteractionDialogs == "onboarding-interaction-dialogs")
		#expect(AccessibilityIdentifier.onboardingInteractionConversation == "onboarding-interaction-conversation")
	}

	/// A question identified as an alert keeps its identifiers as a card, so a
	/// client finds the same controls whichever style the reader chose.
	@Test("Questions in the conversation")
	func prompts() {
		let consent = ServerSession.credentialConsentAlert(host: "example.org")
		let plain = AlertRequest(
			title: "Q", body: "", defaultButton: "Send", alternateButton: "Cancel",
			keywords: [.default: .send, .alternate: .cancel]
		)
		#expect(AccessibilityIdentifier.promptTray == "prompt-tray")
		#expect(AccessibilityIdentifier.promptElsewhere == "prompt-elsewhere")
		#expect(AccessibilityIdentifier.promptElsewhereShow == "prompt-elsewhere-show")
		#expect(AccessibilityIdentifier.promptFeedback == "prompt-feedback")
		#expect(AccessibilityIdentifier.promptCard(consent, number: 4) == "credential-consent")
		#expect(AccessibilityIdentifier.promptButton(consent, number: 4, response: .alternate) == "credential-consent-alternate")
		#expect(AccessibilityIdentifier.promptCard(plain, number: 4) == "prompt-card-4")
		#expect(AccessibilityIdentifier.promptButton(plain, number: 4, response: .default) == "prompt-4-send")
		#expect(AccessibilityIdentifier.promptField(plain, number: 4) == "prompt-card-4-field")
		#expect(AccessibilityIdentifier.settingsInteractionStyle == "settings-interaction-style")
	}

	@Test("Settings and configuration transfer")
	func settings() {
		#expect(AccessibilityIdentifier.settingsPage(SettingsPane.defaultIdentity.rawValue)
			== "settings-page-defaultIdentity")
		#expect(AccessibilityIdentifier.settingsPage(SettingsPane.general.rawValue) == "settings-page-general")
		#expect(AccessibilityIdentifier.settingsConfirmQuit == "settings-confirm-quit")
		#expect(AccessibilityIdentifier.settingsField(SettingsKeys.Identity.nickname.name)
			== "settings-field-Identity -> Nickname")
		#expect(AccessibilityIdentifier.settingsImport == "settings-import")
		#expect(AccessibilityIdentifier.settingsExport == "settings-export")
		#expect(AccessibilityIdentifier.settingsRecoveryPreview == "settings-recovery-preview")
		#expect(AccessibilityIdentifier.settingsExportIncludeCommands == "settings-export-include-commands")
		#expect(AccessibilityIdentifier.settingsExportSave == "settings-export-save")
		#expect(AccessibilityIdentifier.settingsTransferPreview == "settings-transfer-preview")
		#expect(AccessibilityIdentifier.settingsTransferCommit == "settings-transfer-commit")
		#expect(AccessibilityIdentifier.settingsTransferCancel == "settings-transfer-cancel")
		#expect(AccessibilityIdentifier.settingsTransferResultConfirm == "settings-transfer-result-confirm")
		#expect(AccessibilityIdentifier.settingsTransferChange("Connection -> Confirm Quit")
			== "settings-transfer-change-Connection -> Confirm Quit")
	}

	@Test("Server Properties and file transfers")
	func sheetsAndWindows() {
		#expect(AccessibilityIdentifier.serverPropertiesSave == "server-properties-save")
		#expect(AccessibilityIdentifier.serverPropertiesServerPassword == "server-password")
		#expect(AccessibilityIdentifier.serverPropertiesNicknamePassword == "server-nickserv-password")
		#expect(AccessibilityIdentifier.serverPropertiesPane(String(describing: ServerPropertiesSelection.identity))
			== "server-properties-pane-identity")
		#expect(AccessibilityIdentifier.fileTransfersWindow == "file-transfers-window")
		#expect(AccessibilityIdentifier.fileTransfersStart == "file-transfers-start")
		#expect(AccessibilityIdentifier.fileTransfersStop == "file-transfers-stop")
		#expect(AccessibilityIdentifier.scrollbackSearchFilters == "scrollback-search-filters")
		#expect(AccessibilityIdentifier.serverChannelListUpdate == "server-channel-list-update")
		#expect(AccessibilityIdentifier.serverChannelListJoin == "server-channel-list-join")
		#expect(AccessibilityIdentifier.serverChannelListFilters == "server-channel-list-filters")
		#expect(AccessibilityIdentifier.serverChannelListMinimumUsers == "server-channel-list-minimum-users")
	}

	@Test("Main window rows and counts")
	func mainWindow() {
		#expect(AccessibilityIdentifier.sidebarRow("channel", "#e2e") == "sidebar-row-channel-#e2e")
		#expect(AccessibilityIdentifier.sidebarRow("server", "E2E") == "sidebar-row-server-E2E")
		#expect(SidebarRowState.connected.rawValue == "connected")
		#expect(SidebarRowState.disconnected.rawValue == "disconnected")
		#expect(SidebarRowState.joined.rawValue == "joined")
		#expect(SidebarRowState.notJoined.rawValue == "not-joined")
		#expect(AccessibilityIdentifier.memberCount == "member-count")
		#expect(AccessibilityIdentifier.memberRow("fixture") == "member-row-fixture")
	}
}
