/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/// The Identity row: who a new connection says the user is, and the reasons an
/// operator's commands carry by default.
struct IdentityPane: View {
	let model: SettingsModel

	var body: some View {
		Section {
			SettingsNote(.Settings.defaultIdentityNote)
			identityField(.Settings.defaultIdentityNickname, key: Preferences.Identity.nickname)
			identityField(.Settings.defaultIdentityAwayNickname, key: Preferences.Identity.awayNickname)
			identityField(.Settings.defaultIdentityUsername, key: Preferences.Identity.username)
			identityField(.Settings.defaultIdentityRealname, key: Preferences.Identity.realName)
			SettingsNote(.Settings.defaultIdentityAllOptional)
		} header: {
			Text(SettingsPane.defaultIdentity.title)
		}

		Section {
			irCopField(.Settings.ircopKillLabel, note: nil, key: Preferences.Commands.irCopKillMessage)
			irCopField(
				.Settings.ircopGlineLabel,
				note: .Settings.ircopIncludesBanLength,
				key: Preferences.Commands.irCopGlineMessage
			)
			irCopField(
				.Settings.ircopShunLabel,
				note: .Settings.ircopIncludesBanLength,
				key: Preferences.Commands.irCopShunMessage
			)
		} header: {
			Text(SettingsPane.defaultIRCopMessages.title)
		}
	}

	private func identityField(
		_ label: LocalizedStringResource,
		key: PreferenceKey<String>
	) -> some View {
		TextField(
			text: model.preferences.binding(for: key),
			prompt: Text(.Settings.defaultIdentityOptional)
		) {
			Text(label)
		}
		.accessibilityLabel(Text(label))
	}

	private func irCopField(
		_ label: LocalizedStringResource,
		note: LocalizedStringResource?,
		key: PreferenceKey<String>
	) -> some View {
		TextField(text: model.preferences.binding(for: key)) {
			Text(label)

			if let note {
				Text(note)
			}
		}
		.accessibilityLabel(Text(label))
	}
}
