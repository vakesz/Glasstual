/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

public nonisolated extension Preferences {
	/// What is shown in a channel view, and how incoming text is treated.
	nonisolated enum Messages {
		public static let showDateChanges = PreferenceKey(
			"DisplayEventInLogView -> Date Changes",
			default: true
		)

		public static let showInlineMedia = PreferenceKey(
			"DisplayEventInLogView -> Inline Media",
			default: false
		)

		public static let showJoinLeave = PreferenceKey(
			"DisplayEventInLogView -> Join, Part, Quit",
			default: true
		)

		public static let autoAddScrollbackMark = PreferenceKey("AutomaticallyAddScrollbackMarker", default: true)
		public static let copyOnSelect = PreferenceKey("CopyTextSelectionOnMouseUp", default: false)
		public static let removeAllFormatting = PreferenceKey("RemoveIRCTextFormatting", default: false)
		public static let rightToLeftFormatting = PreferenceKey("RightToLeftTextFormatting", default: false)
		public static let replyToCTCPRequests = PreferenceKey("ReplyUnignoredExternalCTCPRequests", default: true)
		public static let detectHighlightSpam = PreferenceKey("AutomaticallyDetectHighlightSpam", default: true)
		public static let filterUnicodeTextSpam = PreferenceKey("AutomaticallyFilterUnicodeTextSpam", default: false)
		public static let openBrowserInBackground = PreferenceKey(
			"OpenClickedLinksInBackgroundBrowser",
			default: false
		)

		public static let disableNicknameColorHashing = PreferenceKey(
			"DisableRemoteNicknameColorHashing",
			default: false
		)

		public static let nicknameColorStyleOverrides = UntypedPreferenceKey(
			"Nickname Color Style Overrides (v2)"
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

public nonisolated extension Preferences {
	/// Transcript logging and the scrollback the log view keeps.
	nonisolated enum Logging {
		public static let logToDisk = PreferenceKey("LogTranscript", default: false)
		public static let logHighlights = PreferenceKey("LogHighlights", default: true)
		public static let reloadScrollbackOnLaunch = PreferenceKey("ReloadScrollbackOnLaunch", default: true)
		public static let loadHistoryLazily = PreferenceKey("Optimizations -> Load History Lazily", default: true)

		public static let scrollbackSaveLimit = PreferenceKey(
			"ScrollbackMaximumSavedLineCount",
			default: UInt(15000)
		)

		public static let scrollbackVisibleLimit = PreferenceKey(
			"ScrollbackMaximumVisibleLineCount",
			default: UInt(0)
		)

		/// A security-scoped bookmark for the folder the user picked; useless in
		/// another user account, so it never leaves this one.
		public static let transcriptFolderBookmark = PreferenceKey(
			"LogTranscriptDestinationSecurityBookmark_5",
			default: Data(),
			traits: [.unregistered, .excludedFromExport]
		)

		public static let historicLogFileName = PreferenceKey(
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
