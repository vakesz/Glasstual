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
		#expect(String(localized: event.title).isEmpty == false)
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

	/// A muted conversation stops before anything is built for the event.
	@Test("A muted conversation is quiet, and a file transfer still asks")
	func muteSilencesAConversationButNotATransfer() {
		func admission(_ event: NotificationEvent, muted: Bool) -> NotificationAdmission {
			NotificationPolicy.admission(for: NotificationAdmissionContext(
				event: event,
				isTerminating: false,
				isCollapsingNetsplit: false,
				nicknameIsLocalUser: false,
				conversationIsMuted: muted
			))
		}

		#expect(admission(.highlight, muted: true) == .quiet)
		#expect(admission(.highlight, muted: false) == .proceed)
		#expect(admission(.fileTransferReceiveRequested, muted: true) == .proceed)
	}

	/// Only what is addressed to the person interrupts; the room's own traffic
	/// is the transcript's job.
	@Test("Room events do not post, mentions and private messages do")
	func onlyDirectEventsPost() {
		func posts(_ event: NotificationEvent, mentions: Bool = true) -> Bool {
			NotificationPolicy.postsNotification(
				event: event,
				notifiesAboutMentions: mentions,
				postWhileFocused: true,
				mainWindowIsFocused: false,
				targetIsSelected: false
			)
		}

		#expect(posts(.highlight))
		#expect(posts(.privateMessage))
		#expect(posts(.kick))
		#expect(posts(.channelMessage) == false)
		#expect(posts(.userJoined) == false)
		#expect(posts(.connect) == false)
		#expect(posts(.highlight, mentions: false) == false)
		// A transfer asks a question the transcript cannot answer.
		#expect(posts(.fileTransferReceiveRequested, mentions: false))
	}

	/// A conversation the person is reading needs no banner for what is already
	/// on screen.
	@Test("Nothing posts for the conversation in front of the person")
	func focusedSelectionSuppressesTheNotification() {
		#expect(NotificationPolicy.postsNotification(
			event: .highlight,
			notifiesAboutMentions: true,
			postWhileFocused: true,
			mainWindowIsFocused: true,
			targetIsSelected: true
		) == false)

		#expect(NotificationPolicy.postsNotification(
			event: .highlight,
			notifiesAboutMentions: true,
			postWhileFocused: false,
			mainWindowIsFocused: true,
			targetIsSelected: false
		) == false)
	}

	/** A reply typed into a notification went nowhere once the query it came
	 from had been closed, because the channel identifier no longer found
	 anything. The notification carries the nickname, so the query opens again. */
	@Test("A reply to a closed query opens the query again")
	func replyToAClosedQueryReopensIt() throws {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Replies"))
		let query = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		let payload = NotificationPayload(
			clientIdentifier: client.uniqueIdentifier,
			channelIdentifier: query.uniqueIdentifier,
			queryName: "alice"
		)

		#expect(NotificationController.replyDestination(for: payload, in: fixture.clientDirectory) === query)

		fixture.clientDirectory.destroyChannel(query)

		let reopened = try #require(NotificationController.replyDestination(for: payload, in: fixture.clientDirectory))
		#expect(reopened.isPrivateMessage)
		#expect(reopened.name == "alice")
		#expect(reopened !== query)
	}

	@Test("A reply with no query name or no connection has nowhere to go")
	func replyWithoutADestinationIsDropped() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Replies"))

		#expect(NotificationController.replyDestination(
			for: NotificationPayload(clientIdentifier: client.uniqueIdentifier, channelIdentifier: "gone"),
			in: fixture.clientDirectory
		) == nil)
		#expect(NotificationController.replyDestination(
			for: NotificationPayload(clientIdentifier: "no-such-client", queryName: "alice"),
			in: fixture.clientDirectory
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
