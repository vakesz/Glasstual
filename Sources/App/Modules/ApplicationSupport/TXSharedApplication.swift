/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

/** The process-wide singletons. Every one of these owns AppKit state, so the
 whole store is main-actor isolated: `static let` gives lazy, once-only creation
 without a lock, and the isolation removes the main-queue hops the Objective-C
 translation needed to reach it from background threads. */
@objc(TXSharedApplication)
@MainActor
public final class SharedApplication: NSObject {
	private static let appearance = Appearance()
	private static let networkReachabilityNotifier = Reachability.reachabilityForInternetConnection()
	private static let notificationController = NotificationController()
	private static let printingQueue = LogControllerPrintingOperationQueue()
	private static let themeController = TPCThemeController()
	private static let windowController = WindowController()
	private static let fileTransferDialog = TDCFileTransferDialog()

	/** An optional rather than a `static let` because callers ask whether speech
	 was ever used (to stop it) without wanting to start the engine. */
	private static var speechSynthesizerStorage: SpeechSynthesizer?

	@objc
	public static func sharedAppearance() -> Appearance {
		appearance
	}

	@objc
	public static func sharedNetworkReachabilityNotifier() -> Reachability {
		networkReachabilityNotifier
	}

	@objc
	public static func sharedNotificationController() -> NotificationController {
		notificationController
	}

	/* ISOLATION-EXCEPTION: plugin dispatch runs on the IRC threads, so this
	 singleton has to stay reachable without the main actor, but `PluginManager`
	 is not yet `Sendable` (its load/unload scheduling flags are plain vars behind
	 an `NSLock`). Owned by the plugin-layer task; drop the annotation once
	 `PluginManager` conforms. */
	private nonisolated(unsafe) static let pluginManager = PluginManager()

	@objc
	public nonisolated static func sharedPluginManager() -> PluginManager {
		pluginManager
	}

	@objc
	public static func sharedPrintingQueue() -> LogControllerPrintingOperationQueue {
		printingQueue
	}

	@objc
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

	@objc
	public static func sharedThemeController() -> TPCThemeController {
		themeController
	}

	@objc
	public static func sharedWindowController() -> WindowController {
		windowController
	}

	@objc
	public static func sharedFileTransferDialog() -> TDCFileTransferDialog {
		fileTransferDialog
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
