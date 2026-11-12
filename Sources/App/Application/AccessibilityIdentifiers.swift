// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The accessibility identifiers an external Accessibility client finds the
 application's controls by.

 Identifiers are not spoken and not shown; they are how `Tests/E2EHarness`
 addresses a control without depending on its title, its position or the
 language the application runs in. The harness keeps a mirror of these strings
 in `Tests/E2EHarness/Identifiers.swift`, and `AccessibilityIdentifiersTests`
 pins them, so renaming one here is a contract change on both sides.

 Identifiers already set elsewhere in the application before this list existed
 (`main-window`, `channel-transcript`, `message-input`, `sidebar`,
 `member-list`, `settings-sidebar` and the onboarding fields) keep their
 spelling where they are set. */
enum AccessibilityIdentifier {
	// MARK: - Menus

	/// What `NSMenuItem.identifier` is prefixed with for a ``MenuCommand``.
	/// AppKit exports a menu item's identifier as its accessibility identifier.
	static let menuPrefix = "menu."

	static func menu(_ command: MenuCommand) -> String {
		menuPrefix + command.rawValue
	}

	// MARK: - Alerts

	/// The suffix of an alert button's identifier, by the response it gives.
	static func alertButton(_ alert: String, _ response: AlertResponse) -> String {
		switch response {
		case .default: alert + "-default"
		case .alternate: alert + "-alternate"
		case .other: alert + "-other"
		}
	}

	/// The certificate trust sheet shown when a server's certificate does not
	/// validate. Its default button is Continue and its alternate is Cancel,
	/// identified the way an alert's are.
	static let certificateTrust = "certificate-trust"

	/// The question asked before the account password goes to an unverified server.
	/// Its default button is Don't Send and its alternate is Send Password.
	static let credentialConsent = "credential-consent"

	/// The confirmation a kick, ban or account ban asks for. Its default button
	/// applies the action.
	static let moderationConfirmation = "moderation-confirmation"

	/// The question about a secure DCC peer seen for the first time. Its default
	/// button is Trust and Remember, its alternate Cancel and its other Trust Once.
	static let dccCertificateFirstUse = "dcc-certificate-first-use"

	/// The warning about a secure DCC peer whose certificate differs from the
	/// saved one. Its default button is Cancel and its alternate replaces the
	/// saved certificate.
	static let dccCertificateChanged = "dcc-certificate-changed"

	/// The question a `DCC CHAT` or `DCC SCHAT` offer asks. Its default button
	/// is Accept and its alternate Decline.
	static let dccChatOffer = "dcc-chat-offer"

	// MARK: - Questions in the conversation

	/// The questions above the message field.
	static let promptTray = "prompt-tray"
	/// The line saying questions wait in other conversations, and its button.
	static let promptElsewhere = "prompt-elsewhere"
	static let promptElsewhereShow = "prompt-elsewhere-show"
	/// What the last typed answering command had to say.
	static let promptFeedback = "prompt-feedback"

	/** One question's card. A question that is identified as an alert keeps
	 that identifier as a card, and its buttons keep their alert identifiers,
	 so a client finds the same control in either style. Any other card is
	 named by its number. */
	static func promptCard(_ request: AlertRequest, number: Int) -> String {
		request.accessibilityIdentifier ?? "prompt-card-\(number)"
	}

	static func promptButton(_ request: AlertRequest, number: Int, response: AlertResponse) -> String {
		if let identifier = request.accessibilityIdentifier {
			return alertButton(identifier, response)
		}
		return "prompt-\(number)-\(request.keyword(for: response).rawValue)"
	}

	static func promptField(_ request: AlertRequest, number: Int) -> String {
		promptCard(request, number: number) + "-field"
	}

	static func promptRemember(_ request: AlertRequest, number: Int) -> String {
		promptCard(request, number: number) + "-remember"
	}

	// MARK: - Onboarding

	static let onboardingWindow = "onboarding-window"
	static let onboardingContinue = "onboarding-continue"
	static let onboardingFinish = "onboarding-finish"
	static let onboardingSkip = "onboarding-skip"
	static let onboardingBack = "onboarding-back"

