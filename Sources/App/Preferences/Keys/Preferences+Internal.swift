// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated extension Preferences {
	/// Bookkeeping the application keeps about itself, and the handful of keys
	/// AppKit or a vendored library reads out of `UserDefaults.standard`.
	enum Internals {
		/// What the current build writes into `dictionaryVersion`. Raised when a
		/// release changes what the stored defaults mean.
		static let currentDictionaryVersion: UInt = 602

		static let dictionaryVersion = PreferenceKey(
			"TPCPreferencesDictionaryVersion",
			default: UInt(0),
			traits: .unregistered
		)

		/** How many times the application has been launched.

		 The count is raised on every launch and read back as an `Int`, so it is
		 bounded the way the other counts are:
		 `Int32.max` launches is past any real number of them, and the launch
		 scrub drops a stored value above it. */
		static let runCount = PreferenceKey(
			"TXRunCount",
			default: UInt(0),
			traits: [.unregistered, .excludedFromExport],
			validation: { $0 <= UInt(Int32.max) }
		)

		/// Foundation reads the per-app language override from the standard domain.
		/// Leave it unregistered so the global language preference remains inherited.
		static let appLanguages = PreferenceKey(
			"AppleLanguages",
			default: [String](),
			storage: .standard,
			traits: [.unregistered, .excludedFromExport]
		)

		static let runTime = PreferenceKey(
			"TXRunTime",
			default: 0.0,
			traits: [.unregistered, .excludedFromExport]
		)

		/// Which pane the preferences window reopens on. Restored state of one
		/// window, so it is not part of the catalogue.
		static let selectedPreferencePane = PreferenceKey(
			"TDCPreferencesController -> Selected Pane",
			default: "",
			traits: [.unregistered, .uncatalogued]
		)

		static let includeAdvancedEncodings = PreferenceKey(
			"Server Properties Window Sheet -> Include Advanced Encodings",
			default: false,
			traits: .unregistered
		)

		/** App Nap is read by AppKit out of the application's own domain, so
		 unlike everything else this one genuinely belongs in `.standard`. The
		 declaration is what says so; it used to be an undocumented exception at
		 the call site. */
		static let appSleepDisabled = PreferenceKey(
			"NSAppSleepDisabled",
			default: false,
			storage: .standard,
			traits: [.unregistered, .uncatalogued]
		)

		static let all: [any AnyPreferenceKey] = [
			dictionaryVersion, runCount, runTime, selectedPreferencePane,
			includeAdvancedEncodings, appSleepDisabled, appLanguages,
		]
	}
}

nonisolated extension Preferences {
	/** The scheme allowlist the transcript's link parser consults.

	 Stored in the application's own domain rather than in the shared container:
	 which schemes this Mac turns into links is a browsing choice, and the
	 connection host has no use for it. */
	enum LinkSchemes {
		static let permittedDefault = PreferenceKey(
			"Link Schemes -> Permitted Default",
			default: [
				"feed", "ftp", "gopher", "irc", "ircs", "itms", "sftp", "ssh",
				"telnet", "glasstual", "textual", "webcal", "x-man-page",
			],
			storage: .standard
		)

		static let permitted = PreferenceKey(
			"Link Schemes -> Permitted",
			default: [String](),
			storage: .standard,
			traits: .unregistered
		)

		/// Makes every scheme a link. A decision this Mac's user makes for
		/// themselves, so no configuration file carries it in or out.
		static let permitAny = PreferenceKey(
			"Link Schemes -> Permit Any",
			default: false,
			storage: .standard,
			traits: [.unregistered, .excludedFromExport]
		)

		static let all: [any AnyPreferenceKey] = [permittedDefault, permitted, permitAny]
	}
}

nonisolated extension Preferences {
	/// Key families whose individual names are made at runtime.
	enum Families {
		/// Per-window saved frames, written by AppKit into the standard domain.
		static let windowFrames = PreferenceKeyFamily(
			"NSWindow Frame -> Internal (v3) -> ",
			storage: .standard,
			traits: .excludedFromExport
		)

		/// A style's own key-value store, keyed by style name.
		static let themeSettings = PreferenceKeyFamily(
			"Internal Theme Settings Key-value Store -> ",
			traits: .excludedFromExport,
			coerce: { _, value in value.dictionary == nil ? nil : value }
		)

		/// "Do not ask me again" flags, one per prompt.
		static let alertSuppression = PreferenceKeyFamily(
			"Text Input Prompt Suppression -> ",
			traits: .excludedFromExport
		)

		static let mainWindowState = PreferenceKeyFamily(
			"Window -> Main Window ",
			traits: [.excludedFromExport, .uncatalogued]
		)

		static let all: [PreferenceKeyFamily] = [
			windowFrames, themeSettings, alertSuppression, mainWindowState,
		]
	}
}
