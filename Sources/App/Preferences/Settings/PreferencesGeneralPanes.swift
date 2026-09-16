/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import SwiftUI

struct PreferencesGeneralSections: View {
	@Bindable var model: PreferencesPaneModel

	var body: some View {
		Section {
			Picker(selection: $model.appLanguage) {
				ForEach(AppLanguage.allCases, id: \.self) { language in
					Text(verbatim: language.title).tag(language)
				}
			} label: {
				Text(.Settings.appLanguage)
			}
			.accessibilityIdentifier("settings-app-language")
		} footer: {
			Text(.Settings.languageRestartHelp)
		}

		Section {
			PreferencesToggle(
				title: PreferencesGeneralStrings.confirmQuit,
				isOn: model.preferences.binding(for: Preferences.Connection.confirmQuit)
			)
			PreferencesToggle(
				title: PreferencesGeneralStrings.awayOnScreenSleep,
				isOn: model.preferences.binding(for: Preferences.Connection.awayOnScreenSleep)
			)
			PreferencesToggle(
				title: PreferencesGeneralStrings.preventSleepWhileConnected,
				note: PreferencesGeneralStrings.preventSleepExplanation,
				isOn: model.preferences.binding(for: Preferences.Connection.preventSleepWhileConnected)
			)
		}

		Section {
			PreferencesToggle(
				title: PreferencesGeneralStrings.rejoinOnKick,
				isOn: model.preferences.binding(for: Preferences.Connection.rejoinOnKick)
			)
			PreferencesToggle(
				title: PreferencesGeneralStrings.autojoinOnInvite,
				isOn: model.preferences.binding(for: Preferences.Connection.autojoinOnInvite)
			)
		} header: {
			Text(verbatim: PreferencesGeneralStrings.headingChannels)
		}

		Section {
			PreferencesToggle(
				title: PreferencesGeneralStrings.reloadScrollback,
				isOn: model.preferences.binding(for: Preferences.Logging.reloadScrollbackOnLaunch)
			)
			PreferencesToggle(
				title: PreferencesGeneralStrings.rememberQueries,
				isOn: model.preferences.binding(for: Preferences.Appearance.rememberQueryStates)
			)
		} header: {
			Text(verbatim: PreferencesGeneralStrings.headingOnLaunch)
		}

		PreferencesRecoverySection()
	}
}

struct PreferencesCommandScopeSections: View {
	let model: PreferencesPaneModel

	private var noticeDestination: Binding<NoticeSendLocation> {
		model.preferences.binding(for: Preferences.Commands.noticeDestination)
	}

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesCommandScopeStrings.amsg,
				isOn: model.preferences.binding(for: Preferences.Commands.amsgAllConnections)
			)
			PreferencesToggle(
				title: PreferencesCommandScopeStrings.away,
				isOn: model.preferences.binding(for: Preferences.Commands.awayAllConnections)
			)
			PreferencesToggle(
				title: PreferencesCommandScopeStrings.nick,
				isOn: model.preferences.binding(for: Preferences.Commands.nickAllConnections)
			)
			PreferencesToggle(
				title: PreferencesCommandScopeStrings.clearall,
				isOn: model.preferences.binding(for: Preferences.Commands.clearAllConnections)
			)
			PreferencesToggle(
				title: PreferencesCommandScopeStrings.focusOnMessage,
				isOn: model.preferences.binding(for: Preferences.Commands.giveFocusOnMessageCommand)
			)
			Picker(selection: noticeDestination) {
				Text(verbatim: PreferencesCommandScopeStrings.noticeServerConsole)
					.tag(NoticeSendLocation.serverConsole)
				Text(verbatim: PreferencesCommandScopeStrings.noticeSelectedChannel)
					.tag(NoticeSendLocation.selectedChannel)
				Text(verbatim: PreferencesCommandScopeStrings.noticeQuery)
					.tag(NoticeSendLocation.query)
			} label: {
				Text(verbatim: PreferencesCommandScopeStrings.noticeLabel)
			}
			.pickerStyle(.radioGroup)
		} header: {
			Text(verbatim: PreferencesPane.commandScope.title)
		}
	}
}

struct PreferencesChannelManagementSections: View {
	let model: PreferencesPaneModel

	private var banFormat: Binding<HostmaskBanFormat> {
		model.preferences.binding(for: Preferences.Commands.banFormat)
	}

	var body: some View {
		Section {
			Picker(selection: banFormat) {
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhnin)
					.tag(HostmaskBanFormat.whnin)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhainn)
					.tag(HostmaskBanFormat.whainn)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhanni)
					.tag(HostmaskBanFormat.whanni)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatExact)
					.tag(HostmaskBanFormat.exact)
			} label: {
				Text(verbatim: PreferencesChannelManagementStrings.banFormatLabel)
			}
			PreferencesNote(PreferencesChannelManagementStrings.banFormatNote)
			TextField(text: model.preferences.binding(for: Preferences.Commands.kickMessage)) {
				Text(verbatim: PreferencesChannelManagementStrings.kickReasonLabel)
			}
			.accessibilityLabel(Text(verbatim: PreferencesChannelManagementStrings.kickReasonLabel))
		} header: {
			Text(verbatim: PreferencesPane.channelManagement.title)
		}
	}
}