	static let onboardingNetworkTLS = "onboarding-network-tls"
	static let onboardingNetworkSASL = "onboarding-network-sasl"
	static let onboardingConnectWhenFinished = "onboarding-connect-when-finished"
	/// The network picker's Custom Server row, which the onboarding network
	/// step and the connection sheet share.
	static let networkPickerCustomServer = "network-picker-custom-server"

	/// The content of one onboarding step, named after the step.
	static func onboardingStep(_ name: String) -> String {
		"onboarding-step-" + name
	}

	/// The two choices of the step that asks how Glasstual asks.
	static let onboardingInteractionDialogs = "onboarding-interaction-dialogs"
	static let onboardingInteractionConversation = "onboarding-interaction-conversation"

	// MARK: - Settings

	static let settingsConfirmQuit = "settings-confirm-quit"
	static let settingsTranscriptFont = "settings-transcript-font"
	static let settingsInteractionStyle = "settings-interaction-style"
	/// The transcript theme preset menu in Settings ▸ Style.
	static let settingsThemePreset = "settings-theme-preset"
	static let settingsImport = "settings-import"
	static let settingsExport = "settings-export"
	static let settingsRecoveryPreview = "settings-recovery-preview"
	static let settingsExportIncludeCommands = "settings-export-include-commands"
	static let settingsExportSave = "settings-export-save"
	static let settingsTransferPreview = "settings-transfer-preview"
	static let settingsTransferCommit = "settings-transfer-commit"
	static let settingsTransferCancel = "settings-transfer-cancel"
	static let settingsTransferResult = "settings-transfer-result"
	static let settingsTransferResultConfirm = "settings-transfer-result-confirm"

	/// One row of the Settings sidebar, named after its page.
	static func settingsPage(_ name: String) -> String {
		"settings-page-" + name
	}

	/// A Settings text field, named after the key it edits.
	static func settingsField(_ key: String) -> String {
		"settings-field-" + key
	}

	/// One choice of the interaction style picker, named after its case.
	static func settingsInteractionStyle(_ style: String) -> String {
		settingsInteractionStyle + "-" + style
	}

	/// One preset of the theme preset menu, named after its case.
	static func settingsThemePreset(_ preset: String) -> String {
		settingsThemePreset + "-" + preset
	}

	/// One setting an import preview lists, named after its stored key.
	static func settingsTransferChange(_ key: String) -> String {
		"settings-transfer-change-" + key
	}

	// MARK: - Server Properties

	static let serverPropertiesSave = "server-properties-save"
	static let serverPropertiesRevert = "server-properties-revert"
	/// The Save, Don't Save and Cancel alert closing an edited window asks.
	static let serverPropertiesCloseReview = "server-properties-close-review"
	static let serverPropertiesConnectionName = "server-properties-connection-name"
	static let serverPropertiesServerPassword = "server-password"
	static let serverPropertiesNicknamePassword = "server-nickserv-password"

	/// One row of the Server Properties sidebar, named after its pane.
	static func serverPropertiesPane(_ name: String) -> String {
		"server-properties-pane-" + name
	}

	/// The Sign In with SASL switch, the mechanism menu and the switch that
	/// keeps to the chosen mechanism.
	static let serverPropertiesSASLEnabled = "server-sasl-enabled"
	static let serverPropertiesSASLMechanism = "server-sasl-mechanism"
	static let serverPropertiesSASLMechanismOnly = "server-sasl-mechanism-only"

	/// One choice of the mechanism menu: `automatic`, or a mechanism's wire name.
	static func serverPropertiesSASLMechanism(_ choice: String) -> String {
		serverPropertiesSASLMechanism + "-" + choice
	}

	/// The Profile pane's display name field and its Update and Remove buttons.
	static let serverProfileDisplayName = "server-profile-display-name"
	static let serverProfileUpdate = "server-profile-update"
	static let serverProfileClear = "server-profile-clear"

	// MARK: - Sign In Again

