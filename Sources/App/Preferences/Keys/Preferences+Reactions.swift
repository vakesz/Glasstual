/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

public nonisolated extension Preferences { // nonisolated: value
	/// What the reaction picker offers first.
	enum Reactions {
		/// The emoji the user has reacted with, most recent first. Kept short by
		/// `RecentReactions`; the picker fills the rest of the row from its
		/// common set.
		public static let recent = PreferenceKey(
			"Reactions -> Recently Used",
			default: [String](),
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = [recent]
	}
}
