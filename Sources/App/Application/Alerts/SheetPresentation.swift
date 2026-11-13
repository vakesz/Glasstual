// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/** The window a shared alert hangs its sheet from.

 A static that names a live object: `Application/` installs the main window as
 it builds it and everything else only reads it, which is why the setter is not
 open. `nil` before that window exists, which is when an alert runs application
 modal instead.

 An `NSWindow` rather than the main-window type, because a window is all an
 alert asks of it: whether it is on screen, and what sheet it is already
 showing. */
@MainActor
enum SheetPresentation {
	private(set) weak static var hostWindow: NSWindow?

	/// Called once, from the application delegate, as the main window is built.
	static func install(_ window: NSWindow) {
		hostWindow = window
	}
}
