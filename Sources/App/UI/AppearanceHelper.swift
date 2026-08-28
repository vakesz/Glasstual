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

import AppKit

/// A view that reacts to the application's or the system's appearance
/// changing. Views that do not conform are still walked through so that their
/// subviews are reached.
///
/// This used to be eight `@objc` members on an extension of `NSView`, which
/// every view in the application advertised and subclasses overrode through
/// the runtime.
@MainActor
public protocol AppearanceObserving: NSView {
	/// The application's own light/dark setting changed.
	func applicationAppearanceChanged()
	/// The system's appearance changed while the application follows it.
	func systemAppearanceChanged()
}

public extension AppearanceObserving {
	func applicationAppearanceChanged() {
		needsDisplay = true
	}

	func systemAppearanceChanged() {
		needsDisplay = true
	}
}

public extension NSView {
	/// Tells this view and every view beneath it that the application's
	/// appearance changed.
	func notifyApplicationAppearanceChanged() {
		(self as? any AppearanceObserving)?.applicationAppearanceChanged()

		for view in subviews {
			view.notifyApplicationAppearanceChanged()
		}
	}

	/// Tells this view and every view beneath it that the system's appearance
	/// changed.
	func notifySystemAppearanceChanged() {
		(self as? any AppearanceObserving)?.systemAppearanceChanged()

		for view in subviews {
			view.notifySystemAppearanceChanged()
		}
	}
}

public extension NSWindow {
	func notifyApplicationAppearanceChanged() {
		contentView?.superview?.notifyApplicationAppearanceChanged()

		for viewController in titlebarAccessoryViewControllers {
			viewController.view.notifyApplicationAppearanceChanged()
		}
	}

	func notifySystemAppearanceChanged() {
		contentView?.superview?.notifySystemAppearanceChanged()

		for viewController in titlebarAccessoryViewControllers {
			viewController.view.notifySystemAppearanceChanged()
		}
	}
}
