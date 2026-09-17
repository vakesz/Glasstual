// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Labeled response tracking")
struct LabeledResponseTests {
	@Test("Registering a delivery hands back a label that is still pending")
	func registerCreatesPendingDeliveryWithLabel() throws {
		let client = clientWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: client)
		let label = try #require(client.registerPendingDelivery(for: channel))

		#expect(label == "g1")
		#expect(client.deliveryState(forLabel: label) == .pending)
	}

	@Test("A delivery that times out is retired")
	func timeoutRetiresDelivery() throws {
		let client = clientWithLabeledResponse()
		let channel = try makeChannel(named: "#chat", on: client)
		let label = try #require(client.registerPendingDelivery(for: channel))

		client.timeoutDelivery(withLabel: label)

		#expect(client.deliveryState(forLabel: label) == .none)
	}

	private func clientWithLabeledResponse() -> TestClient {
		let client = TestClient()
		client.enableCapability(.messageTags)
		client.enableCapability(.echoMessage)
		client.enableCapability(.labeledResponse)
		return client
	}

	private func makeChannel(named name: String, on client: TestClient) throws -> Channel {
		try #require(client.findChannelOrCreate(name))
	}
}
