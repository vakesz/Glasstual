/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** Decides which notifications in a burst may alert.

 A busy query or a channel full of mentions used to raise one banner and one
 sound per line. Messages alerts once for a burst and adds the rest to
 Notification Center quietly, and this does the same. The first notification
 in a thread alerts. Every later one in that thread stays quiet until
 `window` has passed since the last alert. The quiet ones are still posted, so
 nothing is lost from Notification Center. */
struct NotificationBurstCoalescer {
	let window: Duration
	private var lastAlerts: [String: ContinuousClock.Instant] = [:]

	init(window: Duration = .seconds(5)) {
		self.window = window
	}

	/** Whether a notification in `thread` may alert at `now`, recording the
	 alert when it may.

	 A notification with no thread has nothing to be part of a burst with, so it
	 always alerts. */
	mutating func claimsAlert(inThread thread: String?, at now: ContinuousClock.Instant) -> Bool {
		guard let thread else { return true }

		if let last = lastAlerts[thread], now < last + window {
			return false
		}

		/* Threads whose window has closed no longer decide anything. Dropping them
		 here keeps the table as small as the number of threads alerting now. */
		lastAlerts = lastAlerts.filter { now < $0.value + window }
		lastAlerts[thread] = now
		return true
	}

	/// Forgets every burst, so the next notification in any thread alerts.
	mutating func reset() {
		lastAlerts.removeAll()
	}
}
