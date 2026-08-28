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

/** One entry of a highlight list.

 The list is stored as an array of single-field dictionaries — the shape the
 array controller in the preferences nib binds to — rather than an array of
 strings, so the record is spelled out here instead of being rebuilt from
 `["string": …]` literals at every use. */
public nonisolated struct HighlightKeyword: Hashable, Sendable {
	public static let field = "string"

	public var string: String

	public init(string: String) {
		self.string = string
	}
}

nonisolated extension HighlightKeyword: PreferenceValue {
	public static func preferenceValue(from object: Any) -> HighlightKeyword? {
		guard let entry = object as? [String: Any], let string = entry[field] as? String else {
			return nil
		}

		return HighlightKeyword(string: string)
	}

	public var preferenceObject: Any {
		[Self.field: string]
	}
}

// MARK: - Input

public nonisolated extension Preferences {
	/// The input text field, the keyboard, and tab completion.
	nonisolated enum Input {
		public static let automaticSpellCheck = PreferenceKey("TextFieldAutomaticSpellCheck", default: true)
		public static let automaticGrammarCheck = PreferenceKey("TextFieldAutomaticGrammarCheck", default: true)
		public static let automaticSpellCorrection = PreferenceKey(
			"TextFieldAutomaticSpellCorrection",
			default: false
		)

		public static let smartCopyPaste = PreferenceKey("TextFieldSmartCopyPaste", default: true)
		public static let smartQuotes = PreferenceKey("TextFieldSmartQuotes", default: false)
		public static let smartDashes = PreferenceKey("TextFieldSmartDashes", default: false)
		public static let smartLinks = PreferenceKey("TextFieldSmartLinks", default: false)
		public static let dataDetectors = PreferenceKey("TextFieldDataDetectors", default: false)
		public static let textReplacement = PreferenceKey("TextFieldTextReplacement", default: true)

		/// Every `TextField…` key is restored state of the text system rather
		/// than a portable setting, so the prefix is excluded from export.
		public static let textFieldFamily = PreferenceKeyFamily(
			"TextField",
			traits: [.excludedFromExport, .uncatalogued]
		)

		public static let tabKeyAction = PreferenceKey(
			"Keyboard -> Tab Key Action",
			default: TXTabKeyAction.nicknameComplete
		)

		public static let commandWKeyAction = PreferenceKey(
			"Keyboard -> Command+W Key Action",
			default: TXCommandWKeyAction.closeWindow
		)

		public static let tabCompletionSuffix = PreferenceKey(
			"Keyboard -> Tab Key Completion Suffix",
			default: "",
			traits: .unregistered
		)

		public static let tabCompletionNoWhitespace = PreferenceKey(
			"Tab Completion -> Do Not Use Whitespace for Missing Completion Suffix",
			default: false
		)

		public static let tabCompletionCutForward = PreferenceKey(
			"Tab Completion -> Completion Suffix Cut Forward Until Space",
			default: false
		)

		public static let focusTextViewOnSelectionChange = PreferenceKey(
			"Main Input Text Field -> Focus When Changing Views",
			default: true
		)

		public static let textViewFontSize = PreferenceKey(
			"Main Input Text Field -> Font Size",
			default: TVCMainWindowTextViewFontSize.normal
		)

		public static let commandReturnSendsAction = PreferenceKey(
			"CommandReturnSendsMessageAsAction",
			default: true
		)

		public static let controlEnterSendsMessage = PreferenceKey("ControlEnterSendsMessage", default: false)
		public static let historyIsChannelSpecific = PreferenceKey("SaveInputHistoryPerSelection", default: false)
		public static let swipeMinimumLength = PreferenceKey("SwipeMinimumLength", default: 30.0)

		public static let userDoubleClickAction = PreferenceKey(
			"UserListDoubleClickAction",
			default: TXUserDoubleClickAction.privateMessage
		)

		static let all: [any AnyPreferenceKey] = [
			automaticSpellCheck, automaticGrammarCheck, automaticSpellCorrection, smartCopyPaste,
			smartQuotes, smartDashes, smartLinks, dataDetectors, textReplacement, tabKeyAction,
			commandWKeyAction, tabCompletionSuffix, tabCompletionNoWhitespace, tabCompletionCutForward,
			focusTextViewOnSelectionChange, textViewFontSize, commandReturnSendsAction,
			controlEnterSendsMessage, historyIsChannelSpecific, swipeMinimumLength, userDoubleClickAction,
		]
	}
}

// MARK: - Highlights

public nonisolated extension Preferences {
	/// Which incoming text counts as a highlight.
	nonisolated enum Highlights {
		public static let matchingMethod = PreferenceKey(
			"NicknameHighlightMatchingType",
			default: TXNicknameHighlightMatchType.exact
		)

		public static let trackLocalNickname = PreferenceKey("TrackNicknameHighlightsOfLocalUser", default: true)

		public static let matchKeywords = PreferenceKey(
			"Highlight List -> Primary Matches",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		public static let excludeKeywords = PreferenceKey(
			"Highlight List -> Excluded Matches",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		static let all: [any AnyPreferenceKey] = [
			matchingMethod, trackLocalNickname, matchKeywords, excludeKeywords,
		]
	}
}
