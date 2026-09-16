/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing
import UserNotifications

@MainActor
@Suite("Notification controller", .serialized)
struct NotificationControllerTests {
	/// The table lists every event by this name and a notification that is not
	/// someone speaking carries it as its title, so an event without one is an
	/// unlabelled row and a blank notification.
	@Test("Every event has a name", arguments: NotificationEvent.allCases)
	func everyEventHasAName(event: NotificationEvent) {
		#expect(NotificationStrings.eventTypeTitle(for: event).isEmpty == false)
	}

	@Test("A thread identifier needs a client, and takes the channel when there is one")
	func threadIdentifierCombinesClientAndChannel() {
		#expect(NotificationPayload(channelIdentifier: "chan").threadIdentifier == nil)
		#expect(NotificationPayload(clientIdentifier: "client-a").threadIdentifier == "client-a")
		#expect(
			NotificationPayload(clientIdentifier: "client-a", channelIdentifier: "chan-b").threadIdentifier
				== "client-a-chan-b"
		)
	}

	@Test("A notification without a channel is in scope only when no channel is asked for")
	func userInfoScopeMatchingTreatsNilChannelsAsEqual() {
		let clientOnly: [AnyHashable: Any] = [NotificationPayload.clientIdentifierKey: "c1"]
		let withChannel: [AnyHashable: Any] = [
			NotificationPayload.clientIdentifierKey: "c1",
			NotificationPayload.channelIdentifierKey: "ch1",
		]

		#expect(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: nil
		))

		#expect(NotificationController.isNotification(
			userInfo: clientOnly,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		) == false)

		#expect(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c1",
			channelIdentifier: "ch1"
		))

		#expect(NotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfClientIdentifier: "c2",
			channelIdentifier: "ch1"
		) == false)
	}

	/** The flags are written as an alternating pattern first. Comparing each
	 lookup against the key it is meant to read passes for a lookup wired to the
	 wrong key whenever the two keys agree, which at the shipped defaults they
	 do for every boolean pair here. */
	@Test("A lookup with no channel answers with the global preference")
	func preferenceLookupsWithNilChannelMatchGlobalPreferences() {
		let eventType = NotificationEvent.highlight
		let sound = Preferences.Notifications.sound(eventType)
		let flags: [NotificationSetting] = [
			.enabled, .speak, .disabledWhileAway, .bounceDockIcon, .bounceDockIconRepeatedly,
		]
		let storedSound = sound.storedValue
		let storedFlags = flags.map { Preferences.Notifications.flag(eventType, $0).storedValue }
		defer {
			sound.storedValue = storedSound
			for (flag, stored) in zip(flags, storedFlags) {
				Preferences.Notifications.flag(eventType, flag).storedValue = stored
			}
		}

		sound.value = "Glass"
		for (offset, flag) in flags.enumerated() {
			Preferences.Notifications.flag(eventType, flag).value = offset.isMultiple(of: 2)
		}

		#expect(NotificationEventSettings.sound(for: eventType, in: nil) == "Glass")
		#expect(NotificationEventSettings.isEnabled(eventType, in: nil))
		#expect(NotificationEventSettings.speaks(eventType, in: nil) == false)
		#expect(NotificationEventSettings.isDisabledWhileAway(eventType, in: nil))
		#expect(NotificationEventSettings.bouncesDockIcon(for: eventType, in: nil) == false)
		#expect(NotificationEventSettings.bouncesDockIconRepeatedly(for: eventType, in: nil))
	}

	/** What the delegate answers for a notification that arrives while Glasstual
	 is frontmost. The options are the whole of what the system then does with
	 it: without `.sound` the banner appears and the sound the notification
	 carries is dropped, which was every sound raised while the application was
	 in front. */
	@Test("A notification presented in the foreground keeps its sound")
	func foregroundPresentationKeepsTheSound() {
		let presented = NotificationController.presentationOptions(notificationsAreDisabled: false)

		#expect(presented.contains(.sound))
		#expect(presented.contains(.banner))
		#expect(presented.contains(.list))
		#expect(NotificationController.presentationOptions(notificationsAreDisabled: true).isEmpty)
	}

	/// The system alert is the one sound that is not a file in a Sounds folder;
	/// a notification names it by asking for the default sound.
	@Test("The alert sound a notification carries is resolved by name")
	func notificationSoundResolvesByName() {
		#expect(NotificationController.notificationSound(named: NotificationAlertSound.noSoundPreferenceValue) == nil)
		#expect(NotificationController.notificationSound(named: SoundPlayer.beepSoundName) == .default)
		#expect(NotificationController.notificationSound(named: "Submarine") != nil)
	}

	/** A channel override wins over the application-wide value, and an
	 inherited one falls back to it. */
	@Test("A channel override answers before the global preference")
	func channelOverrideAnswersFirst() {
		let flag = Preferences.Notifications.flag(.highlight, .enabled)
		let stored = flag.storedValue
		defer { flag.storedValue = stored }
		flag.value = true

		var config = ChannelConfig(channelName: "#glasstual")
		config.setNotificationEnabled(.off, forEvent: .highlight)
		let channel = Channel(config: config)

		#expect(NotificationEventSettings.isEnabled(.highlight, in: channel) == false)

		config.setNotificationEnabled(.inherited, forEvent: .highlight)
		channel.updateConfig(config, fireChangedNotification: false, updateStoredChannelList: false)

		#expect(NotificationEventSettings.isEnabled(.highlight, in: channel))
	}

	/** A reply typed into a notification went nowhere once the query it came
	 from had been closed, because the channel identifier no longer found
	 anything. The notification carries the nickname, so the query opens again. */
	@Test("A reply to a closed query opens the query again")
	func replyToAClosedQueryReopensIt() throws {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig(connectionName: "Replies"))
		let query = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		let payload = NotificationPayload(
			clientIdentifier: client.uniqueIdentifier,
			channelIdentifier: query.uniqueIdentifier,
			queryName: "alice"
		)

		#expect(NotificationController.replyDestination(for: payload, in: fixture.world) === query)

		fixture.world.destroyChannel(query)

		let reopened = try #require(NotificationController.replyDestination(for: payload, in: fixture.world))
		#expect(reopened.isPrivateMessage)
		#expect(reopened.name == "alice")
		#expect(reopened !== query)
	}

	@Test("A reply with no query name or no connection has nowhere to go")
	func replyWithoutADestinationIsDropped() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.world.createClient(with: ClientConfig(connectionName: "Replies"))

		#expect(NotificationController.replyDestination(
			for: NotificationPayload(clientIdentifier: client.uniqueIdentifier, channelIdentifier: "gone"),
			in: fixture.world
		) == nil)
		#expect(NotificationController.replyDestination(
			for: NotificationPayload(clientIdentifier: "no-such-client", queryName: "alice"),
			in: fixture.world
		) == nil)
	}

	/// Each category has to say something in place of a hidden preview, and
	/// the summary format has to keep the count the system fills in.
	@Test("Every category has a hidden-preview placeholder and a counted summary", arguments: NotificationCategory.allCases)
	func categoriesDescribeHiddenPreviewsAndStacks(category: NotificationCategory) {
		let registered = category.notificationCategory

		#expect(registered.identifier == category.rawValue)
		#expect(registered.hiddenPreviewsBodyPlaceholder.isEmpty == false)
		#expect(registered.categorySummaryFormat.contains("%u"))
	}

	@Test("A file transfer request offers Accept and Decline, and a private message offers Reply")
	func eventsCarryTheirActions() {
		let fileTransfer = NotificationCategory(event: .fileTransferReceiveRequested).notificationCategory
		let privateMessage = NotificationCategory(event: .privateMessage).notificationCategory
		let highlight = NotificationCategory(event: .highlight).notificationCategory

		#expect(fileTransfer.actions.map(\.identifier) == [
			NotificationCategory.Action.acceptFileTransfer.rawValue,
			NotificationCategory.Action.declineFileTransfer.rawValue,
		])
		#expect(privateMessage.actions.map(\.identifier) == [NotificationCategory.Action.replyToPrivateMessage.rawValue])
		#expect(highlight.actions.isEmpty)
	}
}
