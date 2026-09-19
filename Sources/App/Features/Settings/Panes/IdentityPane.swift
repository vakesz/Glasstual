// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Identity row: who a new connection says the user is, and the reasons an
/// operator's commands carry by default.
struct IdentityPane: View {
	let model: SettingsModel

	var body: some View {
		Section {
			SettingsNote(.Settings.defaultIdentityNote)
			identityField(.Settings.defaultIdentityNickname, key: SettingsKeys.Identity.nickname)
			identityField(.Settings.defaultIdentityAwayNickname, key: SettingsKeys.Identity.awayNickname)
			identityField(.Settings.defaultIdentityUsername, key: SettingsKeys.Identity.username)
			identityField(.Settings.defaultIdentityRealname, key: SettingsKeys.Identity.realName)
			SettingsNote(.Settings.defaultIdentityAllOptional)
		} header: {
			Text(SettingsPane.defaultIdentity.title)
		}

		Section {
			irCopField(.Settings.ircopKillLabel, note: nil, key: SettingsKeys.Commands.irCopKillMessage)
			irCopField(
				.Settings.ircopGlineLabel,
				note: .Settings.ircopIncludesBanLength,
				key: SettingsKeys.Commands.irCopGlineMessage
			)
			irCopField(
				.Settings.ircopShunLabel,
				note: .Settings.ircopIncludesBanLength,
				key: SettingsKeys.Commands.irCopShunMessage
			)
		} header: {
			Text(SettingsPane.defaultIRCopMessages.title)
		}
	}

	private func identityField(
		_ label: LocalizedStringResource,
		key: SettingsKey<String>
	) -> some View {
		TextField(
			text: model.settings.binding(for: key),
			prompt: Text(.Settings.defaultIdentityOptional)
		) {
			Text(label)
		}
		.accessibilityLabel(Text(label))
	}

	private func irCopField(
		_ label: LocalizedStringResource,
		note: LocalizedStringResource?,
		key: SettingsKey<String>
	) -> some View {
		TextField(text: model.settings.binding(for: key)) {
			Text(label)

			if let note {
				Text(note)
			}
		}
		.accessibilityLabel(Text(label))
	}
}
