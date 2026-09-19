// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import os

private let highlightRecordLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "HighlightRecord"
)

/** An entry in a session's in-memory highlight log.

 A value, owned by the session that logged it (`ServerSession.cachedHighlights`) and
 read by `HighlightLogWindow`, which sorts and draws the entries itself
 rather than binding an `NSArrayController` to them by KVC key path.

 Its identity is the line it logged: `lineNumber` names one printed line. */
struct HighlightRecord: Codable, Hashable, Sendable {
	var lineLogged: ChatLine
	var sessionId: String
	var conversationId: String

	init(lineLogged: ChatLine, sessionId: String, conversationId: String) {
		self.lineLogged = lineLogged
		self.sessionId = sessionId
		self.conversationId = conversationId

		// An incomplete entry used to abort the app from a health check; it is
		// only logged now, and callers that care check `isWellFormed`.
		if isWellFormed == false {
			highlightRecordLogger.error("Created an incomplete highlight log entry")
		}
	}

	/// `true` when the entry carries everything its accessors need.
	var isWellFormed: Bool {
		sessionId.isEmpty == false && conversationId.isEmpty == false
	}

	var timeLogged: Date {
		lineLogged.receivedAt
	}

	var lineNumber: String {
		lineLogged.uniqueIdentifier
	}
}
