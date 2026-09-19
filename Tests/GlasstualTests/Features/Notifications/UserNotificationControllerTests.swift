// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing
import UserNotifications

@MainActor
@Suite("Notification controller", .serialized)
struct UserNotificationControllerTests {
	/// The table lists every event by this name and a notification that is not
	/// someone speaking carries it as its title, so an event without one is an
	/// unlabelled row and a blank notification.
	@Test("Every event has a name", arguments: UserNotificationEvent.allCases)
	func everyEventHasAName(event: UserNotificationEvent) {
		#expect(String(localized: event.title).isEmpty == false)
	}

	@Test("A thread identifier needs a session, and takes the channel when there is one")
	func threadIdentifierCombinesSessionAndChannel() {
		#expect(UserNotificationPayload(conversationIdentifier: "chan").threadIdentifier == nil)
		#expect(UserNotificationPayload(sessionIdentifier: "session-a").threadIdentifier == "session-a")
		#expect(
			UserNotificationPayload(sessionIdentifier: "session-a", conversationIdentifier: "chan-b").threadIdentifier
				== "session-a-chan-b"
		)
	}

	@Test("A notification without a channel is in scope only when no channel is asked for")
	func userInfoScopeMatchingTreatsNilChannelsAsEqual() {
		let sessionOnly: [AnyHashable: Any] = [UserNotificationPayload.sessionIdentifierKey: "c1"]
		let withChannel: [AnyHashable: Any] = [
			UserNotificationPayload.sessionIdentifierKey: "c1",
			UserNotificationPayload.conversationIdentifierKey: "ch1",
		]

		#expect(UserNotificationController.isNotification(
			userInfo: sessionOnly,
			inScopeOfSessionIdentifier: "c1",
			conversationIdentifier: nil
		))

		#expect(UserNotificationController.isNotification(
			userInfo: sessionOnly,
			inScopeOfSessionIdentifier: "c1",
			conversationIdentifier: "ch1"
		) == false)

		#expect(UserNotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfSessionIdentifier: "c1",
			conversationIdentifier: "ch1"
		))

		#expect(UserNotificationController.isNotification(
			userInfo: withChannel,
			inScopeOfSessionIdentifier: "c2",
			conversationIdentifier: "ch1"
		) == false)
	}

	/** What the delegate answers for a notification that arrives while Glasstual
	 is frontmost. The options are the whole of what the system then does with
	 it: without `.sound` the banner appears and the sound the notification
	 carries is dropped, which was every sound raised while the application was
	 in front. */
	@Test("A notification presented in the foreground keeps its sound")
	func foregroundPresentationKeepsTheSound() {
		let presented = UserNotificationController.presentationOptions(notificationsAreDisabled: false)

		#expect(presented.contains(.sound))
		#expect(presented.contains(.banner))
		#expect(presented.contains(.list))
		#expect(UserNotificationController.presentationOptions(notificationsAreDisabled: true).isEmpty)
	}

	/// A muted conversation stops before anything is built for the event.
	@Test("A muted conversation is refused, and a file transfer still asks")
	func muteSilencesAConversationButNotATransfer() {
		func admits(_ event: UserNotificationEvent, muted: Bool) -> Bool {
			UserNotificationPolicy.admits(UserNotificationAdmissionContext(
				event: event,
				isTerminating: false,
				isCollapsingNetsplit: false,
				nicknameIsLocalUser: false,
				conversationIsMuted: muted
			))
		}

		#expect(admits(.highlight, muted: true) == false)
		#expect(admits(.highlight, muted: false))
		#expect(admits(.fileTransferReceiveRequested, muted: true))
	}

	/// Only what is addressed to the person interrupts; the room's own traffic
	/// is the transcript's job.
	@Test("Room events do not post, mentions and private messages do")
	func onlyDirectEventsPost() {
		func posts(_ event: UserNotificationEvent, mentions: Bool = true) -> Bool {
			UserNotificationPolicy.postsNotification(
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
		#expect(UserNotificationPolicy.postsNotification(
			event: .highlight,
			notifiesAboutMentions: true,
			postWhileFocused: true,
			mainWindowIsFocused: true,
			targetIsSelected: true
		) == false)

		#expect(UserNotificationPolicy.postsNotification(
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
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Replies"))
		let query = try #require(session.findConversationOrCreate("alice", isDirect: true))
		let payload = UserNotificationPayload(
			sessionIdentifier: session.uniqueIdentifier,
			conversationIdentifier: query.uniqueIdentifier,
			directNickname: "alice"
		)

		#expect(UserNotificationController.replyDestination(for: payload, in: fixture.chatSession) === query)

		fixture.chatSession.destroyConversation(query)

		let reopened = try #require(UserNotificationController.replyDestination(for: payload, in: fixture.chatSession))
		#expect(reopened.isDirect)
		#expect(reopened.name == "alice")
		#expect(reopened !== query)
	}

	@Test("A reply with no query name or no connection has nowhere to go")
	func replyWithoutADestinationIsDropped() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Replies"))

		#expect(UserNotificationController.replyDestination(
			for: UserNotificationPayload(sessionIdentifier: session.uniqueIdentifier, conversationIdentifier: "gone"),
			in: fixture.chatSession
		) == nil)
		#expect(UserNotificationController.replyDestination(
			for: UserNotificationPayload(sessionIdentifier: "no-such-session", directNickname: "alice"),
			in: fixture.chatSession
		) == nil)
	}

	/// Each category has to say something in place of a hidden preview, and
	/// the summary format has to keep the count the system fills in.
	@Test("Every category has a hidden-preview placeholder and a counted summary", arguments: UserNotificationCategory.allCases)
	func categoriesDescribeHiddenPreviewsAndStacks(category: UserNotificationCategory) {
		let registered = category.userNotificationCategory

		#expect(registered.identifier == category.rawValue)
		#expect(registered.hiddenPreviewsBodyPlaceholder.isEmpty == false)
		#expect(registered.categorySummaryFormat.contains("%u"))
	}

	@Test("A file transfer request offers Accept and Decline, and a private message offers Reply")
	func eventsCarryTheirActions() {
		let fileTransfer = UserNotificationCategory(event: .fileTransferReceiveRequested).userNotificationCategory
		let privateMessage = UserNotificationCategory(event: .privateMessage).userNotificationCategory
		let highlight = UserNotificationCategory(event: .highlight).userNotificationCategory

		#expect(fileTransfer.actions.map(\.identifier) == [
			UserNotificationCategory.Action.acceptFileTransfer.rawValue,
			UserNotificationCategory.Action.declineFileTransfer.rawValue,
		])
		#expect(privateMessage.actions.map(\.identifier) == [UserNotificationCategory.Action.replyToPrivateMessage.rawValue])
		#expect(highlight.actions.isEmpty)
	}
}
