// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

nonisolated extension SettingsKeys {
	/// The input text field, the keyboard, and tab completion.
	enum Input {
		private static let group = "Input -> "

		static let automaticSpellCheck = SettingsKey(group + "Automatic Spell Check", default: true)
		static let automaticGrammarCheck = SettingsKey(group + "Automatic Grammar Check", default: true)
		static let automaticSpellCorrection = SettingsKey(
			group + "Automatic Spell Correction",
			default: false
		)

		static let smartCopyPaste = SettingsKey(group + "Smart Copy Paste", default: true)
		static let smartQuotes = SettingsKey(group + "Smart Quotes", default: false)
		static let smartDashes = SettingsKey(group + "Smart Dashes", default: false)
		static let smartLinks = SettingsKey(group + "Smart Links", default: false)
		static let dataDetectors = SettingsKey(group + "Data Detectors", default: false)
		static let textReplacement = SettingsKey(group + "Text Replacement", default: true)

		static let tabKeyAction = SettingsKey(
			group + "Tab Key Action",
			default: TabKeyAction.nicknameComplete
		)

		static let commandWKeyAction = SettingsKey(
			group + "Command+W Key Action",
			default: CommandWShortcutAction.closeWindow
		)

		static let tabCompletionSuffix = SettingsKey(
			group + "Tab Completion Suffix",
			default: "",
			traits: .unregistered
		)

		static let tabCompletionNoWhitespace = SettingsKey(
			group + "Tab Completion No Whitespace",
			default: false
		)

		static let tabCompletionCutForward = SettingsKey(
			group + "Tab Completion Cut Forward",
			default: false
		)

		static let focusTextViewOnSelectionChange = SettingsKey(
			group + "Focus Text View On Selection Change",
			default: true
		)

		static let textViewFontSize = SettingsKey(
			group + "Text View Font Size",
			default: MainWindowTextFontSize.normal
		)

		static let commandReturnSendsAction = SettingsKey(
			group + "Command Return Sends Action",
			default: true
		)

		static let controlEnterSendsMessage = SettingsKey(
			group + "Control Enter Sends Message",
			default: false
		)
		/// Whether the input history is kept per sidebar selection -- each server
		/// and each conversation its own -- rather than one history for the window.
		static let historyIsPerSelection = SettingsKey(
			group + "History Is Channel Specific",
			default: false
		)
		static let swipeMinimumLength = SettingsKey(
			group + "Swipe Minimum Length", default: 30.0,
			validation: { $0.isFinite && $0 >= 0 }
		)

		static let userDoubleClickAction = SettingsKey(
			group + "User Double Click Action",
			default: UserDoubleClickAction.startDirectConversation
		)

		static let all: [any AnySettingsKey] = [
			automaticSpellCheck, automaticGrammarCheck, automaticSpellCorrection, smartCopyPaste,
			smartQuotes, smartDashes, smartLinks, dataDetectors, textReplacement, tabKeyAction,
			commandWKeyAction, tabCompletionSuffix, tabCompletionNoWhitespace, tabCompletionCutForward,
			focusTextViewOnSelectionChange, textViewFontSize, commandReturnSendsAction,
			controlEnterSendsMessage, historyIsPerSelection, swipeMinimumLength, userDoubleClickAction,
		]
	}
}

/// What the tab key does in the input field.
enum TabKeyAction: UInt, Sendable {
	case nicknameComplete
	/// Moves to the next sidebar entry with unread lines, of any kind.
	case unreadConversation
	case none
}

extension TabKeyAction: SettingEnum {}

/// What a double click on a name in the member list does.
enum UserDoubleClickAction: UInt, Sendable {
	case whois
	case startDirectConversation
	case insertTextField
}

extension UserDoubleClickAction: SettingEnum {}

/// What Command-W closes.
enum CommandWShortcutAction: UInt, Sendable {
	case closeWindow
	/// Leaves the selected conversation: a part for a channel, a close for
	/// anything else.
	case closeConversation
	case disconnect
	case terminate
}

extension CommandWShortcutAction: SettingEnum {}

/// The size the input field draws its text at.
enum MainWindowTextFontSize: UInt, Sendable {
	case normal = 1
	case large
	case extraLarge
	case humongous
}

extension MainWindowTextFontSize: SettingEnum {}
