// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Holds the second history read open until the test lets it answer, and
/// counts every read.
private actor SecondFetchGate {
	private var fetches = 0
	private var parked: CheckedContinuation<ScrollbackFetchOutcome, Never>?
	private var observers: [CheckedContinuation<Void, Never>] = []

	var fetchCount: Int {
		fetches
	}

	func fetch() async -> ScrollbackFetchOutcome {
		fetches += 1
		guard fetches == 2 else { return .page([]) }
		for observer in observers {
			observer.resume()
		}
		observers.removeAll()
		return await withCheckedContinuation { parked = $0 }
	}

	func waitUntilParked() async {
		guard fetches < 2 else { return }
		await withCheckedContinuation { observers.append($0) }
	}

	func release() {
		parked?.resume(returning: .page([]))
		parked = nil
	}
}

@MainActor
@Suite("Recovered history reload", .serialized)
struct TranscriptRecoveredHistoryReloadTests {
	private func line(_ text: String, at seconds: Double) -> ChatLine {
		var line = ChatLine()
		line.messageBody = text
		line.lineType = .privateMessage
		line.receivedAt = Date(timeIntervalSince1970: seconds)
		return line
	}

	/// Runs the pipeline until no read is under way: the read that follows one
	/// that just ended is submitted as that one is applied.
	private func drain(_ controller: TranscriptController) async {
		for _ in 0 ..< 20 {
			await controller.drainRenderJobs()
			guard controller.historyRecovery.isReloading else { return }
			await Task.yield()
		}
	}

	/** A gap fill arrives a page at a time, faster than a read of the store
	 finishes. A reload is refused while one is under way, so the pages after
	 the first were stored and never drawn: the banner went away and most of
	 the messages it promised did not appear. */
	@Test("A page recovered while history is being read is read again once that read ends",
	      .timeLimit(.minutes(1)))
	func pageRecoveredDuringAReloadIsReadAgain() async {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
		defer { controller.tearDown(.permanentRemoval) }
		let gate = SecondFetchGate()
		controller.historyPageFetcher = { _ in await gate.fetch() }

		controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(await gate.fetchCount == 1)
		#expect(controller.historyRecovery.isReloading == false)

		controller.archiveRecoveredChatLines([line("first page", at: 100)])
		await gate.waitUntilParked()
		#expect(controller.historyRecovery.isReloading)

		// The second page lands while the first page's read is still out.
		controller.archiveRecoveredChatLines([line("second page", at: 200)])
		#expect(controller.historyRecovery.recoveredLinesAwaitReload)
		#expect(await gate.fetchCount == 2)

		await gate.release()
		await drain(controller)

		#expect(await gate.fetchCount == 3)
		#expect(controller.historyRecovery.recoveredLinesAwaitReload == false)
		#expect(controller.historyRecovery.isReloading == false)
	}

	@Test("A page recovered with no read under way is read once")
	func pageRecoveredWhileIdleIsReadOnce() async {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(session: session, in: window)
		controller.loadsHistoryLazily = { false }
		defer { controller.tearDown(.permanentRemoval) }
		let fetches = SecondFetchGate()
		controller.historyPageFetcher = { _ in
			await fetches.fetch()
		}
		controller.ensureBackingView()
		await controller.drainRenderJobs()
		#expect(await fetches.fetchCount == 1)

		Task { await fetches.waitUntilParked(); await fetches.release() }
		controller.archiveRecoveredChatLines([line("only page", at: 100)])
		await drain(controller)

		#expect(await fetches.fetchCount == 2)
		#expect(controller.historyRecovery.recoveredLinesAwaitReload == false)
	}
}
