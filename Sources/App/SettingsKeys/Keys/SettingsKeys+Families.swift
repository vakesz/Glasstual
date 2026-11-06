// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension SettingsKeys {
	/// Key families whose individual names are made at runtime.
	enum Families {
		/** Per-window saved frames.

		 AppKit writes these itself, under its own prefix plus the window's
		 autosave name, into the application's own domain -- so the pattern is
		 the one `NSWindow.saveFrame(usingName:)` uses and nothing else. */
		static let windowFrames = SettingsKeyFamily(
			"NSWindow Frame ",
			storage: .standard,
			traits: .excludedFromExport
		)

		/// "Do not ask me again" flags, one per prompt, each with the answer it
		/// was given recorded beside it.
		static let alertSuppression = SettingsKeyFamily(
			"Alerts -> ",
			traits: .excludedFromExport
		)

		static let mainWindowState = SettingsKeyFamily(
			"Main Window -> ",
			traits: [.excludedFromExport, .uncatalogued]
		)

		static let all: [SettingsKeyFamily] = [windowFrames, alertSuppression, mainWindowState]
	}
}
