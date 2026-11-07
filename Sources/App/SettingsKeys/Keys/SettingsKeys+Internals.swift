// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// Bookkeeping the application keeps about itself, and the handful of keys
	/// AppKit or a vendored library reads out of `UserDefaults.standard`.
	enum Internals {
		private static let group = "Internals -> "

		/** How many times the application has been launched.

		 The count is raised on every launch and read back as an `Int`, so it is
		 bounded the way the other counts are:
		 `Int32.max` launches is past any real number of them, and the launch
		 scrub drops a stored value above it. */
		static let runCount = SettingsKey(
			group + "Run Count",
			default: UInt(0),
			traits: [.unregistered, .excludedFromExport],
			validation: { $0 <= UInt(Int32.max) }
		)

		static let runTime = SettingsKey(
			group + "Run Time",
			default: 0.0,
			traits: [.unregistered, .excludedFromExport]
		)

		/// Which pane the Settings window reopens on. Restored state of one
		/// window, so it is not part of the catalogue.
		static let selectedSettingsPane = SettingsKey(
			group + "Selected Settings Pane",
			default: "",
			traits: [.unregistered, .uncatalogued]
		)

		/// Foundation reads the per-app language override from the standard domain
		/// under its own name. Leave it unregistered so the global language
		/// setting remains inherited.
		static let appLanguages = SettingsKey(
			"AppleLanguages",
			default: [String](),
			storage: .standard,
			traits: [.unregistered, .excludedFromExport]
		)

		/** App Nap is read by AppKit out of the application's own domain under
		 its own name, so unlike everything else this one genuinely belongs in
		 `.standard`. The declaration is what says so; it used to be an
		 undocumented exception at the call site. */
		static let appSleepDisabled = SettingsKey(
			"NSAppSleepDisabled",
			default: false,
			storage: .standard,
			traits: [.unregistered, .uncatalogued]
		)

		static let all: [any AnySettingsKey] = [
			runCount, runTime, selectedSettingsPane, appSleepDisabled, appLanguages,
		]
	}
}
