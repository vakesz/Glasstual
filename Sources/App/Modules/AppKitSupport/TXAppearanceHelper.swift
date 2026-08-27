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

public extension NSView {
	@objc var needsDisplayWhenApplicationAppearanceChanges: Bool {
		false
	}

	@objc var needsDisplayWhenSystemAppearanceChanges: Bool {
		false
	}

	@objc var sendApplicationAppearanceChangedToSubviews: Bool {
		true
	}

	@objc var sendSystemAppearanceChangedToSubviews: Bool {
		true
	}

	@objc func applicationAppearanceChanged() {
		if needsDisplayWhenApplicationAppearanceChanges {
			needsDisplay = true
		}
	}

	@objc func systemAppearanceChanged() {
		if needsDisplayWhenSystemAppearanceChanges {
			needsDisplay = true
		}
	}

	@objc func notifyApplicationAppearanceChanged() {
		applicationAppearanceChanged()

		guard sendApplicationAppearanceChangedToSubviews else {
			return
		}

		for view in subviews {
			view.notifyApplicationAppearanceChanged()
		}
	}

	@objc func notifySystemAppearanceChanged() {
		systemAppearanceChanged()

		guard sendSystemAppearanceChangedToSubviews else {
			return
		}

		for view in subviews {
			view.notifySystemAppearanceChanged()
		}
	}
}

public extension NSWindow {
	@objc func notifyApplicationAppearanceChanged() {
		contentView?.superview?.notifyApplicationAppearanceChanged()

		for viewController in titlebarAccessoryViewControllers {
			viewController.view.notifyApplicationAppearanceChanged()
		}
	}

	@objc func notifySystemAppearanceChanged() {
		contentView?.superview?.notifySystemAppearanceChanged()

		for viewController in titlebarAccessoryViewControllers {
			viewController.view.notifySystemAppearanceChanged()
		}
	}
}
