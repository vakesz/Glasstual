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

	// MARK: - File transfers

	static let fileTransfersWindow = "file-transfers-window"
	static let fileTransfersStart = "file-transfers-start"
	static let fileTransfersStop = "file-transfers-stop"

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
