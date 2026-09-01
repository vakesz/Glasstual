/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2018 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit

/// The shape of `TDCChannelSpotlightAppearance.plist`.
struct ChannelSpotlightAppearanceSchema: Decodable, Sendable {
	struct SearchField: Decodable, Sendable {
		let controlTextColor: AppearanceColor?
		let noResultsTextColor: AppearanceColor?
	}

	struct SearchResult: Decodable, Sendable {
		let keyboardShortcutDeselectedOffset: Double
		let keyboardShortcutSelectedOffset: Double
	}

	let searchField: SearchField
	let searchResult: SearchResult

	private enum CodingKeys: String, CodingKey {
		case searchField = "Search Field"
		case searchResult = "Search Result"
	}
}
