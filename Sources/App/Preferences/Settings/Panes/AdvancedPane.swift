// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Advanced row: where transcripts are written, and the handful of
/// settings that are only worth changing on purpose.
struct AdvancedPane: View {
	private static let scrollbackPresets = [
		"100", "500", "1000", "1500", "2000", "2500", "3000", "3500", "4000", "4500", "5000",
	]

	let model: SettingsModel

	private var logsToDisk: Bool {
		model.preferences[Preferences.Logging.logToDisk]
	}

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.logLocationToggle,
				isOn: model.preferences.binding(for: Preferences.Logging.logToDisk)
			)
			SettingsFolderPicker(
				label: .Settings.logLocationFolderLabel,
				accessibilityLabel: .Settings.transcriptFolder,
				folder: model.transcriptFolder,
				emptyTitle: .Settings.noLogLocationSelected,
				select: { model.selectTranscriptFolder() },
				clear: { model.clearTranscriptFolder() }
			)
			.disabled(logsToDisk == false)
		} header: {
			Text(SettingsPane.logLocation.title)
		}

		Section {
			SettingsToggle(
				title: .Settings.hiddenAppNap,
				isOn: model.preferences.invertedBinding(for: Preferences.Internals.appSleepDisabled)
			)
			SettingsToggle(
				title: .Settings.hiddenLoadHistoryLazily,
				isOn: model.preferences.binding(for: Preferences.Logging.loadHistoryLazily)
			)
			SettingsToggle(
				title: .Settings.hiddenSidebarTranslucency,
				isOn: model.preferences.invertedBinding(
					for: Preferences.Appearance.disableSidebarTranslucency
				)
			)
			scrollbackLimitRow
		} header: {
			Text(SettingsPane.hidden.title)
		} footer: {
			VStack(alignment: .leading, spacing: SettingsMetrics.spacingSmall) {
				SettingsNote(.Settings.hiddenWarning)
				SettingsNote(.Settings.hiddenRestartNote)
			}
		}
	}

	private var scrollbackLimitRow: some View {
		LabeledContent {
			SettingsComboField(
				title: .Settings.hiddenScrollbackVisibleLimit,
				presets: Self.scrollbackPresets,
				value: model.preferences.numberField(
					for: Preferences.Logging.scrollbackVisibleLimit
				) {
					PreferenceReload.perform(.scrollbackVisibleLimit)
				},
				rejectionMessage: .PreferencesTransfer.enterAValidWholeNumber
			)
		} label: {
			Text(.Settings.hiddenScrollbackVisibleLimit)
			Text(.Settings.hiddenScrollbackVisibleLimitNote)
		}
	}
}
