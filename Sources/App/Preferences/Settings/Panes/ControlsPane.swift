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
				isOn: model.preferences.binding(
					for: Preferences.Appearance.channelNavigationIsServerSpecific
				)
			)
			doubleClickPicker
			commandWPicker
			doubleClickToggles
			SettingsToggle(
				title: .Settings.controlsCopyOnSelect,
				note: .Settings.controlsCopyOnSelectNote,
				isOn: model.preferences.binding(for: Preferences.Messages.copyOnSelect)
			)
			SettingsToggle(
				title: .Settings.controlsOpenLinksInBackground,
				isOn: model.preferences.binding(for: Preferences.Messages.openBrowserInBackground)
			)
		} header: {
			Text(.Settings.controlsHeadingKeyboardMouse)
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
		Picker(selection: model.preferences.binding(for: Preferences.Input.userDoubleClickAction)) {
			Text(.Settings.controlsUserDoubleClickQuery)
				.tag(UserDoubleClickAction.privateMessage)
			Text(.Settings.controlsUserDoubleClickWhois)
				.tag(UserDoubleClickAction.whois)
			Text(.Settings.controlsUserDoubleClickInsert)
				.tag(UserDoubleClickAction.insertTextField)
		} label: {
			Text(.Settings.controlsUserDoubleClickLabel)
		}
	}

	private var commandWPicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.commandWKeyAction)) {
			Text(.Settings.controlsCommandWCloseWindow)
				.tag(CommandWShortcutAction.closeWindow)
			Text(.Settings.controlsCommandWPartChannel)
				.tag(CommandWShortcutAction.partChannel)
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
			isOn: model.preferences.binding(for: Preferences.Appearance.connectOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsDisconnectOnDoubleClick,
			isOn: model.preferences.binding(for: Preferences.Appearance.disconnectOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsJoinOnDoubleClick,
			isOn: model.preferences.binding(for: Preferences.Appearance.joinOnDoubleClick)
		)
		SettingsToggle(
			title: .Settings.controlsLeaveOnDoubleClick,
			isOn: model.preferences.binding(for: Preferences.Appearance.leaveOnDoubleClick)
		)
	}

	@ViewBuilder
	private var spellingToggles: some View {
		SettingsToggle(
			title: .Settings.controlsSpellCheck,
			isOn: model.preferences.binding(for: Preferences.Input.automaticSpellCheck)
		)
		SettingsToggle(
			title: .Settings.controlsGrammarCheck,
			isOn: model.preferences.binding(for: Preferences.Input.automaticGrammarCheck)
		)
		SettingsToggle(
			title: .Settings.controlsSpellCorrection,
			isOn: model.preferences.binding(for: Preferences.Input.automaticSpellCorrection)
		)
	}

	@ViewBuilder
	private var sendingToggles: some View {
		SettingsToggle(
			title: .Settings.controlsHistoryPerSelection,
			isOn: model.preferences.binding(for: Preferences.Input.historyIsChannelSpecific) { _ in
				PreferenceReload.perform(.inputHistoryScope)
			}
		)
		/* Neither keyboard toggle reloads anything: they are read when a
		 key is pressed. Copying the history-scope reload onto them threw
		 the whole input history away every time one was flipped. */
		SettingsToggle(
			title: .Settings.controlsCommandReturnAction,
			isOn: model.preferences.binding(for: Preferences.Input.commandReturnSendsAction)
		)
		SettingsToggle(
			title: .Settings.controlsControlEnterSends,
			isOn: model.preferences.binding(for: Preferences.Input.controlEnterSendsMessage)
		)
	}

	private var textSizePicker: some View {
		Picker(selection: model.preferences.binding(for: Preferences.Input.textViewFontSize) { _ in
			PreferenceReload.perform(.textFieldFontSize)
		}) {
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
		Picker(selection: model.preferences.binding(for: Preferences.Input.tabKeyAction)) {
			Text(.Settings.controlsTabKeyNone)
				.tag(TabKeyAction.none)
			Text(.Settings.controlsTabKeyUnread)
				.tag(TabKeyAction.unreadChannel)
			Text(.Settings.controlsTabKeyComplete)
				.tag(TabKeyAction.nicknameComplete)
		} label: {
			Text(.Settings.controlsTabKeyLabel)
		}
	}

	private var completionSuffixRow: some View {
		LabeledContent {
			HStack(spacing: SettingsMetrics.spacingMedium) {
				TextField(
					"",
					text: model.preferences.binding(for: Preferences.Input.tabCompletionSuffix)
				)
				.labelsHidden()
				.accessibilityLabel(Text(.Settings.controlsCompletionSuffixAccessibility))
				Divider()
				Text(.Settings.controlsCompletionPreviewLabel)
					.bold()
				Text(.Settings.controlsCompletionPreview(
					model.preferences[Preferences.Input.tabCompletionSuffix]
				))
				.foregroundStyle(.secondary)
			}
		} label: {
			Text(.Settings.controlsCompletionSuffixLabel)
		}
	}
}
