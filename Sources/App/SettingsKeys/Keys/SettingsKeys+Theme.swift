// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// The complete native transcript appearance.
	enum Theme {
		private static let group = "Theme -> "

		/// The complete native transcript theme, encoded as an XML property list.
		/// Keeping it as one value makes edits atomic and lets settings export
		/// carry exactly the same document as the dedicated theme exporter.
		static let transcriptTheme = SettingsKey(group + "Transcript Theme", default: Data(), validation: { data in
			guard !data.isEmpty else { return true }
			guard let root = try? PropertyListSerialization
				.propertyList(from: data, options: [], format: nil) as? [String: Any],
				let version = root["formatVersion"].flatMap({ Int.settingValue(from: $0) }) else { return false }
			// Future themes stay byte-for-byte intact while this build renders its fallback.
			if version > TranscriptTheme.currentFormatVersion {
				return true
			}
			// Everything else a stored document has to satisfy is what reading it says.
			return (try? TranscriptTheme.decoded(from: data)) != nil
		})
		static let all: [any AnySettingsKey] = [transcriptTheme]
	}
}
