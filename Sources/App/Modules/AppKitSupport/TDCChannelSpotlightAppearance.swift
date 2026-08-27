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

@objc(TDCChannelSpotlightAppearance)
public final class ChannelSpotlightAppearance: ApplicationAppearance {
	@objc public private(set) var searchFieldTextColor: NSColor?
	@objc public private(set) var searchFieldNoResultsTextColor: NSColor?
	@objc public private(set) var searchResultKeyboardShortcutDeselectedOffset: CGFloat = 0
	@objc public private(set) var searchResultKeyboardShortcutSelectedOffset: CGFloat = 0

	@objc(initWithWindow:)
	public init?(window _: ChannelSpotlightPanel) {
		guard let appearanceLocation = Bundle.main.url(
			forResource: "TDCChannelSpotlightAppearance",
			withExtension: "plist"
		) else {
			return nil
		}

		super.init(appearanceAt: appearanceLocation)

		guard let properties = appearanceProperties else {
			return nil
		}

		let searchField = properties["Search Field"] as? [String: Any] ?? [:]
		searchFieldTextColor = color(inGroup: searchField, withKey: "controlTextColor")
		searchFieldNoResultsTextColor = color(inGroup: searchField, withKey: "noResultsTextColor")

		let searchResult = properties["Search Result"] as? [String: Any] ?? [:]
		searchResultKeyboardShortcutDeselectedOffset = measurement(
			inGroup: searchResult,
			withKey: "keyboardShortcutDeselectedOffset"
		)
		searchResultKeyboardShortcutSelectedOffset = measurement(
			inGroup: searchResult,
			withKey: "keyboardShortcutSelectedOffset"
		)

		flushAppearanceProperties()
	}
}
