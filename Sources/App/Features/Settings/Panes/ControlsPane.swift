// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Controls row: what the keyboard and the mouse do, and how the input
/// field behaves as it is typed into.
struct ControlsPane: View {
	let model: SettingsModel

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.controlsNavigationServerSpecific,
				isOn: model.settings.binding(
					for: SettingsKeys.Appearance.conversationNavigationIsServerSpecific
				)
			)
			commandWPicker
		} header: {
			Text(.Settings.controlsHeadingKeyboard)
		}

		Section {
			doubleClickPicker
			doubleClickToggles
			SettingsToggle(
				title: .Settings.controlsCopyOnSelect,
				note: .Settings.controlsCopyOnSelectNote,
				isOn: model.settings.binding(for: SettingsKeys.Messages.copyOnSelect)
			)
			SettingsToggle(
				title: .Settings.controlsOpenLinksInBackground,
				isOn: model.settings.binding(for: SettingsKeys.Messages.openBrowserInBackground)
			)
		} header: {
			Text(.Settings.controlsHeadingMouse)
		}

		Section {
			spellingToggles
			sendingToggles
			textSizePicker
			tabKeyPicker
			completionSuffixRow
		} header: {
			Text(.Settings.controlsHeadingTextField)
		}
	}

	private var doubleClickPicker: some View {
		Picker(selection: model.settings.binding(for: SettingsKeys.Input.userDoubleClickAction)) {
			Text(.Settings.controlsUserDoubleClickQuery)
				.tag(UserDoubleClickAction.startDirectConversation)
			Text(.Settings.controlsUserDoubleClickWhois)
				.tag(UserDoubleClickAction.whois)
			Text(.Settings.controlsUserDoubleClickInsert)
				.tag(UserDoubleClickAction.insertTextField)
		} label: {
			Text(.Settings.controlsUserDoubleClickLabel)
		}
	}

	private var commandWPicker: some View {
		Picker(selection: model.settings.binding(for: SettingsKeys.Input.commandWKeyAction)) {
			Text(.Settings.controlsCommandWCloseWindow)
				.tag(CommandWShortcutAction.closeWindow)
			Text(.Settings.controlsCommandWPartChannel)
				.tag(CommandWShortcutAction.closeConversation)
			Text(.Settings.controlsCommandWDisconnect)
				.tag(CommandWShortcutAction.disconnect)
			Text(.Settings.controlsCommandWTerminate)
				.tag(CommandWShortcutAction.terminate)
		} label: {
			Text(.Settings.controlsCommandWLabel)
		}
	}

	@ViewBuilder
	private var doubleClickToggles: some View {
		SettingsToggle(
			title: .Settings.controlsConnectOnDoubleClick,
			isOn: model.settings.binding(for: SettingsKeys.Appearance.connectOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsDisconnectOnDoubleClick,
			isOn: model.settings.binding(for: SettingsKeys.Appearance.disconnectOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsJoinOnDoubleClick,
			isOn: model.settings.binding(for: SettingsKeys.Appearance.joinOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsLeaveOnDoubleClick,
			isOn: model.settings.binding(for: SettingsKeys.Appearance.leaveOnDoubleClick)
		)
	}

	@ViewBuilder
	private var spellingToggles: some View {
		SettingsToggle(
			title: .Settings.controlsSpellCheck,
			isOn: model.settings.binding(for: SettingsKeys.Input.automaticSpellCheck)
		)
		SettingsToggle(
			title: .Settings.controlsGrammarCheck,
			isOn: model.settings.binding(for: SettingsKeys.Input.automaticGrammarCheck)
		)
		SettingsToggle(
			title: .Settings.controlsSpellCorrection,
			isOn: model.settings.binding(for: SettingsKeys.Input.automaticSpellCorrection)
		)
	}

	@ViewBuilder
	private var sendingToggles: some View {
		SettingsToggle(
			title: .Settings.controlsHistoryPerSelection,
			isOn: model.settings.binding(for: SettingsKeys.Input.historyIsPerSelection)
		)
		SettingsToggle(
			title: .Settings.controlsCommandReturnAction,
			isOn: model.settings.binding(for: SettingsKeys.Input.commandReturnSendsAction)
		)
		SettingsToggle(
			title: .Settings.controlsControlEnterSends,
			isOn: model.settings.binding(for: SettingsKeys.Input.controlEnterSendsMessage)
		)
	}

	private var textSizePicker: some View {
		Picker(selection: model.settings.binding(for: SettingsKeys.Input.textViewFontSize)) {
			Text(.Settings.controlsTextSizeNormal)
				.tag(MainWindowTextFontSize.normal)
			Text(.Settings.controlsTextSizeLarge)
				.tag(MainWindowTextFontSize.large)
			Text(.Settings.controlsTextSizeExtraLarge)
				.tag(MainWindowTextFontSize.extraLarge)
			Text(.Settings.controlsTextSizeHumongous)
				.tag(MainWindowTextFontSize.humongous)
		} label: {
			Text(.Settings.controlsTextSizeLabel)
		}
	}

	private var tabKeyPicker: some View {
		Picker(selection: model.settings.binding(for: SettingsKeys.Input.tabKeyAction)) {
			Text(.Settings.controlsTabKeyNone)
				.tag(TabKeyAction.none)
			Text(.Settings.controlsTabKeyUnread)
				.tag(TabKeyAction.unreadConversation)
			Text(.Settings.controlsTabKeyComplete)
				.tag(TabKeyAction.nicknameComplete)
		} label: {
			Text(.Settings.controlsTabKeyLabel)
		}
	}

	/// The suffix, with what a completed name looks like as the row's subtitle.
	private var completionSuffixRow: some View {
		TextField(text: model.settings.binding(for: SettingsKeys.Input.tabCompletionSuffix)) {
			Text(.Settings.controlsCompletionSuffixLabel)
			Text(.Settings.controlsCompletionPreview(
				model.settings[SettingsKeys.Input.tabCompletionSuffix]
			))
		}
		.accessibilityLabel(Text(.Settings.controlsCompletionSuffixAccessibility))
	}
}
