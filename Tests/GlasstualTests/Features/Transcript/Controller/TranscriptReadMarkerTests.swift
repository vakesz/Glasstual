// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript read markers", .serialized)
struct TranscriptReadMarkerTests {
	private func line(_ body: String, date: TimeInterval = 100) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.receivedAt = Date(timeIntervalSince1970: date)
		line.serverTimestamp = line.receivedAt
		line.messageIdentifier = UUID().uuidString
		return line
	}

	/** The controller refers to its window weakly, as it does to its session, so
	 a test keeps both in scope for as long as the controller is in use. A window
	 passed as a temporary was gone by the time an `await` returned, and the view
	 the test then made never loaded its history. */
	private func window() -> MainWindow {
		MainWindow(contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
		           styleMask: .borderless, backing: .buffered, defer: false)
	}

	@Test("Buffered rendering is not a viewed timestamp until the transcript is displayed")
	func bufferedRenderingIsNotViewed() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		let message = line("waiting for the view")
		var wasDisplayed: Bool?
		controller.print(message) { wasDisplayed = $0.isDisplayed }
		await controller.drainRenderJobs()
		#expect(wasDisplayed == false)
		#expect(controller.lastRenderedLineDate() == nil)
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(controller.lastRenderedLineDate() == message.receivedAt)
	}

	@Test("Assigning an echoed msgid cannot turn a local timestamp into a read marker")
	func echoedIdentifierDoesNotEstablishServerTimestamp() async {
		let session = ServerSession(config: ServerConfig())
		let window = window()
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		_ = controller.ensureBackingView()
		await controller.drainRenderJobs()
		var message = line("printed locally")
		message.serverTimestamp = nil
		message.messageIdentifier = nil
		message.deliveryState = .pending
		controller.print(message)
		await controller.drainRenderJobs()

		controller.updateDeliveryState(forLineNumber: message.uniqueIdentifier, state: .delivered,
		                               messageIdentifier: "server-msgid", reason: nil)

		#expect(controller.lastRenderedLineDate() == nil)
		var incoming = line("server stamped", date: 200)
		incoming.messageIdentifier = nil
		controller.print(incoming)
		await controller.drainRenderJobs()
		#expect(controller.lastRenderedLineDate() == incoming.serverTimestamp)
	}
}
