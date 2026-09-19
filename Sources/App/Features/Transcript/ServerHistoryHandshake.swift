// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** One transcript's end of the server-history handshake.

 The transcript asks the server for the lines before the oldest it holds, one
 page at a time, and what the answer said about that cursor is what decides
 whether asking again could bring anything back. A value the controller owns
 rather than six properties spread across it: each of them changes what the
 recovery banner offers, so the controller mirrors the whole of it in one place
 whenever it moves. */
struct ServerHistoryHandshake {
	/// The page the server has been asked for and has not answered.
	var request: ServerHistoryRequest?
	/// The cursor the server has already answered for. Asking for it again would
	/// bring the same page back, so it is asked for once.
	private(set) var completedBefore: Date?
	/// The cursor the server said it has nothing before.
	private(set) var exhaustedBefore: Date?
	/// Whether the last answer was a refusal, which is what the banner offers
	/// Retry Server History for, and what the server said about it.
	private(set) var failed = false
	private(set) var failureReason: String?

	/// Whether the page before `cursor` is one the server has not answered yet.
	func canAsk(before cursor: Date) -> Bool {
		request == nil && exhaustedBefore != cursor && completedBefore != cursor
	}

	/// Whether `candidate` is the page still in flight.
	func isCurrent(_ candidate: ServerHistoryRequest) -> Bool {
		request?.id == candidate.id
	}

	/// The session took the request, so the last refusal is no longer what the
	/// reader is waiting on.
	mutating func noteAdmitted() {
		failed = false
		failureReason = nil
	}

	/** Drops the request in flight.

	 `forgettingAnsweredCursor` is for an answer that left the transcript where it
	 was — a cancellation, or a page whose lines it already had — after which the
	 same cursor has to be askable again. */
	mutating func retire(forgettingAnsweredCursor: Bool = false) {
		request = nil
		if forgettingAnsweredCursor {
			completedBefore = nil
		}
	}

	/// The server answered the page before `cursor`. Where `extent` says it has
	/// nothing left, `oldestCursor` is where it is exhausted — which the caller
	/// reads from what the transcript now begins with, and which can be nothing.
	mutating func noteAnswered(before cursor: Date, extent: ServerHistoryPageExtent, oldestCursor: Date?) {
		completedBefore = cursor
		if case .exhausted = extent {
			exhaustedBefore = oldestCursor
		}
	}

	/// The server refused the page. The cursor stays askable: a refusal says
	/// nothing about what is stored behind it.
	mutating func noteFailed(reason: String?) {
		request = nil
		completedBefore = nil
		failed = true
		failureReason = reason
	}

	/// Forgets which cursors have been answered, so the page the reader asks for
	/// again is asked for again.
	mutating func forgetAnsweredCursors() {
		completedBefore = nil
		exhaustedBefore = nil
	}

	/// Everything about a transcript that is being replaced, since nothing is
	/// waiting for the page any more. The caller cancels the request handed back.
	mutating func reset() -> ServerHistoryRequest? {
		let retired = request
		self = ServerHistoryHandshake()
		return retired
	}
}
