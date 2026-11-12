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
			.accessibilityIdentifier(AccessibilityIdentifier.settingsConfirmQuit)
			SettingsToggle(
				title: .Settings.generalAwayOnScreenSleep,
				isOn: model.settings.binding(for: SettingsKeys.Connection.awayOnScreenSleep)
			)
			SettingsToggle(
				title: .Settings.generalAwayOnIdle,
				note: .Settings.generalAwayOnIdleNote,
				isOn: model.settings.binding(for: SettingsKeys.Connection.awayOnIdle)
			)
			idleAwayRows
			SettingsToggle(
				title: .Settings.preventSleepWhileConnected,
				note: .Settings.preventSleepExplanation,
				isOn: model.settings.binding(for: SettingsKeys.Connection.preventSleepWhileConnected)
			)
		}

		Section {
			SettingsToggle(
				title: .Settings.generalSpotlightConversations,
				note: .Settings.generalSpotlightNote,
				isOn: model.settings.binding(for: SettingsKeys.Spotlight.indexConversations)
			)
			SettingsToggle(
				title: .Settings.generalSpotlightDirectMessages,
				note: .Settings.generalSpotlightDirectMessagesNote,
				isEnabled: model.settings[SettingsKeys.Spotlight.indexConversations],
				isOn: model.settings.binding(for: SettingsKeys.Spotlight.indexDirectMessages)
			)
		} header: {
			Text(.Settings.generalHeadingSpotlight)
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

	/// The idle threshold and message, drawn disabled while idle-away is off.
	@ViewBuilder
	private var idleAwayRows: some View {
		let isEnabled = model.settings[SettingsKeys.Connection.awayOnIdle]
		let minutes = model.settings.binding(for: SettingsKeys.Connection.idleAwayMinutes)

		Stepper(
			value: minutes,
			in: IdleAwayDecision.minimumMinutes ... IdleAwayDecision.maximumMinutes,
			step: 1
		) {
			Text(.Settings.generalAwayIdleMinutes(Int(IdleAwayDecision.clampedMinutes(minutes.wrappedValue))))
		}
		.disabled(isEnabled == false)

		TextField(text: model.settings.binding(for: SettingsKeys.Connection.idleAwayMessage)) {
			Text(.Settings.generalAwayIdleMessage)
		}
		.accessibilityLabel(Text(.Settings.generalAwayIdleMessage))
		.disabled(isEnabled == false)
	}
}
