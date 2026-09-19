// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One notification, as the connection describes it.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail: the shape Messages and Mail use, and the shape every
 event takes. */
struct PendingUserNotification {
	var event: UserNotificationEvent
	var title: String
	var subtitle: String?
	var body: String?
	var payload: UserNotificationPayload

	/** Whether this one interrupts.

	 The first notification of a burst in a conversation alerts; the ones behind
	 it are added to Notification Center quietly. */
	var alerts = true

	/// Whether the notification carries a sound for the system to play.
	var playsSound = true
}
