// Copyright (c) 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("WHO rate-limit refusals")
struct ErrorNumericsTests {
	private func refuse(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))
		session.receiveRateLimitRefusalReply(message, shouldPrint: false)
	}

	@Test("A refusal naming a target closes that target's request", arguments: [416, 736])
	func targetedRefusalClosesNamedRequest(numeric: Int) throws {
		let session = TestServerSession()
		session.requestedCommands.recordWhoRequestOpened(for: "#first")
		session.requestedCommands.recordWhoRequestOpened(for: "#second")

		try refuse(":server \(numeric) me WHO #second :Rate limited", on: session)

		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#second") == nil)
		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#first") != nil)
	}

	@Test("A refusal without a target closes the oldest request", arguments: [416, 736])
	func untargetedRefusalClosesOldestRequest(numeric: Int) throws {
		let session = TestServerSession()
		session.requestedCommands.recordWhoRequestOpened(for: "#first")
		session.requestedCommands.recordWhoRequestOpened(for: "#second")

		try refuse(":server \(numeric) me WHO :Rate limited", on: session)

		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#first") == nil)
		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#second") != nil)
	}

	@Test("A 263 closes the oldest request even when it carries a target-shaped parameter")
	func tryAgainClosesOldestRequest() throws {
		let session = TestServerSession()
		session.requestedCommands.recordWhoRequestOpened(for: "#first")
		session.requestedCommands.recordWhoRequestOpened(for: "#second")

		try refuse(":server 263 me WHO #second :Please wait a while and try again", on: session)

		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#first") == nil)
		#expect(session.requestedCommands.recordWhoRequestClosed(for: "#second") != nil)
	}
}
