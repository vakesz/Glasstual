// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The General row: the language the application runs in, the questions it
/// asks on quit and on sleep, and what it does on launch.
struct GeneralPane: View {
	@Bindable var model: SettingsModel

	var body: some View {
		Section {
			Picker(selection: $model.appLanguage) {
				ForEach(AppLanguage.allCases, id: \.self) { language in
					Text(language.title).tag(language)
				}
			} label: {
				Text(.Settings.appLanguage)
			}
			.accessibilityIdentifier("settings-app-language")
		} footer: {
			Text(.Settings.languageRestartHelp)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalConfirmQuit,
				isOn: model.preferences.binding(for: Preferences.Connection.confirmQuit)
			)
			SettingsToggle(
				title: .Settings.generalAwayOnScreenSleep,
				isOn: model.preferences.binding(for: Preferences.Connection.awayOnScreenSleep)
			)
			SettingsToggle(
				title: .Settings.preventSleepWhileConnected,
				note: .Settings.preventSleepExplanation,
				isOn: model.preferences.binding(for: Preferences.Connection.preventSleepWhileConnected)
			)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalRejoinOnKick,
				isOn: model.preferences.binding(for: Preferences.Connection.rejoinOnKick)
			)
			SettingsToggle(
				title: .Settings.generalAutojoinOnInvite,
				isOn: model.preferences.binding(for: Preferences.Connection.autojoinOnInvite)
			)
		} header: {
			Text(.Settings.generalHeadingChannels)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalReloadScrollback,
				isOn: model.preferences.binding(for: Preferences.Logging.reloadScrollbackOnLaunch)
			)
			SettingsToggle(
				title: .Settings.generalRememberQueries,
				isOn: model.preferences.binding(for: Preferences.Appearance.rememberQueryStates)
			)
		} header: {
			Text(.Settings.generalHeadingOnLaunch)
		}

		PreferencesRecoverySection()
	}
}
