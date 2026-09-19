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
				isOn: model.settings.binding(for: SettingsKeys.Connection.confirmQuit)
			)
			SettingsToggle(
				title: .Settings.generalAwayOnScreenSleep,
				isOn: model.settings.binding(for: SettingsKeys.Connection.awayOnScreenSleep)
			)
			SettingsToggle(
				title: .Settings.preventSleepWhileConnected,
				note: .Settings.preventSleepExplanation,
				isOn: model.settings.binding(for: SettingsKeys.Connection.preventSleepWhileConnected)
			)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalRejoinOnKick,
				isOn: model.settings.binding(for: SettingsKeys.Connection.rejoinOnKick)
			)
			SettingsToggle(
				title: .Settings.generalAutojoinOnInvite,
				isOn: model.settings.binding(for: SettingsKeys.Connection.autojoinOnInvite)
			)
		} header: {
			Text(.Settings.generalHeadingChannels)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalReloadScrollback,
				isOn: model.settings.binding(for: SettingsKeys.Logging.reloadScrollbackOnLaunch)
			)
			SettingsToggle(
				title: .Settings.generalRememberQueries,
				isOn: model.settings.binding(for: SettingsKeys.Appearance.rememberDirectConversations)
			)
		} header: {
			Text(.Settings.generalHeadingOnLaunch)
		}

		SettingsRecoverySection()
	}
}
