// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript controller replay ownership", .serialized)
struct TranscriptControllerReplayOwnershipTests {
	@Test("A queued receipt and its reaction retire when the view trims their row")
	func queuedReceiptRetiresWithTrim() async {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		view.setBufferLimit(1)

		var first = ChatLine()
		first.messageBody = "first"
		first.lineType = .privateMessage
		controller.print(first)
		await controller.drainRenderJobs()
		controller.updateDeliveryState(
			forLineNumber: first.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-ack",
			reason: nil
		)
		controller.noteReaction("+1", fromNickname: "bob", toMessageIdentifier: "server-ack")
		#expect(controller.reactions.reactions(forMessage: "server-ack") != nil)

		var second = ChatLine()
		second.messageBody = "second"
		second.lineType = .privateMessage
		controller.print(second)
		await controller.drainRenderJobs()

		#expect(view.displayedLines.map(\.lineNumber) == [second.uniqueIdentifier])
		#expect(controller.transcriptProjection.deliveryUpdates.isEmpty)
		#expect(controller.reactions.reactions(forMessage: "server-ack") == nil)
		#expect(controller.transcriptProjection.lineCount == 0)
	}

	@Test("A later history replay reads the displayed owner and keeps live state")
	func activeHistoryReplayKeepsDeliveryReactionsAndMarker() async throws {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(
			contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
			styleMask: .borderless, backing: .buffered, defer: false
		)
		let controller = TranscriptController(session: session, in: window)
		defer { controller.tearDown(.permanentRemoval) }
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()

		var message = ChatLine()
		message.messageBody = "visible before reload"
		message.lineType = .privateMessage
		message.nickname = "alice"
		message.messageIdentifier = UUID().uuidString
		controller.print(message)
		await controller.drainRenderJobs()
		let provisionalIdentifier = try #require(message.messageIdentifier)
		controller.noteReaction("+1", fromNickname: "carol", toMessageIdentifier: provisionalIdentifier)
		await controller.drainRenderJobs()
		controller.updateDeliveryState(
			forLineNumber: message.uniqueIdentifier,
			state: .delivered,
			messageIdentifier: "server-ack",
			reason: nil
		)
		await controller.drainRenderJobs()
		#expect(controller.reactions.reactions(forMessage: provisionalIdentifier) == nil)
		controller.noteReaction("+1", fromNickname: "bob", toMessageIdentifier: "server-ack")
		await controller.drainRenderJobs()
		controller.mark()
		#expect(controller.transcriptProjection.lineCount == 0)

		controller.reloadHistory()
		await controller.drainRenderJobs()

		#expect(view.displayedLines.count == 1)
		let row = try #require(view.displayedLines.first)
		#expect(row.lineNumber == message.uniqueIdentifier)
		#expect(row.deliveryState == .delivered)
		#expect(row.messageIdentifier == "server-ack")
		#expect(row.reactions == ["+1": ["carol", "bob"]])
		let hasUnreadMarker = row.markers.contains(where: \.isUnread)
		#expect(hasUnreadMarker)
		#expect(controller.transcriptProjection.lineCount == 0)
		#expect(controller.transcriptProjection.deliveryUpdates.isEmpty)
	}
}
