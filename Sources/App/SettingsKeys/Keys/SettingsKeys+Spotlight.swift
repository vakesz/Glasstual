// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// What Spotlight is told about. Only names ever go in: never message text.
	enum Spotlight {
		private static let group = "Spotlight -> "

		/// Servers and channels, by name.
		static let indexConversations = SettingsKey(group + "Index Conversations", default: true)

		/// Direct conversations, which are named after people.
		static let indexDirectMessages = SettingsKey(group + "Index Direct Messages", default: false)

		static let all: [any AnySettingsKey] = [indexConversations, indexDirectMessages]
	}
}
