/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

// MARK: - Rules

nonisolated extension Preferences { // nonisolated: value
	/// The message rules the Rules pane edits and the rule engine runs.
	enum Rules {
		/** Every rule, as the property list the editor has always written.

		 The name is the one the rules were stored under when they belonged to a
		 bundled extension, so a user's rules survive that extension going away. */
		static let messageRules = UntypedPreferenceKey(
			"Glasstual Chat Filter Extension -> Filters",
			validation: PreferencesPayloadValidation.messageRules
		)

		static let all: [any AnyPreferenceKey] = [messageRules]
	}
}
