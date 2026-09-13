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

enum PreferencesNotificationsStrings {
	static var dockBadgePrivate: String {
		String(localized: .Settings.notificationsDockBadgePrivate)
	}

	static var dockBadgePublic: String {
		String(localized: .Settings.notificationsDockBadgePublic)
	}

	static var headingAlerts: String {
		String(localized: .Settings.notificationsHeadingAlerts)
	}

	static var headingDelivery: String {
		String(localized: .Settings.notificationsHeadingDelivery)
	}

	static var headingDockIcon: String {
		String(localized: .Settings.notificationsHeadingDockIcon)
	}

	static var headingSpeech: String {
		String(localized: .Settings.notificationsHeadingSpeech)
	}

	static var headingSpeechInclude: String {
		String(localized: .Settings.notificationsHeadingSpeechInclude)
	}

	static var onlySpeakSelection: String {
		String(localized: .Settings.notificationsOnlySpeakSelection)
	}

	static var postWhileInFocus: String {
		String(localized: .Settings.notificationsPostWhileInFocus)
	}

	static var speakChannelName: String {
		String(localized: .Settings.notificationsSpeakChannelName)
	}

	static var speakNickname: String {
		String(localized: .Settings.notificationsSpeakNickname)
	}
}

enum PreferencesHighlightsStrings {
	static var addExcluded: String {
		String(localized: .Settings.highlightsAddExcluded)
	}

	static var addKeyword: String {
		String(localized: .Settings.highlightsAddKeyword)
	}

	static var excludeWordsLabel: String {
		String(localized: .Settings.highlightsExcludeWordsLabel)
	}

	static var logToWindow: String {
		String(localized: .Settings.highlightsLogToWindow)
	}

	static var matchTypeExact: String {
		String(localized: .Settings.highlightsMatchTypeExact)
	}

	static var matchTypeLabel: String {
		String(localized: .Settings.highlightsMatchTypeLabel)
	}

	static var matchTypePartial: String {
		String(localized: .Settings.highlightsMatchTypePartial)
	}

	static var matchTypeRegex: String {
		String(localized: .Settings.highlightsMatchTypeRegex)
	}

	static var newKeyword: String {
		String(localized: .Settings.highlightsNewKeyword)
	}

	static var removeExcluded: String {
		String(localized: .Settings.highlightsRemoveExcluded)
	}

	static var removeKeyword: String {
		String(localized: .Settings.highlightsRemoveKeyword)
	}

	static var trackLocalNickname: String {
		String(localized: .Settings.highlightsTrackLocalNickname)
	}

	static var wordsLabel: String {
		String(localized: .Settings.highlightsWordsLabel)
	}
}

enum PreferencesIncomingDataStrings {
	static var highlightSpam: String {
		String(localized: .Settings.incomingDataHighlightSpam)
	}

	static var highlightSpamNote: String {
		String(localized: .Settings.incomingDataHighlightSpamNote)
	}

	static var removeFormatting: String {
		String(localized: .Settings.incomingDataRemoveFormatting)
	}

	static var removeFormattingNote: String {
		String(localized: .Settings.incomingDataRemoveFormattingNote)
	}

	static var replyCtcp: String {
		String(localized: .Settings.incomingDataReplyCtcp)
	}

	static var unicodeSpam: String {
		String(localized: .Settings.incomingDataUnicodeSpam)
	}

	static var unicodeSpamNote: String {
		String(localized: .Settings.incomingDataUnicodeSpamNote)
	}
}

enum PreferencesFloodControlStrings {
	static func countValue(value: String) -> String {
		String(localized: .Settings.floodControlCountValue(value))
	}

	static var disabledMarker: String {
		String(localized: .Settings.floodControlDisabledMarker)
	}

	static var identifyDelayLabel: String {
		String(localized: .Settings.floodControlIdentifyDelayLabel)
	}

	static var identifyDelayNote: String {
		String(localized: .Settings.floodControlIdentifyDelayNote)
	}

	static var note: String {
		String(localized: .Settings.floodControlNote)
	}

	static func secondsValue(value: String) -> String {
		String(localized: .Settings.floodControlSecondsValue(value))
	}

	static var whoLimitLabel: String {
		String(localized: .Settings.floodControlWhoLimitLabel)
	}

	static var whoLimitNote: String {
		String(localized: .Settings.floodControlWhoLimitNote)
	}
}
