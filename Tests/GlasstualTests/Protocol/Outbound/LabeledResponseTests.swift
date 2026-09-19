// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Labeled response tracking")
struct LabeledResponseTests {
	@Test("Registering a delivery hands back a label that is still pending")
	func registerCreatesPendingDeliveryWithLabel() throws {
		let session = sessionWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: session)
		let label = try #require(session.registerPendingDelivery(for: channel))

		#expect(label == "g1")
		#expect(session.deliveryState(forLabel: label) == .pending)
	}

	@Test("A delivery that times out is retired")
	func timeoutRetiresDelivery() throws {
		let session = sessionWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: session)
		let label = try #require(session.registerPendingDelivery(for: channel))

		session.timeoutDelivery(withLabel: label)

		#expect(session.deliveryState(forLabel: label) == .none)
	}

	private func sessionWithLabeledResponse() -> TestServerSession {
		let session = TestServerSession()
		session.enableCapability(.messageTags)
		session.enableCapability(.echoMessage)
		session.enableCapability(.labeledResponse)
		return session
	}

	private func makeChannel(named name: String, on session: TestServerSession) throws -> Conversation {
		try #require(session.findConversationOrCreate(name))
	}
}
