// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SettingsSearchTests {
	@Test("Theme controls are discoverable by their visible localized labels", arguments: [
		LocalizedStringResource.Settings.styleFontLabel,
		.Settings.styleNicknameFormatLabel,
		.Settings.styleTimestampFormatLabel,
		.TranscriptTheme.themeName,
		.TranscriptTheme.layout,
		.TranscriptTheme.bubbles,
		.TranscriptTheme.lineSpacing,
		.TranscriptTheme.messageSpacing,
		.TranscriptTheme.horizontalPadding,
		.TranscriptTheme.background,
		.TranscriptTheme.primaryText,
		.TranscriptTheme.highlightBackground,
		.TranscriptTheme.failure,
		.TranscriptTheme.importTheme,
		.TranscriptTheme.exportTheme,
	])
	func themeControlsAreSearchable(_ label: LocalizedStringResource) throws {
		let destination = try #require(SettingsDestination.row(showing: .style))
		#expect(destination.matches(searchText: String(localized: label)))
	}

	@Test("Folder and recovery controls are searchable without individual defaults keys", arguments: [
		(SettingsPane.general, LocalizedStringResource.SettingsTransfer.settingsAndRecovery),
		(.general, .SettingsTransfer.importConfiguration),
		(.general, .SettingsTransfer.exportConfiguration),
		(.general, .SettingsTransfer.previewBackup),
		(.general, .SettingsTransfer.showBackups),
		(.fileTransfers, .Settings.fileTransfersDestinationLabel),
		(.fileTransfers, .Settings.downloadDestination),
		(.fileTransfers, .Settings.fileTransfersUseDownloads),
		(.logLocation, .Settings.logLocationFolderLabel),
		(.logLocation, .Settings.transcriptFolder),
	])
	func nonKeyControlsAreSearchable(_ pane: SettingsPane, _ label: LocalizedStringResource) throws {
		let destination = try #require(SettingsDestination.row(showing: pane))
		#expect(destination.matches(searchText: String(localized: label)))
	}

	@Test("Retired rank-mark preferences stay compatible without advertising a removed control")
	func retiredRankMarkIsNotSearchable() {
		let key = SettingsKeys.Appearance.memberListNoModeSymbol
		let label = String(localized: .Settings.interfaceNoModeSymbol)
		#expect(SettingsKeys.key(named: key.name) != nil)
		#expect(SettingsPaneKeys.displayName(forKeyNamed: key.name) == label)
		#expect(SettingsDestination.builtIn.allSatisfy { $0.matches(searchText: label) == false })
		#expect(SettingsPaneKeys.keys(for: .interface).contains { $0.key.name == key.name } == false)
	}
}
