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

struct PreferencesGeneralPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesToggle(
					title: PreferencesGeneralStrings.confirmQuit,
					isOn: model.preferences.binding(for: Preferences.Connection.confirmQuit)
				)
			}
		}
	}
}

struct PreferencesBehaviorPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			Section {
				PreferencesToggle(
					title: PreferencesBehaviorStrings.openLinksInBackground,
					isOn: model.preferences.binding(for: Preferences.Messages.openBrowserInBackground)
				)
			}

			Section {
				PreferencesToggle(
					title: PreferencesBehaviorStrings.rejoinOnKick,
					isOn: model.preferences.binding(for: Preferences.Connection.rejoinOnKick)
				)
				PreferencesToggle(
					title: PreferencesBehaviorStrings.autojoinOnInvite,
					isOn: model.preferences.binding(for: Preferences.Connection.autojoinOnInvite)
				)
				PreferencesToggle(
					title: PreferencesBehaviorStrings.awayOnScreenSleep,
					isOn: model.preferences.binding(for: Preferences.Connection.awayOnScreenSleep)
				)
			}

			Section {
				PreferencesToggle(
					title: PreferencesBehaviorStrings.reloadScrollback,
					isOn: model.preferences.binding(for: Preferences.Logging.reloadScrollbackOnLaunch)
				)
				PreferencesToggle(
					title: PreferencesBehaviorStrings.rememberQueries,
					isOn: model.preferences.binding(for: Preferences.Appearance.rememberQueryStates)
				)
				VStack(alignment: .leading, spacing: 4) {
					PreferencesToggle(
						title: PreferencesBehaviorStrings.sendTypingNotifications,
						isOn: model.preferences.binding(for: Preferences.Connection.sendTypingNotifications)
					)
					PreferencesNote(PreferencesBehaviorStrings.typingNotificationsNote)
				}
			}
		}
	}
}

struct PreferencesCompatibilityPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesCompatibilitySections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesCompatibilitySections: View {
	let model: PreferencesPaneModel

	var body: some View {
		Section {
			PreferencesToggle(
				title: PreferencesCompatibilityStrings.echoMessage,
				isOn: model.preferences.binding(for: Preferences.Connection.echoMessageCapability)
			)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.compatibility))
		}
	}
}

struct PreferencesCommandScopePane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesCommandScopeSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesCommandScopeSections: View {
	let model: PreferencesPaneModel

	private var noticeDestination: Binding<TXNoticeSendLocation> {
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
					.tag(TXNoticeSendLocation.serverConsole)
				Text(verbatim: PreferencesCommandScopeStrings.noticeSelectedChannel)
					.tag(TXNoticeSendLocation.selectedChannel)
				Text(verbatim: PreferencesCommandScopeStrings.noticeQuery)
					.tag(TXNoticeSendLocation.query)
			} label: {
				Text(verbatim: PreferencesCommandScopeStrings.noticeLabel)
			}
			.pickerStyle(.radioGroup)
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.commandScope))
		}
	}
}

struct PreferencesChannelManagementPane: View {
	let model: PreferencesPaneModel

	var body: some View {
		PreferencesPaneLayout {
			PreferencesChannelManagementSections(model: model)
		}
	}
}

/// The pane as one form section, for the Advanced group that gathers it with
/// its neighbours.
struct PreferencesChannelManagementSections: View {
	let model: PreferencesPaneModel

	private var banFormat: Binding<TXHostmaskBanFormat> {
		model.preferences.binding(for: Preferences.Commands.banFormat)
	}

	var body: some View {
		Section {
			Picker(selection: banFormat) {
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhnin)
					.tag(TXHostmaskBanFormat.whnin)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhainn)
					.tag(TXHostmaskBanFormat.whainn)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatWhanni)
					.tag(TXHostmaskBanFormat.whanni)
				Text(verbatim: PreferencesChannelManagementStrings.banFormatExact)
					.tag(TXHostmaskBanFormat.exact)
			} label: {
				Text(verbatim: PreferencesChannelManagementStrings.banFormatLabel)
			}
			PreferencesNote(PreferencesChannelManagementStrings.banFormatNote)
			VStack(alignment: .leading, spacing: 6) {
				Text(verbatim: PreferencesChannelManagementStrings.kickReasonLabel)
				TextField(
					"",
					text: model.preferences.binding(for: Preferences.Commands.kickMessage)
				)
				.labelsHidden()
				.accessibilityLabel(Text(verbatim: PreferencesChannelManagementStrings.kickReasonLabel))
			}
		} header: {
			Text(verbatim: PreferencesStrings.paneTitle(.channelManagement))
		}
	}
}
