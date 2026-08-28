/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing

@Suite("Transcript logger idle sweep")
struct FileLoggerIdleSweepTests {
	@Test("A handle that was never written to is never swept")
	func unwrittenHandleIsNotIdle() {
		#expect(FileLogger.fileHandleIsIdle(lastWriteTime: 0, at: 100_000) == false)
	}

	@Test(
		"A handle is swept only once nothing has been written for the idle limit",
		arguments: [
			(secondsSinceWrite: 0.0, idle: false),
			(secondsSinceWrite: 1199.0, idle: false),
			(secondsSinceWrite: 1200.0, idle: false),
			(secondsSinceWrite: 1201.0, idle: true),
			(secondsSinceWrite: 10000.0, idle: true),
		]
	)
	func idleLimitBoundary(secondsSinceWrite: Double, idle: Bool) {
		let lastWriteTime = 1_000_000.0

		#expect(
			FileLogger.fileHandleIsIdle(
				lastWriteTime: lastWriteTime,
				at: lastWriteTime + secondsSinceWrite
			) == idle
		)
	}
}

@Suite("Reachability path seeding")
struct ReachabilitySeedingTests {
	@Test("The first path seeds state without reporting a change")
	func firstPathIsSeedOnly() {
		var currentlyReachable = false
		var receivedInitialPath = false

		let event = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(event == ReachabilityPathEvent.none)
		#expect(currentlyReachable)
		#expect(receivedInitialPath)
	}

	@Test("A change after the seed is reported")
	func changeAfterSeedIsReported() {
		var currentlyReachable = false
		var receivedInitialPath = false

		_ = Reachability.evaluatePathChange(
			reachable: true,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		let event = Reachability.evaluatePathChange(
			reachable: false,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(event == .becameUnreachable)
		#expect(currentlyReachable == false)
	}

	@Test("A repeated path status is not reported as a change")
	func repeatedStatusIsNotAChange() {
		var currentlyReachable = false
		var receivedInitialPath = true

		let event = Reachability.evaluatePathChange(
			reachable: false,
			currentlyReachable: &currentlyReachable,
			receivedInitialPath: &receivedInitialPath
		)

		#expect(event == ReachabilityPathEvent.none)
	}

	/** The notifier is stopped on sleep and started again on wake. Seeding is per
	 object lifetime, not per start, so a connectivity change across the sleep is
	 still reported. */
	@Test("Seeding survives a stop and restart of the notifier")
	@MainActor
	func seedingSurvivesRestart() {
		let notifier = Reachability.reachabilityForInternetConnection()

		notifier.startNotifier()
		notifier.stopNotifier()
		notifier.startNotifier()
		notifier.stopNotifier()

		#expect(notifier.reachable == false)
	}
}

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
