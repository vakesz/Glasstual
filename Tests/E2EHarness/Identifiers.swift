import Foundation

/** The accessibility identifiers the harness finds the application's controls by.

 A mirror of `Sources/App/Application/AccessibilityIdentifiers.swift` and of the
 identifiers set before that list existed. The harness drives the shipped binary
 rather than linking it, so it holds the literals; `AccessibilityIdentifiersTests`
 pins the application's side. Lookups go by these strings only: never by title,
 label, position or the language the application runs in. */
enum AXID {
	// MARK: Menus

	/// A main-menu or context-menu item: `menu.<MenuCommand case>`.
	static func menu(_ command: String) -> String {
		"menu." + command
	}

	// MARK: Alerts

	static func alertDefault(_ alert: String) -> String {
		alert + "-default"
	}

	static func alertAlternate(_ alert: String) -> String {
		alert + "-alternate"
	}

	/// Default button Continue, alternate Cancel.
	static let certificateTrust = "certificate-trust"
	/// Default button Don't Send, alternate Send Password.
	static let credentialConsent = "credential-consent"
	/// Default button applies the kick or ban, alternate cancels.
	static let moderationConfirmation = "moderation-confirmation"

	// MARK: Questions in the conversation

	/// The questions above the message field. A question identified as an
	/// alert keeps that identifier as a card, and its buttons keep theirs.
	static let promptTray = "prompt-tray"
	/// What the last typed answering command had to say.
	static let promptFeedback = "prompt-feedback"

	// MARK: Main window

	static let mainWindow = "main-window"
	static let transcript = "channel-transcript"
	static let messageInput = "message-input"
	static let sidebar = "sidebar"
	static let memberList = "member-list"
	static let memberCount = "member-count"
	static let toolbarAddServer = "toolbar-add-server"
	static let emptyStateAddServer = "empty-state-add-server"

	static func memberRow(_ nickname: String) -> String {
		"member-row-" + nickname
	}

	/// `server`, `channel`, `direct`, `direct-chat` or `console`.
	static func sidebarRow(_ kind: String, _ name: String) -> String {
		"sidebar-row-\(kind)-\(name)"
	}

	/// The values a sidebar row reports.
	enum RowState {
		static let connected = "connected"
		static let disconnected = "disconnected"
		static let joined = "joined"
		static let notJoined = "not-joined"
	}

	// MARK: Onboarding

	static let onboardingWindow = "onboarding-window"
	static let onboardingContinue = "onboarding-continue"
	static let onboardingFinish = "onboarding-finish"
	static let onboardingSkip = "onboarding-skip"
	static let onboardingBack = "onboarding-back"
	static let onboardingNickname = "onboarding-nickname"
	static let onboardingRealName = "onboarding-real-name"
	static let onboardingAlternateNickname = "onboarding-alternate-nickname"
	static let onboardingSummary = "onboarding-summary"
	static let networkPickerList = "network-picker-list"
	static let networkAddress = "network-address"
	static let networkPort = "network-port"
	static let networkPickerCustomServer = "network-picker-custom-server"
	static let onboardingNetworkTLS = "onboarding-network-tls"
	static let onboardingNetworkSASL = "onboarding-network-sasl"
	static let onboardingConnectWhenFinished = "onboarding-connect-when-finished"

	/// `identity`, `appearance`, `interaction`, `notifications`, `network` or `summary`.
	static func onboardingStep(_ name: String) -> String {
		"onboarding-step-" + name
	}

	/// The two choices of the step that asks how Glasstual asks.
	static let onboardingInteractionDialogs = "onboarding-interaction-dialogs"
	static let onboardingInteractionConversation = "onboarding-interaction-conversation"

	// MARK: Settings

	/// SwiftUI names the Settings window itself, so the harness knows it as
	/// the window that holds the Settings sidebar.
	static let settingsWindow = settingsSidebar
	static let settingsSidebar = "settings-sidebar"
	static let settingsConfirmQuit = "settings-confirm-quit"
	static let settingsTranscriptFont = "settings-transcript-font"
	static let settingsImport = "settings-import"
	static let settingsExport = "settings-export"
	static let settingsRecoveryPreview = "settings-recovery-preview"
	static let settingsExportIncludeCommands = "settings-export-include-commands"
	static let settingsExportSave = "settings-export-save"
	static let settingsTransferPreview = "settings-transfer-preview"
	static let settingsTransferCommit = "settings-transfer-commit"
	static let settingsTransferCancel = "settings-transfer-cancel"
	static let settingsTransferResultConfirm = "settings-transfer-result-confirm"
	static let settingsInteractionStyle = "settings-interaction-style"
	static let settingsThemePreset = "settings-theme-preset"

