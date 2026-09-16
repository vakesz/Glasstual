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
	static let reachability = Reachability.reachabilityForInternetConnection()
	static let notifications = NotificationController()
	static let theme = ThemeController()
	static let fileTransfers = FileTransferCenter()

	static let scripts = ScriptController()
	static let messageRules = MessageRuleController()

	/** An optional rather than a `static let` because callers ask whether speech
	 was ever used (to stop it) without wanting to start the engine. */
	private static var speechStorage: SpeechSynthesizer?

	private weak static var delegateStorage: ApplicationDelegate?

	static var speech: SpeechSynthesizer {
		if let existing = speechStorage {
			return existing
		}

		let created = SpeechSynthesizer()
		speechStorage = created
		return created
	}

	static var existingSpeech: SpeechSynthesizer? {
		speechStorage
	}

	static var delegate: ApplicationDelegate! {
		delegateStorage
	}

	static var world: ClientDirectory! {
		delegateStorage?.world
	}

	static func setDelegate(_ delegate: ApplicationDelegate) {
		delegateStorage = delegate
	}
}
