// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Whether a highlight keyword is one the matcher can actually use.

 The Highlights pane decides how every keyword is matched, so a keyword saved
 while that is Regular Expression has to compile. Nothing used to check: the
 renderer builds the expression with `try?` and an unusable pattern simply
 stopped highlighting, with nothing said anywhere. */
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
