/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

// MARK: - Messages

nonisolated extension Preferences { // nonisolated: value
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
			"Nickname Color Style Overrides (v2)", validation: PreferencesPayloadValidation.nicknameColors
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

nonisolated extension Preferences { // nonisolated: value
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
