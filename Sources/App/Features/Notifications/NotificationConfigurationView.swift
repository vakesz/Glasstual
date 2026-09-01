/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import SwiftUI

/// Native SwiftUI editor shared by application-wide notification settings and
/// a channel's three-state overrides.
@MainActor
struct NotificationConfigurationView: View {
	private enum SoundSelection: Hashable {
		case defaultSound
		case noSound
		case named(String)
	}

	let notifications: [NotificationConfigurationItem]
	let allowsInheritedState: Bool
	private let soundNames: [String]

	@State private var activeIndex: Int
	@State private var revision = 0

	init(notifications: [NotificationConfigurationItem], allowsInheritedState: Bool) {
		self.notifications = notifications
		self.allowsInheritedState = allowsInheritedState
		soundNames = SoundPlayer.uniqueListOfSounds()
		_activeIndex = State(initialValue: notifications.firstIndex { $0.configuration != nil } ?? 0)
	}

	private var activeConfiguration: (any NotificationConfiguration)? {
		guard notifications.indices.contains(activeIndex) else { return nil }
		return notifications[activeIndex].configuration
	}

	var body: some View {
		if let configuration = activeConfiguration {
			VStack(alignment: .leading, spacing: 14) {
				Picker(NotificationConfigurationStrings.selectedAlert, selection: $activeIndex) {
					ForEach(Array(notifications.enumerated()), id: \.offset) { index, item in
						if let alert = item.configuration {
							Text(verbatim: alert.displayName).tag(index)
						} else {
							Divider()
						}
					}
				}

				settingControl(
					NotificationConfigurationStrings.showNotification,
					value: binding(
						get: { configuration.pushNotification },
						set: { configuration.pushNotification = $0 }
					)
				)
				settingControl(
					NotificationConfigurationStrings.speak,
					value: binding(
						get: { configuration.speakEvent },
						set: { configuration.speakEvent = $0 }
					)
				)
				settingControl(
					NotificationConfigurationStrings.disableWhileAway,
					value: binding(
						get: { configuration.disabledWhileAway },
						set: { configuration.disabledWhileAway = $0 }
					)
				)
				settingControl(
					NotificationConfigurationStrings.bounceDockIcon,
					value: binding(get: { configuration.bounceDockIcon }, set: { configuration.bounceDockIcon = $0 })
				)
				settingControl(
					NotificationConfigurationStrings.bounceRepeatedly,
					value: binding(
						get: { configuration.bounceDockIconRepeatedly },
						set: { configuration.bounceDockIconRepeatedly = $0 }
					)
				)
				.disabled(configuration.bounceDockIcon == .off)

				Picker(
					NotificationConfigurationStrings.sound,
					selection: soundBinding(for: configuration)
				) {
					Text(verbatim: NotificationAlertSound.localizedDefaultTitle)
						.tag(SoundSelection.defaultSound)
					Text(verbatim: NotificationAlertSound.localizedNoSoundTitle)
						.tag(SoundSelection.noSound)
					Divider()
					ForEach(soundNames, id: \.self) { soundName in
						Text(verbatim: soundName).tag(SoundSelection.named(soundName))
					}
				}
			}
			.id(revision)
		} else {
			ContentUnavailableView(
				NotificationConfigurationStrings.noAlerts,
				systemImage: "bell.slash"
			)
		}
	}

	@ViewBuilder
	private func settingControl(_ title: String, value: Binding<ChannelEventOverride>) -> some View {
		if allowsInheritedState {
			Picker(title, selection: value) {
				Text(verbatim: NotificationConfigurationStrings.inherit).tag(ChannelEventOverride.inherited)
				Text(verbatim: NotificationConfigurationStrings.off).tag(ChannelEventOverride.off)
				Text(verbatim: NotificationConfigurationStrings.on).tag(ChannelEventOverride.on)
			}
			.pickerStyle(.segmented)
		} else {
			Toggle(
				title,
				isOn: Binding(
					get: { value.wrappedValue == .on },
					set: { value.wrappedValue = $0 ? .on : .off }
				)
			)
			.toggleStyle(.switch)
		}
	}

	private func binding(
		get: @escaping @MainActor @Sendable () -> ChannelEventOverride,
		set: @escaping @MainActor @Sendable (ChannelEventOverride) -> Void
	) -> Binding<ChannelEventOverride> {
		Binding(
			get: get,
			set: { value in
				set(value)
				revision &+= 1
			}
		)
	}

	private func soundBinding(for configuration: any NotificationConfiguration) -> Binding<SoundSelection> {
		Binding(
			get: {
				switch configuration.alertSound {
				case nil: .defaultSound
				case NotificationAlertSound.noSoundPreferenceValue: .noSound
				case let .some(name): .named(name)
				}
			},
			set: { selection in
				let name: String? = switch selection {
				case .defaultSound: nil
				case .noSound: NotificationAlertSound.noSoundPreferenceValue
				case let .named(name): name
				}
				if let name {
					SoundPlayer.playAlertSound(name)
				}
				configuration.alertSound = name
				revision &+= 1
			}
		)
	}
}
