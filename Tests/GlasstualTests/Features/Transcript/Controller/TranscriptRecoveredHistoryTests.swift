// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

/// Holds the first history read open until the test lets it answer with the
/// page it was given, and counts every read.
private actor FirstFetchGate {
	private var fetches = 0
	private var parked: CheckedContinuation<Void, Never>?
	private var observers: [CheckedContinuation<Void, Never>] = []
	private let page: [ScrollbackEntry]
	private let parks: Bool

	init(page: [ScrollbackEntry] = [], parks: Bool) {
		self.page = page
		self.parks = parks
	}

	var fetchCount: Int {
		fetches
	}

	func fetch() async -> ScrollbackFetchOutcome {
		fetches += 1
		guard fetches == 1 else { return .page([]) }
		if parks {
			for observer in observers {
				observer.resume()
			}
			observers.removeAll()
			await withCheckedContinuation { parked = $0 }
		}
		return .page(page)
	}

	func waitUntilParked() async {
		guard fetches < 1 else { return }
		await withCheckedContinuation { observers.append($0) }
	}

	func release() {
		parked?.resume()
		parked = nil
	}
}

/** Messages a gap fill recovers are older than the live end, so they are
 drawn between the lines they fall between rather than after the newest one.
 The store is read once, when the transcript loads; a fill does not read it
 again. */
@MainActor
@Suite("Recovered history", .serialized)
struct TranscriptRecoveredHistoryTests {
	private func line(_ text: String, at seconds: Double) -> ChatLine {
		var line = ChatLine()
		line.messageBody = text
		line.lineType = .privateMessage
		line.receivedAt = Date(timeIntervalSince1970: seconds)
		return line
	}

	/// Runs the pipeline until no read is under way and nothing is queued.
	private func drain(_ controller: TranscriptController) async {
		for _ in 0 ..< 20 {
			await controller.drainRenderJobs()
			guard controller.historyRecovery.isReloading else { return }
			await Task.yield()
		}
	}

	/// The controller holds its session and its window weakly, so the fixture
	/// keeps both alive.
	private struct Fixture {
		let session = ServerSession(config: ServerConfig())
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller: TranscriptController

		init() {
			controller = TranscriptController(session: session, in: window)
			controller.loadsHistoryLazily = { false }
			controller.reloadsScrollbackOnLaunch = { true }
		}
	}

	private func displayedText(_ controller: TranscriptController) -> [String] {
		controller.backingView?.displayedLines.map(\.body.plainText) ?? []
	}

	@Test("Recovered pages are drawn between the lines they fall between, without reading the store again")
	func recoveredPagesAreDrawnInPlace() async {
		let fixture = Fixture()
		let controller = fixture.controller
		defer { withExtendedLifetime(fixture) { controller.tearDown(.permanentRemoval) } }
		let gate = FirstFetchGate(page: [
			line("live end", at: 500), line("before the gap", at: 100),
		].map { $0.scrollbackEntry(forView: controller.uniqueIdentifier) }, parks: false)
		controller.historyPageFetcher = { _ in await gate.fetch() }
		controller.ensureBackingView()
		await drain(controller)
		#expect(displayedText(controller) == ["before the gap", "live end"])

		controller.archiveRecoveredChatLines([line("gap one", at: 200), line("gap two", at: 300)])
		controller.archiveRecoveredChatLines([line("gap three", at: 400), line("too old", at: 50)])
		await drain(controller)

		#expect(displayedText(controller) == ["before the gap", "gap one", "gap two", "gap three", "live end"])
		#expect(await gate.fetchCount == 1)
		#expect(controller.newestLineNumber == controller.backingView?.displayedLines.last?.lineNumber)
	}

	/** A fill can answer while the transcript is still reading its stored
	 history. Placed against a transcript that read has not filled yet, the
	 page would land above lines older than it. */
	@Test("A page recovered while history is being read is placed once that read ends",
	      .timeLimit(.minutes(1)))
	func pageRecoveredDuringAReadWaitsForIt() async {
		let fixture = Fixture()
		let controller = fixture.controller
		defer { withExtendedLifetime(fixture) { controller.tearDown(.permanentRemoval) } }
		let gate = FirstFetchGate(page: [
			line("live end", at: 500), line("before the gap", at: 100),
		].map { $0.scrollbackEntry(forView: controller.uniqueIdentifier) }, parks: true)
		controller.historyPageFetcher = { _ in await gate.fetch() }

		controller.ensureBackingView()
		await gate.waitUntilParked()
		#expect(controller.historyRecovery.isReloading)
		controller.archiveRecoveredChatLines([line("gap", at: 300)])

		await gate.release()
		await drain(controller)

		#expect(displayedText(controller) == ["before the gap", "gap", "live end"])
		#expect(await gate.fetchCount == 1)
		#expect(controller.historyRecovery.isReloading == false)
	}

	@Test("A window of stored history keeps what it shows; the recovered lines are only stored")
	func detachedWindowKeepsWhatItShows() async {
		let fixture = Fixture()
		let controller = fixture.controller
		defer { withExtendedLifetime(fixture) { controller.tearDown(.permanentRemoval) } }
		let gate = FirstFetchGate(parks: false)
		controller.historyPageFetcher = { _ in await gate.fetch() }
		controller.ensureBackingView()
		await drain(controller)
		controller.historyRecovery.beginDetached()

		controller.archiveRecoveredChatLines([line("gap", at: 300)])
		await drain(controller)

		#expect(displayedText(controller).isEmpty)
	}
}
