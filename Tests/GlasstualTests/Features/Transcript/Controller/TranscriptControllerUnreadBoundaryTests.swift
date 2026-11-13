// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/** Where the unread boundary lands when it is asked for ahead of rendering.

 A line is printed before it is drawn, and so are the lines just before it.
 The boundary names the line it belongs above, so it lands there whatever
 the renderer had reached when it was asked for. */
@MainActor
@Suite("Transcript controller unread boundary", .serialized)
struct TranscriptControllerUnreadBoundaryTests {
	@Test("A boundary asked for before its line has rendered lands above that line")
	func boundaryWaitsForItsLine() async {
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

		let lines = ["read", "also read", "first unseen", "second unseen"].map(line)
		/* Nothing is drained between these: the two read lines are still
		 rendering when the boundary is asked for. */
		controller.print(lines[0])
		controller.print(lines[1])
		controller.mark(before: lines[2].uniqueIdentifier)
		#expect(view.displayedLines.contains { $0.markers.contains(where: \.isUnread) } == false)
		controller.print(lines[2])
		controller.print(lines[3])
		await controller.drainRenderJobs()

		let marked = view.displayedLines.filter { $0.markers.contains(where: \.isUnread) }.map(\.lineNumber)
		#expect(view.displayedLines.map(\.lineNumber) == lines.map(\.uniqueIdentifier))
		#expect(marked == [lines[2].uniqueIdentifier])
		#expect(controller.transcriptProjection.mark == .line(lines[2].uniqueIdentifier))
	}

	private func line(_ text: String) -> ChatLine {
		var line = ChatLine()
		line.messageBody = text
		line.lineType = .privateMessage
		line.nickname = "alice"
		return line
	}
}
