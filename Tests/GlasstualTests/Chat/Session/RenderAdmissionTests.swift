// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript render admission", .timeLimit(.minutes(1)))
struct RenderAdmissionTests {
	@Test("A render that produces no output releases its admission ticket")
	func declinedRenderReleasesTicket() async {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.enqueueRenderJob(render: { Int?.none }, apply: { _ in Issue.record("Absent output applied") })
		#expect(session.renderAdmission.pendingCount == 1)
		await controller.drainRenderJobs()
		#expect(session.renderAdmission.pendingCount == 0)
	}

	@Test("Retiring old work leaves replacement tickets owned by their new pipeline")
	func retiredTicketCannotReleaseReplacement() async throws {
		let admission = RenderAdmission(capacity: 1)
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
		let admission = RenderAdmission(capacity: 1)
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
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		var applied = false
		controller.enqueueRenderJob(render: { 42 }, apply: { _ in applied = true })
		#expect(session.renderAdmission.pendingCount == 1)
		#expect(!applied)
		await controller.drainRenderJobs()
		#expect(applied)
		#expect(session.renderAdmission.pendingCount == 0)
		controller.enqueueRenderJob(render: { 42 }, apply: { _ in Issue.record("Retired output applied") })
		controller.clear()
		#expect(session.renderAdmission.pendingCount == 0)
		await controller.drainRenderJobs()
	}

	@Test("A full render budget holds the network acknowledgement until application completes")
	func networkWaitsForApplication() async throws {
		let session = TestServerSession()
		session.forwardsProcessedMessages = true
		session.setConnectionTransportForTesting(.connected)
		session.renderAdmission = RenderAdmission(capacity: 1)
		let ticket = session.renderAdmission.submit(for: "test-view")
		defer { session.renderAdmission.finish(ticket) }
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		let (acknowledgements, acknowledge) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		connection.callbackReceiver.didReceive([Data("PING :bounded".utf8)]) {
			acknowledge.yield(())
			acknowledge.finish()
		}
		let deadline = ContinuousClock.now + .seconds(5)
		while session.renderAdmission.waitingProducerCount == 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		try #require(session.renderAdmission.waitingProducerCount == 1)
		#expect(session.sentLines.count == 0)
		session.renderAdmission.finish(ticket)
		for await _ in acknowledgements {}
		#expect(session.sentLines as? [String] == ["PONG bounded"])
		#expect(session.renderAdmission.waitingProducerCount == 0)
	}

	@Test("Cancelling a producer releases its wait without retiring another view")
	func cancellingProducer() async {
		let admission = RenderAdmission(capacity: 1)
		let ticket = admission.submit(for: "retained-view")
		let producer = Task { await admission.waitForCapacity() }
		producer.cancel()
		await producer.value
		#expect(admission.pendingCount == 1)
		admission.finish(ticket)
		#expect(admission.pendingCount == 0)
	}
}
