/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

public final class ChannelSpotlightAppearance: ApplicationAppearance {
	public private(set) var searchFieldTextColor: NSColor?
	public private(set) var searchFieldNoResultsTextColor: NSColor?
	public private(set) var searchResultKeyboardShortcutDeselectedOffset: CGFloat = 0
	public private(set) var searchResultKeyboardShortcutSelectedOffset: CGFloat = 0

	@MainActor
	public init?() {
		super.init(applicationProperties: Self.currentApplicationProperties)

		guard let schema = AppearanceSchema.load(
			ChannelSpotlightAppearanceSchema.self,
			resource: "TDCChannelSpotlightAppearance",
			appearanceName: appearanceName
		) else {
			return nil
		}

		searchFieldTextColor = schema.searchField.controlTextColor?.color
		searchFieldNoResultsTextColor = schema.searchField.noResultsTextColor?.color
		searchResultKeyboardShortcutDeselectedOffset = schema.searchResult.keyboardShortcutDeselectedOffset
		searchResultKeyboardShortcutSelectedOffset = schema.searchResult.keyboardShortcutSelectedOffset
	}
}
