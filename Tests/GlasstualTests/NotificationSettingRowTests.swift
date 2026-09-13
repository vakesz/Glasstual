/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@MainActor
@Suite("Notification settings table rows", .serialized)
struct NotificationSettingRowTests {
	/** The table edits the row, and the row is what writes to preferences. If
	 it only mirrored them the pane would show the change and store nothing,
	 which is the failure the old bindings avoided by writing through and then
	 rebuilding every control to read it back. */
	@Test("Editing a row writes through to the configuration it was made from")
	func editingARowWritesThrough() {
		let event = NotificationEvent.userJoined
		let flags: [NotificationSetting] = [
			.enabled, .speak, .disabledWhileAway, .bounceDockIcon, .bounceDockIconRepeatedly,
		]
		let sound = Preferences.Notifications.sound(event)
		let storedSound = sound.storedValue
		let storedFlags = flags.map { Preferences.Notifications.flag(event, $0).storedValue }
		defer {
			sound.storedValue = storedSound
			for (flag, stored) in zip(flags, storedFlags) {
				Preferences.Notifications.flag(event, flag).storedValue = stored
			}
		}

		for flag in flags {
			Preferences.Notifications.flag(event, flag).value = false
		}
		sound.storedValue = nil

		let row = NotificationSettingRow(configuration: PreferencesNotificationConfiguration(eventType: event))

		#expect(row.id == event)
		#expect(row.showsNotification == .off)
		#expect(row.sound == .defaultSound)

		row.showsNotification = .on
		row.speaks = .on
		row.disabledWhileAway = .on
		row.bouncesDockIcon = .on
		row.bouncesRepeatedly = .on
		row.sound = .noSound

		for flag in flags {
			#expect(Preferences.Notifications.flag(event, flag).value, "\(flag)")
		}
		#expect(sound.storedValue == NotificationAlertSound.noSoundPreferenceValue)
	}

	/// "Default" is a choice, not the absence of one: it stores nothing, and
	/// storing "None" has to read back as "None" rather than as the default.
	@Test("A sound selection round trips through what it stores", arguments: [
		NotificationSoundSelection.defaultSound,
		.noSound,
		.named("Submarine"),
	])
	func soundSelectionRoundTrips(selection: NotificationSoundSelection) {
		#expect(NotificationSoundSelection(storedValue: selection.storedValue) == selection)
	}

	/// The separators the pane draws between groups of events are not events,
	/// so they are not rows.
	@Test("Only the events in the list become rows")
	func separatorsAreNotRows() {
		let model = NotificationConfigurationModel(
			notifications: [
				.configuration(PreferencesNotificationConfiguration(eventType: .highlight)),
				.separator,
				.configuration(PreferencesNotificationConfiguration(eventType: .kick)),
			],
			allowsInheritedState: false
		)

		#expect(model.rows.map(\.id) == [.highlight, .kick])
		#expect(model.allowsInheritedState == false)
	}
}
