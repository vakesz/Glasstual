// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/// The Commands row: which connections a command reaches, and the words the
/// channel commands send on the user's behalf.
struct CommandsPane: View {
	let model: SettingsModel

	private var noticeDestination: Binding<NoticeSendLocation> {
		model.preferences.binding(for: Preferences.Commands.noticeDestination)
	}

	private var banFormat: Binding<HostmaskBanFormat> {
		model.preferences.binding(for: Preferences.Commands.banFormat)
	}

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.commandScopeAmsg,
				isOn: model.preferences.binding(for: Preferences.Commands.amsgAllConnections)
			)
			SettingsToggle(
				title: .Settings.commandScopeAway,
				isOn: model.preferences.binding(for: Preferences.Commands.awayAllConnections)
			)
			SettingsToggle(
				title: .Settings.commandScopeNick,
				isOn: model.preferences.binding(for: Preferences.Commands.nickAllConnections)
			)
			SettingsToggle(
				title: .Settings.commandScopeClearall,
				isOn: model.preferences.binding(for: Preferences.Commands.clearAllConnections)
			)
			SettingsToggle(
				title: .Settings.commandScopeFocusOnMessage,
				isOn: model.preferences.binding(for: Preferences.Commands.giveFocusOnMessageCommand)
			)
			Picker(selection: noticeDestination) {
				Text(.Settings.commandScopeNoticeServerConsole)
					.tag(NoticeSendLocation.serverConsole)
				Text(.Settings.commandScopeNoticeSelectedChannel)
					.tag(NoticeSendLocation.selectedChannel)
				Text(.Settings.commandScopeNoticeQuery)
					.tag(NoticeSendLocation.query)
			} label: {
				Text(.Settings.commandScopeNoticeLabel)
			}
			.pickerStyle(.radioGroup)
		} header: {
			Text(SettingsPane.commandScope.title)
		}

		Section {
			Picker(selection: banFormat) {
				Text(.Settings.channelManagementBanFormatWhnin)
					.tag(HostmaskBanFormat.whnin)
				Text(.Settings.channelManagementBanFormatWhainn)
					.tag(HostmaskBanFormat.whainn)
				Text(.Settings.channelManagementBanFormatWhanni)
					.tag(HostmaskBanFormat.whanni)
				Text(.Settings.channelManagementBanFormatExact)
					.tag(HostmaskBanFormat.exact)
			} label: {
				Text(.Settings.channelManagementBanFormatLabel)
			}
			SettingsNote(.Settings.channelManagementBanFormatNote)
			TextField(text: model.preferences.binding(for: Preferences.Commands.kickMessage)) {
				Text(.Settings.channelManagementKickReasonLabel)
			}
			.accessibilityLabel(Text(.Settings.channelManagementKickReasonLabel))
		} header: {
			Text(SettingsPane.channelManagement.title)
		}
	}
}
