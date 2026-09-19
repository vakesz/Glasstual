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
	static let channelSpotlight = ChannelSpotlightWindow()
	static let channelMaskList = ChannelMaskListWindow()

	static let theme = ThemeStore()
	static let fileTransfers = FileTransferStore()

	static let scripts = ScriptCatalogStore()
	static let messageRules = MessageRules()

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
		KeychainAlerts.showFailure(error, retry: retry)
	})
}
