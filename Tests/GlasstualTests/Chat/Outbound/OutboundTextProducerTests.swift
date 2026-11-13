// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** When the reader's own input goes out while inbound traffic fills the
 transcript.

 The render budget holds network reads until the transcript catches up, and
 typed input used to wait on the same budget. During a join burst the inbound
 reader took every slot that freed, so a typed line waited until the burst was
 over. Input entered into an idle producer now starts at once for a bounded
 number of steps; anything longer, and anything entered behind it, still waits
 and keeps its order. */
@MainActor
@Suite("Outbound text producer")
struct OutboundTextProducerTests {
	@Test("A line typed while the transcript is full goes out at once")
	func typedLineSkipsTheWait() throws {
		let (session, channel) = try fullSession()
		defer { session.cancelPendingSessionTasks() }

		session.inputText("hello", destination: channel)

		#expect(sentLines(of: session) == ["PRIVMSG #one :hello"])
	}

	@Test("A slash command typed while the transcript is full goes out at once")
	func typedCommandSkipsTheWait() throws {
		let (session, channel) = try fullSession()
		defer { session.cancelPendingSessionTasks() }

		session.inputText("/msg fixture E2E_BURST_SWITCH_1", destination: channel)

		#expect(sentLines(of: session) == ["PRIVMSG fixture :E2E_BURST_SWITCH_1"])
	}

	@Test("Long input takes a bounded number of steps without capacity and keeps later input behind it")
	func longInputIsBoundedAndOrdered() async throws {
		let admission = RenderAdmission(capacity: 1)
		let ticket = admission.submit(for: "inbound")
		let producer = OutboundTextProducer(admission: admission, idleAdmissionSteps: 3)
		var produced: [String] = []
		var remaining = 10
		producer.enqueue {
			remaining -= 1
			produced.append("paste \(9 - remaining)")
			return remaining > 0
		}
		producer.enqueue {
			produced.append("after")
			return false
		}

		#expect(produced == ["paste 0", "paste 1", "paste 2"])
		#expect(producer.pendingProducerCount == 2)

		admission.finish(ticket)
		try await Eventually.until("the producer drains") { producer.pendingProducerCount == 0 }
		#expect(produced == (0 ..< 10).map { "paste \($0)" } + ["after"])
	}

	private func fullSession() throws -> (TestServerSession, Conversation) {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.identity.hostmask = "me!user@example.org"
		session.markAsLoggedIn()
		let channel = try #require(session.findConversationOrCreate("#one"))
		channel.activate()
		let admission = RenderAdmission(capacity: 1)
		session.renderAdmission = admission
		_ = admission.submit(for: "inbound")
		#expect(admission.hasCapacity == false)
		return (session, channel)
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}
}
