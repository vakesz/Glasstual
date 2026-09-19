// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/** The scheme allowlist the transcript's link parser consults.

	 Stored in the application's own domain rather than in the shared container:
	 which schemes this Mac turns into links is a browsing choice, and the
	 connection host has no use for it. */
	enum LinkSchemes {
		private static let group = "Link Schemes -> "

		static let permittedDefault = SettingsKey(
			group + "Permitted Default",
			default: [
				"feed", "ftp", "gopher", "irc", "ircs", "itms", "sftp", "ssh",
				"telnet", "glasstual", "webcal", "x-man-page",
			],
			storage: .standard
		)

		static let permitted = SettingsKey(
			group + "Permitted",
			default: [String](),
			storage: .standard,
			traits: .unregistered
		)

		/// Makes every scheme a link. A decision this Mac's user makes for
		/// themselves, so no configuration file carries it in or out.
		static let permitAny = SettingsKey(
			group + "Permit Any",
			default: false,
			storage: .standard,
			traits: [.unregistered, .excludedFromExport]
		)

		static let all: [any AnySettingsKey] = [permittedDefault, permitted, permitAny]
	}
}
