// Copyright (c) 2016 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions

/** Where the name of the database file is kept between launches.

 A pair of closures rather than a protocol: the only thing that varies is where
 the name comes from and goes, and a test wants a rename reported rather than
 followed. */
nonisolated struct ScrollbackFilenameSetting: Sendable {
	let load: @Sendable () -> String?
	let save: @Sendable (String?) -> Void

	/// The typed setting that remembers the existing on-disk database name.
	static let stored = ScrollbackFilenameSetting(
		load: {
			let value = SettingsKeys.Logging.scrollbackDatabaseFileName.detachedStoredValue
			return value?.isEmpty == false ? value : nil
		},
		save: { SettingsKeys.Logging.scrollbackDatabaseFileName.detachedStoredValue = $0 }
	)
}
