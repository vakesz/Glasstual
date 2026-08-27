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

	private static func once<T: AnyObject>(
		_ storage: inout T?,
		create: () -> T
	) -> T {
		lock.lock()
		if let existing = storage {
			lock.unlock()
			return existing
		}
		lock.unlock()

		let created = create()

		lock.lock()
		if let existing = storage {
			lock.unlock()
			return existing
		}
		storage = created
		lock.unlock()
		return created
	}

	@objc
	public static func sharedAppearance() -> Appearance {
		once(&appearance) {
			if Thread.isMainThread {
				return MainActor.assumeIsolated { Appearance() }
			}

			return DispatchQueue.main.sync {
				MainActor.assumeIsolated { Appearance() }
			}
		}
	}

	@objc
	public static func sharedNetworkReachabilityNotifier() -> Reachability {
		once(&networkReachabilityNotifier, create: Reachability.reachabilityForInternetConnection)
	}

	@objc
	public static func sharedNotificationController() -> NotificationController {
		once(&notificationController) {
			if Thread.isMainThread {
				return MainActor.assumeIsolated { NotificationController() }
			}

			return DispatchQueue.main.sync {
				MainActor.assumeIsolated { NotificationController() }
			}
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
		once(&themeController) {
			if Thread.isMainThread {
				return MainActor.assumeIsolated { TPCThemeController() }
			}

			return DispatchQueue.main.sync {
				MainActor.assumeIsolated { TPCThemeController() }
			}
		}
	}

	@objc
	public static func sharedWindowController() -> WindowController {
		once(&windowController, create: WindowController.init)
	}

	@objc
	public static func sharedFileTransferDialog() -> TDCFileTransferDialog {
		once(&fileTransferDialog) {
			if Thread.isMainThread {
				return MainActor.assumeIsolated { TDCFileTransferDialog() }
			}

			return DispatchQueue.main.sync {
				MainActor.assumeIsolated { TDCFileTransferDialog() }
			}
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
