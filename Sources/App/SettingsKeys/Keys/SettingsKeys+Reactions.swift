// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// What the transcript's reaction picker offers first.
	enum Reactions {
		private static let group = "Reactions -> "

		/// The emoji the user has reacted with, most recent first. Kept short by
		/// `RecentReactions`; the picker fills the rest of the row from its
		/// common set.
		static let recent = SettingsKey(
			group + "Recently Used",
			default: [String](),
			traits: .unregistered
		)

		static let all: [any AnySettingsKey] = [recent]
	}
}
