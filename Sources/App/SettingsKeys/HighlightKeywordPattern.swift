// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Validates highlight keywords using the matching mode chosen in Settings.
nonisolated enum HighlightKeywordPattern {
	@MainActor
	static var matchesByRegularExpression: Bool {
		SettingsKeys.Highlights.matchingMethod.value == .regularExpression
	}

	static func validationError(for keyword: String, usesRegularExpression: Bool) -> String? {
		guard usesRegularExpression, isValid(keyword) == false else {
			return nil
		}

		return ApplicationStrings.invalidRegularExpression
	}

	static func isValid(_ pattern: String) -> Bool {
		(try? NSRegularExpression(pattern: pattern)) != nil
	}
}
