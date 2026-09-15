/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/** The notification settings shared by the application-wide pane and a
 channel's overrides.

 Every event is a row and every setting a column, so the whole table is
 readable at once and one event can be compared with its neighbours. It used to
 be a pop-up that revealed one of nineteen events at a time, which made "which
 events bounce the Dock?" a question you answered by clicking nineteen times. */
@MainActor
struct NotificationConfigurationView: View {
	let model: NotificationConfigurationModel

	/// An override needs room for three named states; a plain switch is a
	/// checkbox and needs room for nothing.
	private var settingColumnWidth: CGFloat {
		model.allowsInheritedState ? 104 : 68
	}

	var body: some View {
		if model.rows.isEmpty {
			ContentUnavailableView(
				NotificationConfigurationStrings.noEvents,
				systemImage: "bell.slash"
			)
		} else {
			Table(model.rows) {
				TableColumn(NotificationConfigurationStrings.event) { row in
					Text(verbatim: row.name)
				}
				.width(min: 140, ideal: 180)

				TableColumn(NotificationConfigurationStrings.showNotification) { row in
					setting(
						NotificationConfigurationStrings.showNotification,
						value: row.showsNotification
					) { row.showsNotification = $0 }
				}
				.width(settingColumnWidth)

				TableColumn(NotificationConfigurationStrings.speak) { row in
					setting(NotificationConfigurationStrings.speak, value: row.speaks) { row.speaks = $0 }
				}
				.width(settingColumnWidth)

				TableColumn(NotificationConfigurationStrings.disableWhileAway) { row in
					setting(
						NotificationConfigurationStrings.disableWhileAway,
						value: row.disabledWhileAway
					) { row.disabledWhileAway = $0 }
				}
				.width(settingColumnWidth)

				TableColumn(NotificationConfigurationStrings.bounceDockIcon) { row in
					setting(
						NotificationConfigurationStrings.bounceDockIcon,
						value: row.bouncesDockIcon
					) { row.bouncesDockIcon = $0 }
				}
				.width(settingColumnWidth)

				TableColumn(NotificationConfigurationStrings.bounceRepeatedly) { row in
					setting(
						NotificationConfigurationStrings.bounceRepeatedly,
						value: row.bouncesRepeatedly
					) { row.bouncesRepeatedly = $0 }
						/* Repeating a bounce that does not happen is not a
						 setting, and inheriting the Dock bounce is not agreeing
						 to it either, so only an explicit "on" enables this. */
						.disabled(row.bouncesDockIcon != .on)
				}
				.width(settingColumnWidth)

				TableColumn(NotificationConfigurationStrings.sound) { row in
					soundPicker(for: row)
				}
				.width(min: 120, ideal: 150)
			}
			.frame(minHeight: 260)
		}
	}

	/// The label is hidden because the column heading already names the
	/// setting, and kept because that heading is not the control's own
	/// accessibility label.
	@ViewBuilder
	private func setting(
		_ title: String,
		value: ChannelEventOverride,
		set: @escaping @MainActor @Sendable (ChannelEventOverride) -> Void
	) -> some View {
		if model.allowsInheritedState {
			Picker(title, selection: Binding(get: { value }, set: set)) {
				Text(verbatim: NotificationConfigurationStrings.inherit).tag(ChannelEventOverride.inherited)
				Text(verbatim: NotificationConfigurationStrings.off).tag(ChannelEventOverride.off)
				Text(verbatim: NotificationConfigurationStrings.on).tag(ChannelEventOverride.on)
			}
			.labelsHidden()
		} else {
			Toggle(title, isOn: Binding(get: { value == .on }, set: { set($0 ? .on : .off) }))
				.labelsHidden()
		}
	}

	private func soundPicker(for row: NotificationSettingRow) -> some View {
		Picker(
			NotificationConfigurationStrings.sound,
			selection: Binding(get: { row.sound }, set: { row.sound = $0 })
		) {
			Text(verbatim: NotificationAlertSound.localizedDefaultTitle)
				.tag(NotificationSoundSelection.defaultSound)
			Text(verbatim: NotificationAlertSound.localizedNoSoundTitle)
				.tag(NotificationSoundSelection.noSound)
			Divider()
			ForEach(model.soundNames, id: \.self) { soundName in
				Text(verbatim: soundName).tag(NotificationSoundSelection.named(soundName))
			}
		}
		.labelsHidden()
	}
}