	static let saslSignInMechanism = "sasl-sign-in-mechanism"
	static let saslSignInSubmit = "sasl-sign-in-submit"
	/// What the exchange came to, named for which way it went.
	static let saslSignInSucceeded = "sasl-sign-in-succeeded"
	static let saslSignInFailed = "sasl-sign-in-failed"

	// MARK: - Register Account

	static let accountRegistrationSheet = "account-registration-sheet"
	static let accountRegistrationAccount = "account-registration-account"
	static let accountRegistrationEmail = "account-registration-email"
	static let accountRegistrationPassword = "account-registration-password"
	static let accountRegistrationPasswordVerify = "account-registration-password-verify"
	static let accountRegistrationCode = "account-registration-code"
	static let accountRegistrationSubmit = "account-registration-submit"
	static let accountRegistrationSuccess = "account-registration-success"

	// MARK: - File transfers

	static let fileTransfersWindow = "file-transfers-window"
	static let fileTransfersStart = "file-transfers-start"
	static let fileTransfersStop = "file-transfers-stop"

	/// A pack asked of an XDCC bot that has not offered it yet, named after
	/// the request.
	static func xdccRequestRow(_ id: String) -> String {
		"xdcc-request-row-" + id
	}

	// MARK: - Transcript banners

	/// The banner over a conversation missing messages the server still has,
	/// and its Load button.
	static let missingHistoryBanner = "missing-history-banner"
	static let missingHistoryLoad = "missing-history-load"
	/// The banner over a window of stored history, and its Return to Live button.
	static let historyWindowBanner = "history-window-banner"
	static let historyReturnToLive = "history-return-to-live"

	// MARK: - History search

	/// The toolbar button that shows the sender and date filters.
	static let scrollbackSearchFilters = "scrollback-search-filters"

	// MARK: - Channel list

	static let serverChannelListUpdate = "server-channel-list-update"
	static let serverChannelListJoin = "server-channel-list-join"
	static let serverChannelListFilters = "server-channel-list-filters"
	static let serverChannelListMinimumUsers = "server-channel-list-minimum-users"

	// MARK: - People

	static let addressBookList = "address-book-list"
	static let addressBookAdd = "address-book-add"
	static let addressBookRemove = "address-book-remove"
	static let addressBookAddIgnore = "address-book-add-ignore"
	static let addressBookAddTracking = "address-book-add-tracking"
	static let addressBookEntryHostmask = "address-book-entry-hostmask"
	static let addressBookEntrySave = "address-book-entry-save"

	/// One entry of the People list, named after its hostmask.
	static func addressBookEntry(_ hostmask: String) -> String {
		"address-book-entry-" + hostmask
	}

	// MARK: - Main window

	/** A sidebar row: `sidebar-row-<kind>-<name>`.

	 The row's accessibility value says where it stands: ``SidebarRowState``. */
	static func sidebarRow(_ kind: String, _ name: String) -> String {
		"sidebar-row-\(kind)-\(name)"
	}

	/// The main window's Add Server toolbar button.
	static let toolbarAddServer = "toolbar-add-server"
	/// The Add Server button of the empty state shown when no server is set up.
	static let emptyStateAddServer = "empty-state-add-server"

	/// The line above the message field that says what is typed next answers
	/// a message, in public or privately, and the button that drops the reply.
	static let inputReplyBanner = "input-reply-banner"
	static let inputPrivateReplyBanner = "input-private-reply-banner"
	static let inputReplyCancel = "input-reply-cancel"

	/// The member list's heading. Its accessibility value is the member count.
	static let memberCount = "member-count"

	/// One member's row in the member list, named after the nickname.
	static func memberRow(_ nickname: String) -> String {
		"member-row-" + nickname
	}
}

/// The accessibility value of a sidebar row.
enum SidebarRowState: String {
	/// A server that is connected and registered.
	case connected
	/// A server that is not, including one that is still connecting.
	case disconnected
	/// A channel the user is in.
	case joined
	/// A channel the user is not in, or a conversation that is not active.
	case notJoined = "not-joined"
}
