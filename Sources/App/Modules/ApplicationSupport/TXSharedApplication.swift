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

	nonisolated(unsafe) private static var appearance: Appearance?
	nonisolated(unsafe) private static var networkReachabilityNotifier: Reachability?
	nonisolated(unsafe) private static var notificationController: NotificationController?
	nonisolated(unsafe) private static var pluginManager: PluginManager?
	nonisolated(unsafe) private static var printingQueue: LogControllerPrintingOperationQueue?
	nonisolated(unsafe) private static var speechSynthesizer: SpeechSynthesizer?
	nonisolated(unsafe) private static var themeController: TPCThemeController?
	nonisolated(unsafe) private static var windowController: WindowController?
	nonisolated(unsafe) private static var fileTransferDialog: TDCFileTransferDialog?

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

	@objc
	public class func sharedThemeController() -> TPCThemeController {
		once(&themeController, create: TPCThemeController.init)
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

extension NSObject {
	nonisolated(unsafe) private static weak var globalMasterControllerReference: TXMasterController?

	@objc
	public class func setGlobalMasterControllerClassReference(_ masterController: TXMasterController) {
		globalMasterControllerReference = masterController
	}

	@objc(masterController)
	public var masterController: TXMasterController {
		Self.globalMasterControllerReference!
	}

	@objc(masterController)
	public class func masterController() -> TXMasterController {
		globalMasterControllerReference!
	}
}
