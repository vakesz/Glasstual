/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

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
	static let notifications = NotificationController()
	static let theme = ThemeController()
	static let fileTransfers = FileTransferCenter()

	static let scripts = ScriptController()
	static let messageRules = MessageRuleController()

	private weak static var delegateStorage: ApplicationDelegate?

	static var delegate: ApplicationDelegate! {
		delegateStorage
	}

	static var clientDirectory: ClientDirectory! {
		delegateStorage?.clientDirectory
	}

	static func setDelegate(_ delegate: ApplicationDelegate) {
		delegateStorage = delegate
	}
}
