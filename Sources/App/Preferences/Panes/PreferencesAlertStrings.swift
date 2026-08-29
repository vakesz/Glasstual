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

nonisolated enum PreferencesNotificationsStrings { // nonisolated: value
	static var dockBadgePrivate: String {
		String(localized: .TDCPreferencesController.notificationsDockBadgePrivate)
	}

	static var dockBadgePublic: String {
		String(localized: .TDCPreferencesController.notificationsDockBadgePublic)
	}

	static var headingAlerts: String {
		String(localized: .TDCPreferencesController.notificationsHeadingAlerts)
	}

	static var headingSpeech: String {
		String(localized: .TDCPreferencesController.notificationsHeadingSpeech)
	}

	static var onlySpeakSelection: String {
		String(localized: .TDCPreferencesController.notificationsOnlySpeakSelection)
	}

	static var postWhileInFocus: String {
		String(localized: .TDCPreferencesController.notificationsPostWhileInFocus)
	}

	static var speakChannelName: String {
		String(localized: .TDCPreferencesController.notificationsSpeakChannelName)
	}

	static var speakNickname: String {
		String(localized: .TDCPreferencesController.notificationsSpeakNickname)
	}

	static var speechIncludeLabel: String {
		String(localized: .TDCPreferencesController.notificationsSpeechIncludeLabel)
	}
}

nonisolated enum PreferencesHighlightsStrings { // nonisolated: value
	static var addExcluded: String {
		String(localized: .TDCPreferencesController.highlightsAddExcluded)
	}

	static var addKeyword: String {
		String(localized: .TDCPreferencesController.highlightsAddKeyword)
	}

	static var excludeWordsLabel: String {
		String(localized: .TDCPreferencesController.highlightsExcludeWordsLabel)
	}

	static var logToWindow: String {
		String(localized: .TDCPreferencesController.highlightsLogToWindow)
	}

	static var matchTypeExact: String {
		String(localized: .TDCPreferencesController.highlightsMatchTypeExact)
	}

	static var matchTypeLabel: String {
		String(localized: .TDCPreferencesController.highlightsMatchTypeLabel)
	}

	static var matchTypePartial: String {
		String(localized: .TDCPreferencesController.highlightsMatchTypePartial)
	}

	static var matchTypeRegex: String {
		String(localized: .TDCPreferencesController.highlightsMatchTypeRegex)
	}

	static var newKeyword: String {
		String(localized: .TDCPreferencesController.highlightsNewKeyword)
	}

	static var removeExcluded: String {
		String(localized: .TDCPreferencesController.highlightsRemoveExcluded)
	}

	static var removeKeyword: String {
		String(localized: .TDCPreferencesController.highlightsRemoveKeyword)
	}

	static var trackLocalNickname: String {
		String(localized: .TDCPreferencesController.highlightsTrackLocalNickname)
	}

	static var wordsLabel: String {
		String(localized: .TDCPreferencesController.highlightsWordsLabel)
	}
}

nonisolated enum PreferencesIncomingDataStrings { // nonisolated: value
	static var highlightSpam: String {
		String(localized: .TDCPreferencesController.incomingDataHighlightSpam)
	}

	static var highlightSpamNote: String {
		String(localized: .TDCPreferencesController.incomingDataHighlightSpamNote)
	}

	static var removeFormatting: String {
		String(localized: .TDCPreferencesController.incomingDataRemoveFormatting)
	}

	static var removeFormattingNote: String {
		String(localized: .TDCPreferencesController.incomingDataRemoveFormattingNote)
	}

	static var replyCtcp: String {
		String(localized: .TDCPreferencesController.incomingDataReplyCtcp)
	}

	static var unicodeSpam: String {
		String(localized: .TDCPreferencesController.incomingDataUnicodeSpam)
	}

	static var unicodeSpamNote: String {
		String(localized: .TDCPreferencesController.incomingDataUnicodeSpamNote)
	}
}

nonisolated enum PreferencesFloodControlStrings { // nonisolated: value
	static func countValue(value: String) -> String {
		String(localized: .TDCPreferencesController.floodControlCountValue(value))
	}

	static var disabledMarker: String {
		String(localized: .TDCPreferencesController.floodControlDisabledMarker)
	}

	static var identifyDelayLabel: String {
		String(localized: .TDCPreferencesController.floodControlIdentifyDelayLabel)
	}

	static var identifyDelayNote: String {
		String(localized: .TDCPreferencesController.floodControlIdentifyDelayNote)
	}

	static var joinDelayLabel: String {
		String(localized: .TDCPreferencesController.floodControlJoinDelayLabel)
	}

	static var joinDelayNote: String {
		String(localized: .TDCPreferencesController.floodControlJoinDelayNote)
	}

	static var note: String {
		String(localized: .TDCPreferencesController.floodControlNote)
	}

	static func secondsValue(value: String) -> String {
		String(localized: .TDCPreferencesController.floodControlSecondsValue(value))
	}

	static var whoLimitLabel: String {
		String(localized: .TDCPreferencesController.floodControlWhoLimitLabel)
	}

	static var whoLimitNote: String {
		String(localized: .TDCPreferencesController.floodControlWhoLimitNote)
	}
}
