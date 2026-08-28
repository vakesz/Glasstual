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
import Synchronization

private nonisolated let windowControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "WindowController"
)

@objc(TXWindowController)
public final nonisolated class WindowController: NSObject {
	private struct RegistryState: @unchecked Sendable {
		var windows: [String: AnyObject] = [:]
		var isTerminated = false
	}

	private let registry = Mutex(RegistryState())

	override public init() {
		super.init()
	}

	@objc public func prepareForApplicationTermination() {
		windowControllerLogger.debug("Preparing window controller")

		registry.withLock { state in
			state.windows.removeAll()
			state.isTerminated = true
		}
	}

	@objc(windowDescriptionForWindow:)
	public static func windowDescription(for window: Any) -> String {
		windowDescription(for: window, inRelationTo: nil)
	}

	@objc(windowDescriptionForWindow:inRelationTo:)
	public static func windowDescription(for window: Any, inRelationTo relatedObject: Any?) -> String {
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
		let windowObject = window as AnyObject
		precondition(
			windowObject is NSWindowController || windowObject is WindowBase || windowObject is SheetBase
		)

		registry.withLock { state in
			guard state.isTerminated == false else {
				return
			}

			state.windows[windowDescription] = windowObject
		}
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

		registry.withLock { state in
			if state.windows[windowDescription] == nil, windowWasString == false {
				let windowObject = window as AnyObject
				if let matchingEntry = state.windows.first(where: { $0.value === windowObject }) {
					windowDescription = matchingEntry.key
				}
			}

			state.windows.removeValue(forKey: windowDescription)
		}
	}

	@objc(windowFromWindowList:)
	public func window(fromWindowList windowDescription: String) -> Any? {
		registry.withLock { $0.windows[windowDescription] }
	}

	@objc(windowsFromWindowList:)
	public func windows(fromWindowList windowDescriptions: [String]) -> [Any] {
		registry.withLock { state in
			windowDescriptions.compactMap { state.windows[$0] }
		}
	}

	@objc(maybeBringWindowForward:)
	@MainActor public func maybeBringWindowForward(_ windowDescription: String) -> Bool {
		guard let windowObject = window(fromWindowList: windowDescription) as AnyObject?,
		      let window = Self.window(for: windowObject)
		else {
			return false
		}

		window.makeKeyAndOrderFront(nil)
		return true
	}

	@MainActor
	private static func window(for object: AnyObject) -> NSWindow? {
		switch object {
		case let windowController as NSWindowController:
			windowController.window
		case let windowController as WindowBase:
			windowController.window
		case let sheetController as SheetBase:
			sheetController.window
		default:
			nil
		}
	}

	@MainActor @objc public func popMainWindowSheetIfExists() {
		guard let attachedSheet = NSObject.applicationController().mainWindow.attachedSheet else {
			return
		}

		attachedSheet.close()
	}
}
