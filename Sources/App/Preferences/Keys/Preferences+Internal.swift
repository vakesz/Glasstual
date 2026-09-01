/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

public nonisolated extension Preferences { // nonisolated: value
	/// Bookkeeping the application keeps about itself, and the handful of keys
	/// AppKit or a vendored library reads out of `UserDefaults.standard`.
	enum Internals {
		public static let dictionaryVersion = PreferenceKey(
			"TPCPreferencesDictionaryVersion",
			default: UInt(0),
			traits: .unregistered
		)

		public static let runCount = PreferenceKey(
			"TXRunCount",
			default: UInt(0),
			traits: [.unregistered, .excludedFromExport]
		)

		public static let runTime = PreferenceKey(
			"TXRunTime",
			default: 0.0,
			traits: [.unregistered, .excludedFromExport]
		)

		public static let pluginApprovals = UntypedPreferenceKey(
			"Plugin Approvals",
			default: .emptyDictionary,
			traits: .excludedFromExport
		)

		/// Which pane the preferences window reopens on. Restored state of one
		/// window, so it is not part of the catalogue.
		public static let selectedPreferencePane = PreferenceKey(
			"TDCPreferencesController -> Selected Pane",
			default: "",
			traits: [.unregistered, .uncatalogued]
		)

		public static let includeAdvancedEncodings = PreferenceKey(
			"Server Properties Window Sheet -> Include Advanced Encodings",
			default: false,
			traits: .unregistered
		)

		/** App Nap is read by AppKit out of the application's own domain, so
		 unlike everything else this one genuinely belongs in `.standard`. The
		 declaration is what says so; it used to be an undocumented exception at
		 the call site. */
		public static let appSleepDisabled = PreferenceKey(
			"NSAppSleepDisabled",
			default: false,
			storage: .standard,
			traits: [.unregistered, .uncatalogued]
		)

		static let all: [any AnyPreferenceKey] = [
			dictionaryVersion, runCount, runTime, pluginApprovals, selectedPreferencePane,
			includeAdvancedEncodings, appSleepDisabled,
		]
	}
}

public nonisolated extension Preferences { // nonisolated: value
	/// The scheme allowlist the vendored AutoHyperlinks parser consults. It
	/// reads `UserDefaults.standard` directly, so the keys live there.
	enum LinkSchemes {
		public static let permittedDefault = PreferenceKey(
			"com.adiumX.AutoHyperlinks.permittedSchemesDefault",
			default: [
				"feed", "ftp", "gopher", "irc", "ircs", "itms", "sftp", "ssh",
				"telnet", "glasstual", "webcal", "x-man-page",
			],
			storage: .standard
		)

		public static let permitted = PreferenceKey(
			"com.adiumX.AutoHyperlinks.permittedSchemes",
			default: [String](),
			storage: .standard,
			traits: .unregistered
		)

		public static let permitAny = PreferenceKey(
			"com.adiumX.AutoHyperlinks.permittedSchemesAny",
			default: false,
			storage: .standard,
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = [permittedDefault, permitted, permitAny]
	}
}

public nonisolated extension Preferences { // nonisolated: value
	/// Key families whose individual names are made at runtime.
	enum Families {
		/// Per-window saved frames, written by AppKit into the standard domain.
		public static let windowFrames = PreferenceKeyFamily(
			"NSWindow Frame -> Internal (v3) -> ",
			storage: .standard,
			traits: .excludedFromExport
		)

		/// A style's own key-value store, keyed by style name.
		public static let themeSettings = PreferenceKeyFamily(
			"Internal Theme Settings Key-value Store -> ",
			traits: .excludedFromExport
		)

		/// "Do not ask me again" flags, one per prompt.
		public static let alertSuppression = PreferenceKeyFamily(
			"Text Input Prompt Suppression -> ",
			traits: .excludedFromExport
		)

		public static let mainWindowState = PreferenceKeyFamily(
			"Window -> Main Window ",
			traits: [.excludedFromExport, .uncatalogued]
		)

		static let all: [PreferenceKeyFamily] = [
			windowFrames, themeSettings, alertSuppression, mainWindowState,
			Preferences.Notifications.family, Preferences.Input.textFieldFamily,
		]
	}
}
