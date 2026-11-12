// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CoreGraphics

/** The measurements the Settings window is built to.

 Row gaps come from `UISpacing` and sheet margins from `SheetMetrics`, which
 the whole application shares; what is left here is what only this window has
 an opinion about: the sizes the sidebar and the widest form are chosen
 against. */
enum SettingsWindowMetrics {
	/// Wide enough for the longest sidebar title without leaving the detail
	/// column short of the forms it has to draw.
	static let sidebarWidth = 200.0
	/// What the window opens at: the sidebar plus a detail column that fits the
	/// widest pane without wrapping its labels.
	static let windowSize = CGSize(width: 820, height: 640)
	/// How far it can be taken in: every pane still draws, with scrolling.
	static let minimumWindowSize = CGSize(width: 720, height: 520)
}
