// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the connection needs from whatever posts notifications.

 The connection decides which events are worth interrupting for and what they
 say; the feature layer decides how they are delivered. This is the seam between
 the two: nothing here names a view, a window or a controller.

 What a notification *is* — ``PendingUserNotification`` and the event and payload
 it carries — is filled in by the connection, so it lives beside it in
 `Chat/Notifications` and the seam speaks in those values rather than declaring a
 second set of its own. */
@MainActor
protocol UserNotificationPresenting: AnyObject {
	/// Whether the person has switched notifications off for now.
	var areNotificationsDisabled: Bool { get }

	/// Whether a notification in `thread` may alert now, as the first of a
	/// burst. Asking claims the alert, so it is asked once per notification.
	func claimsAlert(inThread thread: String?) -> Bool

	func post(_ notification: PendingUserNotification)

	/// Asks the application to draw attention to itself, which is the Dock
	/// bounce beside the banner. The connection decides that an event is worth
	/// interrupting for; how the interruption looks is not its business.
	func requestUserAttention()

	/// Plays the alert sound `name`, which is what `/notifysound` asks for. A
	/// notification carries the system alert instead, so this is the one path
	/// that names a sound.
	func playAlertSound(named name: String)
}
