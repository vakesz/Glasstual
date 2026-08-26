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
	public class func sharedAppearance() -> Appearance {
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
	public class func sharedNetworkReachabilityNotifier() -> Reachability {
		once(&networkReachabilityNotifier, create: Reachability.reachabilityForInternetConnection)
	}

	@objc
	public class func sharedNotificationController() -> NotificationController {
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
	public class func sharedPluginManager() -> PluginManager {
		once(&pluginManager, create: PluginManager.init)
	}

	@objc
	public class func sharedPrintingQueue() -> LogControllerPrintingOperationQueue {
		once(&printingQueue, create: LogControllerPrintingOperationQueue.init)
	}

	@objc
	public class func sharedSpeechSynthesizer() -> SpeechSynthesizer {
		once(&speechSynthesizer, create: SpeechSynthesizer.init)
	}

	public class func existingSpeechSynthesizer() -> SpeechSynthesizer? {
		lock.lock()
		defer { lock.unlock() }

		return speechSynthesizer
	}

	@objc
	public class func sharedThemeController() -> TPCThemeController {
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
	public class func sharedWindowController() -> WindowController {
		once(&windowController, create: WindowController.init)
	}

	@objc
	public class func sharedFileTransferDialog() -> TDCFileTransferDialog {
		once(&fileTransferDialog, create: TDCFileTransferDialog.init)
	}
}

public extension NSObject {
	private nonisolated(unsafe) weak static var globalMasterControllerReference: MasterController?

	@objc
	class func setGlobalMasterControllerClassReference(_ masterController: MasterController) {
		globalMasterControllerReference = masterController
	}

	@objc(masterController)
	var masterController: MasterController {
		Self.globalMasterControllerReference!
	}

	@objc(masterController)
	class func masterController() -> MasterController {
		globalMasterControllerReference!
	}
}
