/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Observation

/// Which alert sound a row has chosen. "Default" and "None" are choices in
/// their own right rather than the absence of one, so they are cases.
enum NotificationSoundSelection: Hashable {
	case defaultSound
	case noSound
	case named(String)

	init(storedValue: String?) {
		self = switch storedValue {
		case nil: .defaultSound
		case NotificationAlertSound.noSoundPreferenceValue: .noSound
		case let .some(name): .named(name)
		}
	}

	var storedValue: String? {
		switch self {
		case .defaultSound: nil
		case .noSound: NotificationAlertSound.noSoundPreferenceValue
		case let .named(name): name
		}
	}
}

/** One row of the notification settings table.

 The values are mirrored here because nothing behind a
 `NotificationConfiguration` is observable: the application-wide rows read and
 write `UserDefaults`, and a channel's rows read and write the properties
 sheet's config. Each `didSet` writes straight through, so the mirror cannot
 drift from what it edits, and SwiftUI redraws the one cell that changed. The
 pane used to force that redraw by bumping a counter from inside a binding and
 hanging `.id()` on the whole editor, which rebuilt every control on every
 click. */
@MainActor
@Observable
final class NotificationSettingRow: Identifiable {
	let event: NotificationEvent

	var id: NotificationEvent {
		event
	}

	var name: String {
		NotificationStrings.eventTypeTitle(for: event)
	}

	var showsNotification: ChannelEventOverride {
		didSet { configuration.pushNotification = showsNotification }
	}

	var speaks: ChannelEventOverride {
		didSet { configuration.speakEvent = speaks }
	}

	var disabledWhileAway: ChannelEventOverride {
		didSet { configuration.disabledWhileAway = disabledWhileAway }
	}

	var bouncesDockIcon: ChannelEventOverride {
		didSet { configuration.bounceDockIcon = bouncesDockIcon }
	}

	var bouncesRepeatedly: ChannelEventOverride {
		didSet { configuration.bounceDockIconRepeatedly = bouncesRepeatedly }
	}

	/// Picking a sound plays it, which is the only way to tell two of them
	/// apart from a menu of names.
	var sound: NotificationSoundSelection {
		didSet {
			configuration.alertSound = sound.storedValue
			if let name = sound.storedValue {
				SoundPlayer.playAlertSound(name)
			}
		}
	}

	private let configuration: any NotificationConfiguration

	init(configuration: any NotificationConfiguration) {
		self.configuration = configuration
		event = configuration.eventType
		showsNotification = configuration.pushNotification
		speaks = configuration.speakEvent
		disabledWhileAway = configuration.disabledWhileAway
		bouncesDockIcon = configuration.bounceDockIcon
		bouncesRepeatedly = configuration.bounceDockIconRepeatedly
		sound = NotificationSoundSelection(storedValue: configuration.alertSound)
	}
}

/// The notification settings table: one row per event, one column per setting.
@MainActor
@Observable
final class NotificationConfigurationModel {
	let rows: [NotificationSettingRow]

	/// Whether a row may say "inherit the application-wide value", which is
	/// what a channel's overrides add and the application-wide settings cannot.
	let allowsInheritedState: Bool

	let soundNames: [String]

	init(notifications: [NotificationConfigurationItem], allowsInheritedState: Bool) {
		rows = notifications.compactMap(\.configuration).map(NotificationSettingRow.init)
		self.allowsInheritedState = allowsInheritedState
		soundNames = SoundPlayer.uniqueListOfSounds()
	}
}
