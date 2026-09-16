/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

/** One notification, as the connection describes it.

 The title is who or what it is about, the subtitle is where it happened and
 the body is the detail: the shape Messages and Mail use, and the shape every
 event takes. */
struct PendingNotification {
	var event: NotificationEvent
	var title: String
	var subtitle: String?
	var body: String?
	var payload: NotificationPayload

	/** Whether this one interrupts.

	 The first notification of a burst in a conversation alerts; the ones behind
	 it are added to Notification Center quietly. */
	var alerts = true

	/// Whether the notification carries a sound for the system to play.
	var playsSound = true
}

/** What the connection needs from whatever posts notifications.

 The connection decides which events are worth interrupting for and what they
 say; the feature layer decides how they are delivered. This is the seam
 between the two, so nothing under `Protocol/` names a `Features/` type. */
@MainActor
protocol ClientNotificationPresenting: AnyObject {
	/// Whether the person has switched notifications off for now.
	var areNotificationsDisabled: Bool { get }

	/// Whether a notification in `thread` may alert now, as the first of a
	/// burst. Asking claims the alert, so it is asked once per notification.
	func claimsAlert(inThread thread: String?) -> Bool

	func post(_ notification: PendingNotification)
}
