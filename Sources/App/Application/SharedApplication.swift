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

/** Long-lived dependencies owned by the running application. The store is
 main-actor isolated because their lifecycle is coordinated by the application
 delegate and several publish UI state. `PluginManager` is the deliberate
 exception: plugin dispatch crosses IRC isolation domains and the manager's
 public contract is `Sendable`. */
@MainActor
public enum SharedApplication {
	private static let appearance = Appearance()
	private static let applicationScenes = ApplicationScenes()
	private static let networkReachabilityNotifier = Reachability.reachabilityForInternetConnection()
	private static let notificationController = NotificationController()
	private static let themeController = ThemeController()
	private static let fileTransferCenter = FileTransferCenter()

	/** An optional rather than a `static let` because callers ask whether speech
	 was ever used (to stop it) without wanting to start the engine. */
	private static var speechSynthesizerStorage: SpeechSynthesizer?

	public static func sharedAppearance() -> Appearance {
		appearance
	}

	static func sharedApplicationScenes() -> ApplicationScenes {
		applicationScenes
	}

	public static func sharedNetworkReachabilityNotifier() -> Reachability {
		networkReachabilityNotifier
	}

	public static func sharedNotificationController() -> NotificationController {
		notificationController
	}

	/// Plugin dispatch runs on the IRC threads, so this singleton has to stay
	/// reachable without the main actor; `PluginManager` is `Sendable`.
	private nonisolated static let pluginManager = PluginManager() // nonisolated: let

	public nonisolated static func sharedPluginManager() -> PluginManager { // nonisolated: let
		pluginManager
	}

	public static func sharedSpeechSynthesizer() -> SpeechSynthesizer {
		if let existing = speechSynthesizerStorage {
			return existing
		}

		let created = SpeechSynthesizer()
		speechSynthesizerStorage = created
		return created
	}

	public static func existingSpeechSynthesizer() -> SpeechSynthesizer? {
		speechSynthesizerStorage
	}

	public static func sharedThemeController() -> ThemeController {
		themeController
	}

	public static func sharedFileTransferCenter() -> FileTransferCenter {
		fileTransferCenter
	}
}

/** The running `ApplicationController`.

 This replaces the `NSObject` category the Objective-C code used to reach the
 controller from anywhere. `shared` is implicitly unwrapped because the app's UI
 and IRC layers only run while a controller exists; use `current` in code that
 can also run before the main nib wakes or during teardown. */
@MainActor
public enum AppController {
	public private(set) weak static var current: ApplicationController?

	public static var shared: ApplicationController! {
		current
	}

	static func setCurrent(_ controller: ApplicationController) {
		current = controller
	}
}
