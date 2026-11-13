// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

// MARK: - Rules

nonisolated extension SettingsKeys {
	/// The message rules the Rules pane edits and the rule engine runs.
	enum Rules {
		private static let group = "Rules -> "

		/// Every rule, as the property list the editor writes.
		static let messageRules = UntypedSettingsKey(
			group + "Message Rules",
			validation: SettingsValueRepair.messageRules
		)

		static let all: [any AnySettingsKey] = [messageRules]
	}
}
