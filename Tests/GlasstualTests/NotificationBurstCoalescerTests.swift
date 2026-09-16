/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import Testing
import UserNotifications

@Suite("Notification burst coalescer")
struct NotificationBurstCoalescerTests {
	private let start = ContinuousClock.now

	/// A busy conversation raised one banner and one sound per line. Only the
	/// first line of a burst alerts now, and the thread alerts again once the
	/// window since that alert has passed.
	@Test("One alert per thread per window")
	func oneAlertPerThreadPerWindow() {
		var coalescer = NotificationBurstCoalescer(window: .seconds(5))

		let alerts = [
			coalescer.claimsAlert(inThread: "client-query", at: start),
			coalescer.claimsAlert(inThread: "client-query", at: start + .seconds(1)),
			coalescer.claimsAlert(inThread: "client-query", at: start + .milliseconds(4999)),
			coalescer.claimsAlert(inThread: "client-query", at: start + .seconds(5)),
			coalescer.claimsAlert(inThread: "client-query", at: start + .seconds(6)),
		]

		#expect(alerts == [true, false, false, true, false])
	}

	@Test("Threads burst independently, and a notification with no thread always alerts")
	func threadsAreIndependent() {
		var coalescer = NotificationBurstCoalescer(window: .seconds(5))

		let alerts = [
			coalescer.claimsAlert(inThread: "client-a", at: start),
			coalescer.claimsAlert(inThread: "client-b", at: start + .seconds(1)),
			coalescer.claimsAlert(inThread: nil, at: start + .seconds(1)),
			coalescer.claimsAlert(inThread: nil, at: start + .seconds(2)),
			coalescer.claimsAlert(inThread: "client-a", at: start + .seconds(2)),
		]

		#expect(alerts == [true, true, true, true, false])
	}

	@Test("Resetting forgets every burst")
	func resetForgetsBursts() {
		var coalescer = NotificationBurstCoalescer(window: .seconds(5))

		let beforeReset = coalescer.claimsAlert(inThread: "client-a", at: start)
		coalescer.reset()
		let afterReset = coalescer.claimsAlert(inThread: "client-a", at: start + .seconds(1))

		#expect(beforeReset)
		#expect(afterReset)
	}

	/// Joins, parts and quits go to Notification Center without a banner or a
	/// sound, and everything else interrupts as usual.
	@Test("Membership changes are passive", arguments: NotificationEvent.allCases)
	func membershipChangesArePassive(event: NotificationEvent) {
		let passive: Set<NotificationEvent> = [.userJoined, .userParted, .userDisconnected]

		#expect(NotificationPolicy.interruptionLevel(for: event) == (passive.contains(event) ? .passive : .active))
	}
}
