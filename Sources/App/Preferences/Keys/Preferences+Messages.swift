// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

// MARK: - Messages

nonisolated extension Preferences {
	/// What is shown in a channel view, and how incoming text is treated.
	enum Messages {
		static let showDateChanges = PreferenceKey(
			"DisplayEventInLogView -> Date Changes",
			default: true
		)

		static let showInlineMedia = PreferenceKey(
			"DisplayEventInLogView -> Inline Media",
			default: false
		)

		static let showJoinLeave = PreferenceKey(
			"DisplayEventInLogView -> Join, Part, Quit",
			default: true
		)

		static let autoAddScrollbackMark = PreferenceKey("AutomaticallyAddScrollbackMarker", default: true)
		static let copyOnSelect = PreferenceKey("CopyTextSelectionOnMouseUp", default: false)
		static let removeAllFormatting = PreferenceKey("RemoveIRCTextFormatting", default: false)
		static let rightToLeftFormatting = PreferenceKey("RightToLeftTextFormatting", default: false)
		static let replyToCTCPRequests = PreferenceKey("ReplyUnignoredExternalCTCPRequests", default: true)
		static let detectHighlightSpam = PreferenceKey("AutomaticallyDetectHighlightSpam", default: true)
		static let filterUnicodeTextSpam = PreferenceKey("AutomaticallyFilterUnicodeTextSpam", default: false)
		static let openBrowserInBackground = PreferenceKey(
			"OpenClickedLinksInBackgroundBrowser",
			default: false
		)

		static let disableNicknameColorHashing = PreferenceKey(
			"DisableRemoteNicknameColorHashing",
			default: false
		)

		static let nicknameColorStyleOverrides = UntypedPreferenceKey(
			"Nickname Color Style Overrides (v2)", validation: PreferenceValueRepair.nicknameColors
		)

		static let all: [any AnyPreferenceKey] = [
			showDateChanges, showInlineMedia, showJoinLeave, autoAddScrollbackMark, copyOnSelect,
			removeAllFormatting, rightToLeftFormatting, replyToCTCPRequests, detectHighlightSpam,
			filterUnicodeTextSpam, openBrowserInBackground, disableNicknameColorHashing,
			nicknameColorStyleOverrides,
		]
	}
}

// MARK: - Logging

nonisolated extension Preferences {
	/// Transcript logging and the scrollback the log view keeps.
	enum Logging {
		static let logToDisk = PreferenceKey("LogTranscript", default: false)
		static let logHighlights = PreferenceKey("LogHighlights", default: true)
		static let reloadScrollbackOnLaunch = PreferenceKey("ReloadScrollbackOnLaunch", default: true)
		static let loadHistoryLazily = PreferenceKey("Optimizations -> Load History Lazily", default: true)

		/// How many lines a channel keeps on disk. The bounds are the ones the
		/// field has always enforced, declared here so an import obeys them too.
		static let scrollbackSaveRange: ClosedRange<UInt> = 100 ... 50000

		/// How many lines the transcript draws, where zero means "no limit".
		static let scrollbackVisibleRange: ClosedRange<UInt> = 100 ... 15000

		static let scrollbackSaveLimit = PreferenceKey(
			"ScrollbackMaximumSavedLineCount",
			default: UInt(15000),
			validation: { Self.scrollbackSaveRange.contains($0) }
		)

		static let scrollbackVisibleLimit = PreferenceKey(
			"ScrollbackMaximumVisibleLineCount",
			default: UInt(0),
			validation: { $0 == 0 || Self.scrollbackVisibleRange.contains($0) }
		)

		/// A security-scoped bookmark for the folder the user picked; useless in
		/// another user account, so it never leaves this one.
		static let transcriptFolderBookmark = PreferenceKey(
			"LogTranscriptDestinationSecurityBookmark_5",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		static let historicLogFileName = PreferenceKey(
			"TVCLogControllerHistoricLogFileSavePath_v3",
			default: "",
			traits: [.unregistered, .excludedFromExport]
		)

		static let all: [any AnyPreferenceKey] = [
			logToDisk, logHighlights, reloadScrollbackOnLaunch, loadHistoryLazily,
			scrollbackSaveLimit, scrollbackVisibleLimit, transcriptFolderBookmark, historicLogFileName,
		]
	}
}

nonisolated extension Preferences {
	/// What the transcript's reaction picker offers first.
	enum Reactions {
		/// The emoji the user has reacted with, most recent first. Kept short by
		/// `RecentReactions`; the picker fills the rest of the row from its
		/// common set.
		static let recent = PreferenceKey(
			"Reactions -> Recently Used",
			default: [String](),
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = [recent]
	}
}

@MainActor
extension Preferences.Logging {
	/// Whether a transcript is actually being written: the setting is on and a
	/// folder the application can still reach has been chosen.
	static var logToDiskIsEnabled: Bool {
		logToDisk.value && ApplicationPaths.transcriptFolderURL != nil
	}
}
