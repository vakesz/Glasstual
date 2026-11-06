// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** An in-app announcement whose only payload is the object it is about.

 The subject travels in the message as well as in `Notification.object`, so an
 observer reads what changed from the message it is handed and filters on a
 subject by asking the center for that subject. Conforming types declare the
 name and the subject type; posting and decoding are shared. */
protocol SubjectMessage: NotificationCenter.MainActorMessage where Subject: AnyObject {
	var subject: Subject { get }
	init(subject: Subject)
}

extension SubjectMessage {
	static func makeMessage(_ notification: Notification) -> Self? {
		(notification.object as? Subject).map { Self(subject: $0) }
	}

	static func makeNotification(_ message: Self) -> Notification {
		Notification(name: name, object: message.subject)
	}

	/// Announces the message with its subject on `center`.
	@MainActor func post(on center: NotificationCenter = .default) {
		center.post(self, subject: subject)
	}
}
