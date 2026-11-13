// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Server history handshake")
struct ServerHistoryHandshakeTests {
	private let date = Date(timeIntervalSince1970: 1000)
	private let older = Date(timeIntervalSince1970: 500)

	private func makeRequest() -> ServerHistoryRequest {
		ServerHistoryRequest(id: UUID(), before: date, oldestLineNumber: nil)
	}

	@Test("A fresh handshake allows asking and reports nothing exhausted")
	func fresh() {
		let handshake = ServerHistoryHandshake()
		#expect(handshake.canAsk(before: date))
		#expect(handshake.exhaustedBefore == nil)
		#expect(handshake.failed == false)
	}

	@Test("A request in flight blocks asking, and retiring it allows it again")
	func requestLifecycle() {
		var handshake = ServerHistoryHandshake()
		let request = makeRequest()
		handshake.request = request
		#expect(handshake.canAsk(before: date) == false)
		#expect(handshake.isCurrent(request))
		#expect(handshake.isCurrent(makeRequest()) == false)
		handshake.retire()
		#expect(handshake.canAsk(before: date))
	}

	@Test("An answered cursor is asked once unless the answer is forgotten")
	func answeredCursor() {
		var handshake = ServerHistoryHandshake()
		handshake.noteAnswered(before: date, extent: .unknown, oldestCursor: older)
		handshake.retire()
		#expect(handshake.canAsk(before: date) == false)
		#expect(handshake.canAsk(before: older))
		#expect(handshake.canAsk(before: date, lineNumber: "7"))
		handshake.retire(forgettingAnsweredCursor: true)
		#expect(handshake.canAsk(before: date))
	}

	@Test("An exhausted answer records where the history ends")
	func exhausted() {
		var handshake = ServerHistoryHandshake()
		handshake.noteAnswered(before: date, extent: .exhausted, oldestCursor: older)
		#expect(handshake.exhaustedBefore == older)
		#expect(handshake.canAsk(before: older) == false)
		handshake.forgetAnsweredCursors()
		#expect(handshake.exhaustedBefore == nil)
		#expect(handshake.canAsk(before: older))
	}

	@Test("An exhausted answer with no oldest cursor records nothing")
	func exhaustedWithoutCursor() {
		var handshake = ServerHistoryHandshake()
		handshake.noteAnswered(before: date, extent: .exhausted, oldestCursor: nil)
		#expect(handshake.exhaustedBefore == nil)
	}

	@Test("A refusal keeps the cursor askable and records the reason until the next admission")
	func failure() {
		var handshake = ServerHistoryHandshake()
		handshake.request = makeRequest()
		handshake.noteFailed(reason: "denied")
		#expect(handshake.failed)
		#expect(handshake.failureReason == "denied")
		#expect(handshake.request == nil)
		#expect(handshake.canAsk(before: date))
		handshake.noteAdmitted()
		#expect(handshake.failed == false)
		#expect(handshake.failureReason == nil)
	}

	@Test("Resetting hands back the request in flight and clears everything")
	func reset() {
		var handshake = ServerHistoryHandshake()
		let request = makeRequest()
		handshake.request = request
		handshake.noteAnswered(before: date, extent: .exhausted, oldestCursor: older)
		handshake.noteFailed(reason: "x")
		handshake.request = request
		#expect(handshake.reset() == request)
		#expect(handshake.request == nil)
		#expect(handshake.failed == false)
		#expect(handshake.exhaustedBefore == nil)
		#expect(handshake.canAsk(before: date))
	}
}
