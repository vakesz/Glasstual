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
import os

@objc(TXSharedApplication)
public final class SharedApplication: NSObject {
	private static let lock = NSLock()

	private nonisolated(unsafe) static var appearance: Appearance?
	private nonisolated(unsafe) static var networkReachabilityNotifier: Reachability?
	private nonisolated(unsafe) static var notificationController: NotificationController?
	private nonisolated(unsafe) static var pluginManager: PluginManager?
	private nonisolated(unsafe) static var printingQueue: LogControllerPrintingOperationQueue?
	private nonisolated(unsafe) static var speechSynthesizer: SpeechSynthesizer?
	private nonisolated(unsafe) static var themeController: TPCThemeController?
	private nonisolated(unsafe) static var windowController: WindowController?
	private nonisolated(unsafe) static var fileTransferDialog: TDCFileTransferDialog?

	/** The lock is held across `create()` so that two callers cannot both build the
	 value. Callers whose value must be built on the main actor hop there *before*
	 calling this, so the lock is never held across a main-queue wait. */
	private static func once<T: AnyObject>(
		_ storage: inout T?,
		create: () -> T
	) -> T {
		lock.lock()
		defer { lock.unlock() }

		if let existing = storage {
			return existing
		}

		let created = create()
		storage = created
		return created
	}

	@objc
	public static func sharedAppearance() -> Appearance {
		guard Thread.isMainThread else {
			return DispatchQueue.main.sync { sharedAppearance() }
		}

		return once(&appearance) {
			MainActor.assumeIsolated { Appearance() }
		}
	}

	@objc
	public static func sharedNetworkReachabilityNotifier() -> Reachability {
		once(&networkReachabilityNotifier, create: Reachability.reachabilityForInternetConnection)
	}

	@objc
	public static func sharedNotificationController() -> NotificationController {
		guard Thread.isMainThread else {
			return DispatchQueue.main.sync { sharedNotificationController() }
		}

		return once(&notificationController) {
			MainActor.assumeIsolated { NotificationController() }
		}
	}

	@objc
	public static func sharedPluginManager() -> PluginManager {
		once(&pluginManager, create: PluginManager.init)
	}

	@objc
	public static func sharedPrintingQueue() -> LogControllerPrintingOperationQueue {
		once(&printingQueue, create: LogControllerPrintingOperationQueue.init)
	}

	@objc
	public static func sharedSpeechSynthesizer() -> SpeechSynthesizer {
		once(&speechSynthesizer, create: SpeechSynthesizer.init)
	}

	public static func existingSpeechSynthesizer() -> SpeechSynthesizer? {
		lock.lock()
		defer { lock.unlock() }

		return speechSynthesizer
	}

	@objc
	public static func sharedThemeController() -> TPCThemeController {
		guard Thread.isMainThread else {
			return DispatchQueue.main.sync { sharedThemeController() }
		}

		return once(&themeController) {
			MainActor.assumeIsolated { TPCThemeController() }
		}
	}

	@objc
	public static func sharedWindowController() -> WindowController {
		once(&windowController, create: WindowController.init)
	}

	@objc
	public static func sharedFileTransferDialog() -> TDCFileTransferDialog {
		guard Thread.isMainThread else {
			return DispatchQueue.main.sync { sharedFileTransferDialog() }
		}

		return once(&fileTransferDialog) {
			MainActor.assumeIsolated { TDCFileTransferDialog() }
		}
	}
}

public extension NSObject {
	private nonisolated(unsafe) weak static var globalApplicationControllerReference: ApplicationController?

	@objc(setGlobalMasterControllerClassReference:)
	class func setGlobalApplicationControllerReference(_ applicationController: ApplicationController) {
		globalApplicationControllerReference = applicationController
	}

	@objc(masterController)
	var applicationController: ApplicationController {
		Self.globalApplicationControllerReference!
	}

	@objc(masterController)
	class func applicationController() -> ApplicationController {
		globalApplicationControllerReference!
	}
}
