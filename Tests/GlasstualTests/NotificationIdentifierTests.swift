/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Notification identifiers")
@MainActor
struct NotificationIdentifierTests {
	@Test("A thread identifier needs a client and folds in the channel when present")
	func threadIdentifierComposition() {
		#expect(NotificationController.threadIdentifier(forClient: nil, channel: "c") == nil)
		#expect(NotificationController.threadIdentifier(forClient: "client", channel: nil) == "client")
		#expect(NotificationController.threadIdentifier(forClient: "client", channel: "chan") == "client-chan")
	}

	@Test("Notification identifiers separate distinct titles, messages and threads")
	func notificationIdentifiersAreDistinct() {
		let base = NotificationController.notificationIdentifier(
			title: "title",
			message: "message",
			threadIdentifier: "thread"
		)

		#expect(
			base == NotificationController.notificationIdentifier(
				title: "title",
				message: "message",
				threadIdentifier: "thread"
			)
		)
		#expect(
			base != NotificationController.notificationIdentifier(
				title: "other",
				message: "message",
				threadIdentifier: "thread"
			)
		)
		#expect(
			base != NotificationController.notificationIdentifier(
				title: "title",
				message: "other",
				threadIdentifier: "thread"
			)
		)
		#expect(
			base != NotificationController.notificationIdentifier(
				title: "title",
				message: "message",
				threadIdentifier: nil
			)
		)
	}

	@Test("Scope matching compares both identifiers, absent channels included")
	func scopeMatching() {
		let userInfo: [AnyHashable: Any] = [
			NotificationPayload.clientIdentifierKey: "client",
			NotificationPayload.channelIdentifierKey: "chan",
		]

		#expect(
			NotificationController.isNotification(
				userInfo: userInfo,
				inScopeOfClientIdentifier: "client",
				channelIdentifier: "chan"
			)
		)
		#expect(
			NotificationController.isNotification(
				userInfo: userInfo,
				inScopeOfClientIdentifier: "client",
				channelIdentifier: nil
			) == false
		)
		#expect(
			NotificationController.isNotification(
				userInfo: [NotificationPayload.clientIdentifierKey: "client"],
				inScopeOfClientIdentifier: "client",
				channelIdentifier: nil
			)
		)
	}
}
