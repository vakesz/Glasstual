// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import SwiftUI

/// Where an alert appears.
@MainActor
enum AlertPresentation {
	/// A state-driven sheet on the application's main window. Reveals the
	/// installed window when it is closed, minimised or hidden. Before a
	/// window is installed, the alert runs application modal instead.
	case mainWindow
	/// A sheet on the main window, or on any other visible window. Reveals the
	/// installed main window when none is visible. During launch and migration
	/// no window exists yet, and the alert runs application modal instead.
	case anyVisibleWindow
}
