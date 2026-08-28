/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Importing a preferences file that turns transcript logging on did not
/// reopen the log files until the next launch, because the key-driven path had
/// no branch for it. `.serverList` had the same gap.
@Suite("Preference reload action mapping")
@MainActor
struct PreferencesReloadActionMappingTests {
	@Test("Every action a key can request has a bit of its own")
	func actionsAreDistinct() {
		let actions: [PreferencesReloadAction] = [
			.appearance, .channelViewArrangement, .dockIconBadges, .highlightKeywords,
			.highlightLogging, .ircCommandCache, .inputHistoryScope, .logTranscripts,
			.memberList, .memberListSortOrder, .memberListUserBadges, .preferencesChanged,
			.scrollbackSaveLimit, .scrollbackVisibleLimit, .serverList, .serverListUnreadBadges,
			.style, .textDirection, .textFieldFontSize,
		]

		#expect(Set(actions.map(\.rawValue)).count == actions.count)
	}

	@Test("LogTranscript and the client list reach an action")
	func newlyMappedKeys() {
		#expect(TextualPreferences.reloadAction(forKeys: ["LogTranscript"]).contains(.logTranscripts))
		#expect(TextualPreferences.reloadAction(forKeys: [IRCWorldClientListDefaultsKey]).contains(.serverList))
	}

	@Test("An unrelated key still asks observers to re-read preferences")
	func unrelatedKeyStillNotifies() {
		let action = TextualPreferences.reloadAction(forKeys: ["SomeKeyNothingMaps"])
		#expect(action.contains(.preferencesChanged))
		#expect(action.contains(.logTranscripts) == false)
		#expect(action.contains(.serverList) == false)
	}

	@Test("Keys that already had a mapping keep it")
	func existingMappingsAreIntact() {
		#expect(TextualPreferences.reloadAction(forKeys: ["LogHighlights"]).contains(.highlightLogging))
		#expect(
			TextualPreferences.reloadAction(forKeys: ["ScrollbackMaximumSavedLineCount"])
				.contains(.scrollbackSaveLimit)
		)
		#expect(
			TextualPreferences.reloadAction(forKeys: [TPCPreferencesThemeNameDefaultsKey]).contains(.style)
		)
	}
}