	/// An `InteractionStyle` case name: `dialogs` or `conversation`.
	static func settingsInteractionStyle(_ style: String) -> String {
		settingsInteractionStyle + "-" + style
	}

	/// A `TranscriptThemePreset` raw value, such as `classic`.
	static func settingsThemePreset(_ preset: String) -> String {
		settingsThemePreset + "-" + preset
	}

	/// A `SettingsPane` raw value, such as `general` or `defaultIdentity`.
	static func settingsPage(_ pane: String) -> String {
		"settings-page-" + pane
	}

	/// A Settings text field, by the settings key it edits.
	static func settingsField(_ key: String) -> String {
		"settings-field-" + key
	}

	static func settingsTransferChange(_ key: String) -> String {
		"settings-transfer-change-" + key
	}

	// MARK: Server Properties

	/// The Server Properties window, known by its Save button.
	static let serverProperties = serverPropertiesSave
	static let serverPropertiesSave = "server-properties-save"
	static let serverPropertiesRevert = "server-properties-revert"
	/// The Save, Don't Save and Cancel alert closing an edited window asks.
	static let serverPropertiesCloseReview = "server-properties-close-review"
	static let serverPropertiesConnectionName = "server-properties-connection-name"
	static let serverPassword = "server-password"
	static let nicknamePassword = "server-nickserv-password"

	/// A `ServerPropertiesSelection` case name, such as `general` or `identity`.
	static func serverPropertiesPane(_ pane: String) -> String {
		"server-properties-pane-" + pane
	}

	// MARK: System panels

	/// The identifiers macOS gives its save and open panels, their default
	/// button and the column browser that lists the folder they show.
	static let savePanel = "save-panel"
	static let openPanel = "open-panel"
	static let panelDefaultButton = "OKButton"
	static let panelBrowser = "ColumnView"

	// MARK: File transfers

	static let fileTransfersWindow = "file-transfers-window"
	static let fileTransfersStart = "file-transfers-start"
	static let fileTransfersStop = "file-transfers-stop"

	static func fileTransferRow(_ id: String) -> String {
		"file-transfer-row-" + id
	}

	static func fileTransferStatus(_ id: String) -> String {
		"file-transfer-status-" + id
	}

	static let fileTransferFilenamePrefix = "file-transfer-filename-"

	// MARK: History search

	static let scrollbackSearchFilters = "scrollback-search-filters"

	// MARK: Channel list

	static let serverChannelListUpdate = "server-channel-list-update"
	static let serverChannelListJoin = "server-channel-list-join"
	static let serverChannelListFilters = "server-channel-list-filters"
	static let serverChannelListMinimumUsers = "server-channel-list-minimum-users"

	// MARK: People

	/// SwiftUI names the People window itself, so the harness knows it as
	/// the window that holds the People list.
	static let addressBookWindow = addressBookList
	static let addressBookList = "address-book-list"
	static let addressBookAdd = "address-book-add"
	static let addressBookRemove = "address-book-remove"
	static let addressBookAddIgnore = "address-book-add-ignore"
	static let addressBookAddTracking = "address-book-add-tracking"
	static let addressBookEntryHostmask = "address-book-entry-hostmask"
	static let addressBookEntrySave = "address-book-entry-save"

	static func addressBookEntry(_ hostmask: String) -> String {
		"address-book-entry-" + hostmask
	}
}

/** The settings keys the harness seeds. The harness does not link the
 application, so it holds the literals; `SettingsKeyNamingTests` pins them. */
enum SettingsKey {
	static let serverSessions = "Sessions -> Server Sessions"
	static let confirmQuit = "Connection -> Confirm Quit"
	static let onboardingCompleted = "Identity -> Onboarding Completed"
	static let nickname = "Identity -> Nickname"
	static let realName = "Identity -> Real Name"
	static let username = "Identity -> Username"
	static let interactionStyle = "Interaction -> Style"
	static let transcriptTheme = "Theme -> Transcript Theme"
}
