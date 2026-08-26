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

import AppKit
import os

private let windowControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "WindowController"
)

@objc(TXWindowController)
public final class WindowController: NSObject {
	private var windowObjects: NSMutableDictionary? = NSMutableDictionary()

	override public init() {
		super.init()
	}

	@objc public func prepareForApplicationTermination() {
		windowControllerLogger.debug("Preparing window controller")

		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		windowObjects?.removeAllObjects()
		windowObjects = nil
	}

	@objc(windowDescriptionForWindow:)
	public class func windowDescription(for window: Any) -> String {
		windowDescription(for: window, inRelationTo: nil)
	}

	@objc(windowDescriptionForWindow:inRelationTo:)
	public class func windowDescription(for window: Any, inRelationTo relatedObject: Any?) -> String {
		let windowClass = NSStringFromClass(type(of: window as AnyObject))

		guard let relatedObject else {
			return windowClass
		}

		return "\(windowClass) -> \(String(describing: relatedObject))"
	}

	@objc(addWindowToWindowList:)
	public func addWindow(toWindowList window: Any) {
		addWindow(toWindowList: window, inRelationTo: nil)
	}

	@objc(addWindowToWindowList:inRelationTo:)
	public func addWindow(toWindowList window: Any, inRelationTo relatedObject: Any?) {
		let description = Self.windowDescription(for: window, inRelationTo: relatedObject)
		addWindow(toWindowList: window, withDescription: description)
	}

	@objc(addWindowToWindowList:withDescription:)
	public func addWindow(toWindowList window: Any, withDescription windowDescription: String) {
		precondition((window as AnyObject).responds(to: NSSelectorFromString("window")))

		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		windowObjects?[windowDescription] = window
	}

	@objc(removeWindowFromWindowList:)
	public func removeWindow(fromWindowList window: Any) {
		removeWindow(fromWindowList: window, inRelationTo: nil)
	}

	@objc(removeWindowFromWindowList:inRelationTo:)
	public func removeWindow(fromWindowList window: Any, inRelationTo relatedObject: Any?) {
		if let windows = window as? [Any] {
			for object in windows {
				removeWindow(fromWindowList: object, inRelationTo: relatedObject)
			}
			return
		}

		var windowWasString = false
		var windowDescription: String?

		if let windowString = window as? String {
			windowWasString = true
			windowDescription = windowString
		} else {
			windowDescription = Self.windowDescription(for: window, inRelationTo: relatedObject)
		}

		guard var windowDescription else {
			return
		}

		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		if windowObjects?[windowDescription] == nil, windowWasString == false {
			if let key = (windowObjects as NSDictionary?)?.firstKey(for: window) as? String {
				windowDescription = key
			}
		}

		windowObjects?.removeObject(forKey: windowDescription)
	}

	@objc(windowFromWindowList:)
	public func window(fromWindowList windowDescription: String) -> Any? {
		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		return windowObjects?[windowDescription]
	}

	@objc(windowsFromWindowList:)
	public func windows(fromWindowList windowDescriptions: [String]) -> [Any] {
		objc_sync_enter(self)
		defer { objc_sync_exit(self) }

		var returnedValues: [Any] = []

		for windowDescription in windowDescriptions {
			if let windowObject = windowObjects?[windowDescription] {
				returnedValues.append(windowObject)
			}
		}

		return returnedValues
	}

	@objc(maybeBringWindowForward:)
	@MainActor public func maybeBringWindowForward(_ windowDescription: String) -> Bool {
		guard let windowObject = window(fromWindowList: windowDescription) as AnyObject? else {
			return false
		}

		guard windowObject.responds(to: NSSelectorFromString("window")),
		      let window = windowObject.value(forKey: "window") as? NSWindow
		else {
			return false
		}

		window.makeKeyAndOrderFront(nil)
		return true
	}

	@MainActor @objc public func popMainWindowSheetIfExists() {
		guard let attachedSheet = NSObject.masterController().mainWindow.attachedSheet else {
			return
		}

		attachedSheet.close()
	}
}
