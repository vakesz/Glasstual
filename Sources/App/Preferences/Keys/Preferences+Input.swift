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

import CocoaExtensions
import Foundation

/** One entry of a highlight list.

 The list is stored as an array of single-field dictionaries — the shape every
 existing preferences file already holds — rather than an array of strings, so
 the record is spelled out here instead of being rebuilt from
 `["string": …]` literals at every use. */
nonisolated struct HighlightKeyword: Hashable, Sendable { // nonisolated: value
	static let field = "string"

	var string: String
}

nonisolated extension HighlightKeyword: PreferenceValue { // nonisolated: value
	static func preferenceValue(from object: Any) -> HighlightKeyword? {
		guard let string = PropertyListValue(propertyList: object)?.dictionary?[field]?.string else {
			return nil
		}

		return HighlightKeyword(string: string)
	}

	var preferenceObject: Any? {
		[Self.field: string]
	}
}

// MARK: - Input

nonisolated extension Preferences { // nonisolated: value
	/// The input text field, the keyboard, and tab completion.
	enum Input {
		static let automaticSpellCheck = PreferenceKey("TextFieldAutomaticSpellCheck", default: true)
		static let automaticGrammarCheck = PreferenceKey("TextFieldAutomaticGrammarCheck", default: true)
		static let automaticSpellCorrection = PreferenceKey(
			"TextFieldAutomaticSpellCorrection",
			default: false
		)

		static let smartCopyPaste = PreferenceKey("TextFieldSmartCopyPaste", default: true)
		static let smartQuotes = PreferenceKey("TextFieldSmartQuotes", default: false)
		static let smartDashes = PreferenceKey("TextFieldSmartDashes", default: false)
		static let smartLinks = PreferenceKey("TextFieldSmartLinks", default: false)
		static let dataDetectors = PreferenceKey("TextFieldDataDetectors", default: false)
		static let textReplacement = PreferenceKey("TextFieldTextReplacement", default: true)

		static let tabKeyAction = PreferenceKey(
			"Keyboard -> Tab Key Action",
			default: TabKeyAction.nicknameComplete
		)

		static let commandWKeyAction = PreferenceKey(
			"Keyboard -> Command+W Key Action",
			default: CommandWShortcutAction.closeWindow
		)

		static let tabCompletionSuffix = PreferenceKey(
			"Keyboard -> Tab Key Completion Suffix",
			default: "",
			traits: .unregistered
		)

		static let tabCompletionNoWhitespace = PreferenceKey(
			"Tab Completion -> Do Not Use Whitespace for Missing Completion Suffix",
			default: false
		)

		static let tabCompletionCutForward = PreferenceKey(
			"Tab Completion -> Completion Suffix Cut Forward Until Space",
			default: false
		)

		static let focusTextViewOnSelectionChange = PreferenceKey(
			"Main Input Text Field -> Focus When Changing Views",
			default: true
		)

		static let textViewFontSize = PreferenceKey(
			"Main Input Text Field -> Font Size",
			default: MainWindowTextFontSize.normal
		)

		static let commandReturnSendsAction = PreferenceKey(
			"CommandReturnSendsMessageAsAction",
			default: true
		)

		static let controlEnterSendsMessage = PreferenceKey("ControlEnterSendsMessage", default: false)
		static let historyIsChannelSpecific = PreferenceKey("SaveInputHistoryPerSelection", default: false)
		static let swipeMinimumLength = PreferenceKey(
			"SwipeMinimumLength", default: 30.0,
			validation: { $0.isFinite && $0 >= 0 }
		)

		static let userDoubleClickAction = PreferenceKey(
			"UserListDoubleClickAction",
			default: UserDoubleClickAction.privateMessage
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

nonisolated extension Preferences { // nonisolated: value
	/// Which incoming text counts as a highlight.
	enum Highlights {
		static let matchingMethod = PreferenceKey(
			"NicknameHighlightMatchingType",
			default: NicknameHighlightMatchMode.exact
		)

		static let trackLocalNickname = PreferenceKey("TrackNicknameHighlightsOfLocalUser", default: true)

		static let matchKeywords = PreferenceKey(
			"Highlight List -> Primary Matches",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		static let excludeKeywords = PreferenceKey(
			"Highlight List -> Excluded Matches",
			default: [HighlightKeyword](),
			traits: .unregistered
		)

		/** The keywords a stored list actually matches on.

		 One implementation, because both the connection layer's snapshot and
		 the maintenance pass that rewrites the stored list have to agree on
		 which entries count: an empty entry matches everything, so it is not a
		 keyword at all, and neither is one that is only spaces, which Settings
		 already shows as blank. Surrounding whitespace is dropped for the same
		 reason: a keyword is what the list shows. */
		static func keywords(in list: [HighlightKeyword]) -> [String] {
			list.map { $0.string.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false }
		}

		static let all: [any AnyPreferenceKey] = [
			matchingMethod, trackLocalNickname, matchKeywords, excludeKeywords,
		]
	}
}

/** How a highlight keyword is compared against a message.

 Stored as the integer it declares, so the typed store reads and writes it
 directly. A stored value with no matching case decodes to nothing and the read
 falls back to the key's declared default. The conformance is here because the
 synthesis only happens in the file that declares the enum. */
enum NicknameHighlightMatchMode: UInt, Sendable {
	case partial
	case exact
	case regularExpression
}

extension NicknameHighlightMatchMode: PreferenceEnum {}

/// What the tab key does in the input field.
enum TabKeyAction: UInt, Sendable {
	case nicknameComplete = 0
	case unreadChannel = 1
	case none = 100
}

extension TabKeyAction: PreferenceEnum {}

/// What a double click on a name in the member list does.
enum UserDoubleClickAction: UInt, Sendable {
	case whois = 100
	case privateMessage = 200
	case insertTextField = 300
}

extension UserDoubleClickAction: PreferenceEnum {}

/// What Command-W closes.
enum CommandWShortcutAction: UInt, Sendable {
	case closeWindow
	case partChannel
	case disconnect
	case terminate
}

extension CommandWShortcutAction: PreferenceEnum {}

/// The size the input field draws its text at.
enum MainWindowTextFontSize: UInt, Sendable {
	case normal = 1
	case large
	case extraLarge
	case humongous
}

extension MainWindowTextFontSize: PreferenceEnum {}

@MainActor
extension Preferences.Highlights {
	/// Drops the entries that match nothing and sorts what is left, so the
	/// Settings list and the stored value stay in one order.
	static func cleanUpStoredKeywords() {
		clean(matchKeywords)
		clean(excludeKeywords)
	}

	private static func clean(_ key: PreferenceKey<[HighlightKeyword]>) {
		key.value = keywords(in: key.value)
			.sorted { $0.caseInsensitiveCompare($1) == .orderedAscending }
			.map(HighlightKeyword.init(string:))
	}
}
