// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript render admission", .timeLimit(.minutes(1)))
struct TranscriptRenderAdmissionTests {
	@Test("A render that produces no output releases its admission ticket")
	func declinedRenderReleasesTicket() async {
		let client = Client(config: ClientConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.enqueueRenderJob(render: { Int?.none }, apply: { _ in Issue.record("Absent output applied") })
		#expect(client.renderAdmission.pendingCount == 1)
		await controller.drainRenderJobs()
		#expect(client.renderAdmission.pendingCount == 0)
	}

	@Test("Retiring old work leaves replacement tickets owned by their new pipeline")
	func retiredTicketCannotReleaseReplacement() async throws {
		let admission = TranscriptRenderAdmission(capacity: 1)
		let old = admission.submit(for: "view")
		admission.retire(view: "view")
		let replacement = admission.submit(for: "view")
		let producer = Task { await admission.waitForCapacity() }
		defer { producer.cancel(); admission.finish(replacement) }
		let deadline = ContinuousClock.now + .seconds(5)
		while admission.waitingProducerCount == 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		try #require(admission.waitingProducerCount == 1)
		admission.finish(old)
		#expect(admission.pendingCount == 1)
		#expect(admission.waitingProducerCount == 1)
		admission.finish(replacement)
		await producer.value
		#expect(admission.pendingCount == 0)
		#expect(admission.waitingProducerCount == 0)
	}

	@Test("Cancellation removes a suspended producer while other waiters remain blocked")
	func cancellingSuspendedProducer() async throws {
		let admission = TranscriptRenderAdmission(capacity: 1)
		let ticket = admission.submit(for: "view")
		let cancelled = Task { await admission.waitForCapacity() }
		let waiting = Task { await admission.waitForCapacity() }
		defer { cancelled.cancel(); waiting.cancel(); admission.finish(ticket) }
		let deadline = ContinuousClock.now + .seconds(5)
		while admission.waitingProducerCount < 2, ContinuousClock.now < deadline {
			await Task.yield()
		}
		try #require(admission.waitingProducerCount == 2)
		cancelled.cancel()
		await cancelled.value
		#expect(admission.pendingCount == 1)
		#expect(admission.waitingProducerCount == 1)
		admission.finish(ticket)
		await waiting.value
		#expect(admission.waitingProducerCount == 0)
	}

	@Test("Application and view retirement release submitted work")
	func workLivesThroughApplication() async {
		let client = Client(config: ClientConfig())
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(client: client, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		var applied = false
		controller.enqueueRenderJob(render: { 42 }, apply: { _ in applied = true })
		#expect(client.renderAdmission.pendingCount == 1)
		#expect(!applied)
		await controller.drainRenderJobs()
		#expect(applied)
		#expect(client.renderAdmission.pendingCount == 0)
		controller.enqueueRenderJob(render: { 42 }, apply: { _ in Issue.record("Retired output applied") })
		controller.clear()
		#expect(client.renderAdmission.pendingCount == 0)
		await controller.drainRenderJobs()
	}

	@Test("A full render budget holds the network acknowledgement until application completes")
	func networkWaitsForApplication() async throws {
		let client = TestClient()
		client.forwardsProcessedMessages = true
		client.isConnected = true
		client.renderAdmission = TranscriptRenderAdmission(capacity: 1)
		let ticket = client.renderAdmission.submit(for: "test-view")
		defer { client.renderAdmission.finish(ticket) }
		let connection = Connection(config: ConnectionConfig(), onClient: client)
		client.socket = connection
		let (acknowledgements, acknowledge) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		connection.callbackReceiver.ircConnectionDidReceive([Data("PING :bounded".utf8)]) {
			acknowledge.yield(())
			acknowledge.finish()
		}
		let deadline = ContinuousClock.now + .seconds(5)
		while client.renderAdmission.waitingProducerCount == 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		try #require(client.renderAdmission.waitingProducerCount == 1)
		#expect(client.sentLines.count == 0)
		client.renderAdmission.finish(ticket)
		for await _ in acknowledgements {}
		#expect(client.sentLines as? [String] == ["PONG bounded"])
		#expect(client.renderAdmission.waitingProducerCount == 0)
	}

	@Test("Cancelling a producer releases its wait without retiring another view")
	func cancellingProducer() async {
		let admission = TranscriptRenderAdmission(capacity: 1)
		let ticket = admission.submit(for: "retained-view")
		let producer = Task { await admission.waitForCapacity() }
		producer.cancel()
		await producer.value
		#expect(admission.pendingCount == 1)
		admission.finish(ticket)
		#expect(admission.pendingCount == 0)
	}
}
