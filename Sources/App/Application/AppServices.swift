// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Long-lived dependencies owned by the running application, and the running
 application delegate itself. The store is main-actor isolated because the
 delegate coordinates these lifecycles and several of them publish UI state.

 `delegate` is implicitly unwrapped because the app's UI and IRC layers only run
 while a delegate exists. It replaces the `NSObject` category the Objective-C
 code used to reach the delegate from anywhere. */
@MainActor
enum AppServices {
	static let appearance = Appearance()
	static let scenes = ApplicationScenes()
	static let notifications = UserNotificationController()

	/* What each windowed feature has open. The scene bridge above installs and
	 opens the windows; these own what is inside them. */
	static let serverChannelLists = ServerChannelListWindowSessions()
	static let highlightLogs = HighlightLogWindowSessions()
	static let addressBooks = AddressBookWindowSessions()
	static let channelSpotlight = ChannelSpotlightWindow()
	static let channelMaskList = ChannelMaskListWindow()
	static let transcriptLogViewer = TranscriptLogViewerWindow()
	static let scrollbackSearch = ScrollbackSearchWindow()
	static let serverProperties = ServerPropertiesWindows(save: MenuSheetPresenter.saveServerProperties)

	/// Every question waiting for an answer, and the one place questions are
	/// asked, as alerts or in the conversation.
	static let promptRegistry = PendingPromptRegistry()
	static let prompts = PromptRouter(registry: promptRegistry)
	/// `/serverconfig`, `/channelconfig` and `/setcolor` with a colour.
	static let configurationCommands = ConfigurationCommands()

	static let theme = ThemeStore()
	static let fileTransfers = FileTransferStore()

	/// What Shortcuts, Siri and Spotlight may ask of the chat session, and the
	/// index that tells Spotlight about its conversations.
	static let intentActions: any IntentActions = ChatSessionIntentActions(
		chatSession: { AppServices.chatSession },
		openLink: { _ = ApplicationLinkHandler.open($0) }
	)
	static let conversationIndex = ConversationIndexCoordinator(actions: AppServices.intentActions)

	static let scripts = ScriptCatalogStore()
	static let messageRules = MessageRules()

	/// What every transcript renders a printed line against, kept so a line does
	/// not read the defaults store.
	static let transcriptSettings = TranscriptSettingsStore()

	private weak static var delegateStorage: ApplicationDelegate?

	static var delegate: ApplicationDelegate! {
		delegateStorage
	}

	static var chatSession: ChatSession! {
		delegateStorage?.chatSession
	}

	static func setDelegate(_ delegate: ApplicationDelegate) {
		delegateStorage = delegate
	}
}

extension FileLogCommands {
	/** The one queue every transcript file log writes through, composed here
	 with the alert the disk filling up raises.

	 Telling the user there is no room left is presentation, and the sink only
	 reports that a write ran out of it, so the alert is installed by
	 `Application/` like every other live object the lower layers read. */
	static let shared = FileLogCommands(reportNoSpace: { FileLogAlerts.reportNoSpace() })
}

extension KeychainPersistence {
	/// The process-wide credential writer, composed here with the application's
	/// error presenter: a static that names a live object is installed by
	/// `Application/` and read as a service everywhere else.
	static let shared = KeychainPersistence(reportFailure: { error, retry in
		KeychainAlerts.showFailure(error, about: PromptScope(origin: .application, revealsMainWindow: false), retry: retry)
	})
}

extension ChatServices {
	static let shared = ChatServices(
		certificates: CertificatePresenter(),
		connectToServer: ServerConnection.connect(using:)
	)
}

extension DCCPeerCertificateStore {
	/// The certificates the user trusts for secure DCC peers, kept beside the
	/// application's other support files.
	static let shared = DCCPeerCertificateStore(
		fileURL: ApplicationPaths.groupContainerApplicationSupportURL?
			.appendingPathComponent("DCC Peer Certificates.plist", isDirectory: false)
	)
}

extension DCCLocalIdentityStore {
	/// Each network's secure DCC identity, kept in the keychain.
	static let shared = DCCLocalIdentityStore(storage: KeychainDCCIdentityStorage())
}

extension STSPolicyStore {
	static let applicationStore = STSPolicyStore(userDefaults: GlasstualUserDefaults.container)
}

extension Scrollback {
	static let shared = Scrollback()
}

extension ScrollbackSession {
	static let shared = ScrollbackSession()
}

extension InlineImageLoader {
	static let shared = InlineImageLoader()
}

extension TranscriptHighlightExpressions {
	/// The compiled highlight keywords every transcript renders with.
	static let shared = TranscriptHighlightExpressions()
}

extension InlineImageBudget {
	static let shared = InlineImageBudget()
}

extension RemoteImageStore {
	/// The icons networks advertise, shared by every server row.
	static let networkIcons = RemoteImageStore(configuration: .networkIcons)
	/// The profile pictures people set on the server, shared by member rows and
	/// transcript headers.
	static let avatars: RemoteImageStore = {
		let store = RemoteImageStore(configuration: .avatars)
		store.releaseOwner(on: SessionProfilesDidChange.self) { $0.isReset ? $0.subject.uniqueIdentifier : nil }
		return store
	}()
}

extension SettingsTransferSession {
	static let shared = SettingsTransferSession()
}

extension SettingsSaveQueue {
	static let shared = SettingsSaveQueue()
}

extension SettingsEditingSession {
	static let shared = SettingsEditingSession()
}

extension ChatEnvironment {
	/// Live setting values against the application's services.
	static var application: ChatEnvironment {
		ChatEnvironment(settings: .current(), services: ChatServices.shared)
	}
}
