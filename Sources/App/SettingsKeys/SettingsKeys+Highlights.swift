// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** One entry of a highlight list.

 The list is stored as an array of single-field records rather than an array of
 strings, so the field name is spelled out here once instead of being rebuilt
 from `["string": …]` literals at every use. */
nonisolated struct HighlightKeyword: Hashable, Sendable {
	static let field = "string"

	var string: String
}

nonisolated extension HighlightKeyword: SettingValue {
	static func settingValue(from object: Any) -> HighlightKeyword? {
		guard let string = PropertyListValue(propertyList: object)?.dictionary?[field]?.string else {
			return nil
		}

		return HighlightKeyword(string: string)
	}

	var settingObject: Any? {
		[Self.field: string]
	}
}

nonisolated extension SettingsKeys {
	/// Which incoming text counts as a highlight.
	enum Highlights {
		private static let group = "Highlights -> "

		static let matchingMethod = SettingsKey(
			group + "Matching Method",
			default: NicknameHighlightMatchMode.exact
		)

		static let trackLocalNickname = SettingsKey(group + "Track Local Nickname", default: true)

		static let matchKeywords = SettingsKey(
			group + "Match Keywords",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		static let excludeKeywords = SettingsKey(
			group + "Exclude Keywords",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		static let all: [any AnySettingsKey] = [
			matchingMethod, trackLocalNickname, matchKeywords, excludeKeywords,
		]
	}
}

nonisolated extension SettingsKeys.Highlights {
	/** The keywords a stored list actually matches on.

	 One implementation, because both the connection layer's snapshot and the
	 maintenance pass that rewrites the stored list have to agree on which
	 entries count: an empty entry matches everything, so it is not a keyword
	 at all, and neither is one that is only spaces, which Settings already
	 shows as blank. Surrounding whitespace is dropped for the same reason: a
	 keyword is what the list shows. */
	static func keywords(in list: [HighlightKeyword]) -> [String] {
		list.map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
	}
}

@MainActor
extension SettingsKeys.Highlights {
	/// Drops the entries that match nothing and sorts what is left, so the
	/// Settings list and the stored value stay in one order.
	static func cleanUpStoredKeywords() {
		clean(matchKeywords)
		clean(excludeKeywords)
	}

	private static func clean(_ key: SettingsKey<[HighlightKeyword]>) {
		key.value = keywords(in: key.value)
			.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			.map(HighlightKeyword.init(string:))
	}
}

/** How a highlight keyword is compared against a message.

 Stored as the integer it declares, so the typed store reads and writes it
 directly. A stored value with no matching case decodes to nothing and the read
 falls back to the key's declared default. The conformance is here because the
 synthesis only happens in the file that declares the enum. */
enum NicknameHighlightMatchMode: UInt, Sendable {
	case partial
	case exact
	case regularExpression
}

extension NicknameHighlightMatchMode: SettingEnum {}
