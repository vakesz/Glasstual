/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

struct HighlightEntryContent: Equatable, Sendable {
	let includeTitle: String
	let excludeTitle: String
	let allChannelsTitle: String
	let keywordConnector: String
	let channelConnector: String
	let matchTypeAccessibilityLabel: String
	let keywordAccessibilityLabel: String
	let keywordAccessibilityHint: String
	let channelAccessibilityLabel: String
	let channelAccessibilityHint: String
	let saveButtonTitle: String
	let cancelButtonTitle: String
	let windowTitle: String

	static var current: Self {
		Self(
			includeTitle: ServerPropertiesStrings.Highlight.matchType(isExcluded: false),
			excludeTitle: ServerPropertiesStrings.Highlight.matchType(isExcluded: true),
			allChannelsTitle: ServerPropertiesStrings.Highlight.allChannels,
			keywordConnector: HighlightEntryStrings.keywordConnector,
			channelConnector: HighlightEntryStrings.channelConnector,
			matchTypeAccessibilityLabel: HighlightEntryStrings.matchTypeAccessibilityLabel,
			keywordAccessibilityLabel: HighlightEntryStrings.keywordAccessibilityLabel,
			keywordAccessibilityHint: HighlightEntryStrings.keywordAccessibilityHint,
			channelAccessibilityLabel: HighlightEntryStrings.channelAccessibilityLabel,
			channelAccessibilityHint: HighlightEntryStrings.channelAccessibilityHint,
			saveButtonTitle: PromptStrings.Action.save,
			cancelButtonTitle: PromptStrings.Action.cancel,
			windowTitle: HighlightEntryStrings.windowTitle
		)
	}

	func title(for behavior: HighlightMatchBehavior) -> String {
		switch behavior {
		case .include:
			includeTitle
		case .exclude:
			excludeTitle
		}
	}
}
