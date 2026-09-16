/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/** The Notifications row: what interrupts, whether it makes a sound and
 whether it counts on the Dock.

 Four switches, the way Messages has four. Muting one conversation is not here
 because it is not an application-wide choice: it belongs to that server or
 channel, and lives in its properties sheet. */
struct NotificationsPane: View {
	@Bindable var model: SettingsModel

	/// The row asks whether sounds play; the setting records whether they are
	/// muted, under the name the menu command has always written.
	private var playsSound: Binding<Bool> {
		let muted = model.preferences.binding(for: Preferences.Notifications.soundIsMuted)

		return Binding(
			get: { muted.wrappedValue == false },
			set: { muted.wrappedValue = $0 == false }
		)
	}

	var body: some View {
		Section {
			SettingsToggle(
				title: .Settings.notificationsNotifyMentions,
				note: .Settings.notificationsMuteNote,
				isOn: model.preferences.binding(for: Preferences.Notifications.notifyAboutMentions)
			)
			SettingsToggle(title: .Settings.notificationsPlaySound, isOn: playsSound)
		} header: {
			Text(.Settings.notificationsHeadingAlerts)
		}

		Section {
			SettingsToggle(
				title: .Settings.notificationsDockBadgePrivate,
				isOn: model.preferences.binding(for: Preferences.Notifications.displayDockBadge)
			)
			SettingsToggle(
				title: .Settings.notificationsDockBadgePublic,
				isOn: model.preferences.binding(for: Preferences.Notifications.publicMessageCountOnDockBadge)
			)
		} header: {
			Text(.Settings.notificationsHeadingDockIcon)
		}

		Section {
			SettingsToggle(
				title: .Settings.notificationsPostWhileInFocus,
				isOn: model.preferences.binding(for: Preferences.Notifications.postWhileInFocus)
			)
		} header: {
			Text(.Settings.notificationsHeadingDelivery)
		}
	}
}
