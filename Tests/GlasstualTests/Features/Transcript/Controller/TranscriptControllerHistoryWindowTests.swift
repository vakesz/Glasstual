// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CoreData
@testable import Glasstual
import Testing

/// Jumping to a stored line that is not loaded, and coming back to the live end.
@MainActor
@Suite("Transcript history window", .serialized)
struct TranscriptControllerHistoryWindowTests {
	private struct Fixture {
		let directory: URL
		let context: NSManagedObjectContext
		let history: ScrollbackSession
		let controller: TranscriptController
		let identifier: String
		let view: TranscriptView
		/// The controller holds both weakly, so the fixture keeps them alive.
		let session: ServerSession
		let window: MainWindow
	}

	private func body(_ index: Int) -> String {
		"message-\(String(format: "%04d", index))-end"
	}

	/// A transcript over a store holding `count` lines, of which it loads the newest page.
	private func makeFixture(count: Int = 300) async throws -> Fixture {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
			UUID().uuidString, isDirectory: true
		)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		let context = try ScrollbackQueries.makeStack(at: directory.appendingPathComponent("history.sqlite"))
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture().store, makeStack: { _ in context })
		let history = ScrollbackSession(
			store: store,
			databaseDirectory: { directory.path },
			reportFailure: { Issue.record("\($0)") }
		)
		let session = ServerSession(config: ServerConfig())
		let identifier = session.uniqueIdentifier
		#expect(await history.retryLoading())
		for index in 0 ..< count {
			var line = ChatLine()
			line.messageBody = body(index)
			line.nickname = "alice"
			line.lineType = .privateMessage
			line.receivedAt = Date(timeIntervalSince1970: Double(index + 100))
			#expect(await history.writeEntry(line.scrollbackEntry(forView: identifier)) == .accepted)
		}
		#expect(await store.saveData() == .saved)
		let window = MainWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(
			session: session, in: window, inlineImageLoader: InlineImageLoader(),
			scrollback: Scrollback(session: history)
		)
		controller.loadsHistoryLazily = { false }
		controller.reloadsScrollbackOnLaunch = { true }
		let view = controller.ensureBackingView()
		await controller.drainRenderJobs()
		return Fixture(
			directory: directory, context: context, history: history, controller: controller,
			identifier: identifier, view: view, session: session, window: window
		)
	}

	private func finish(_ fixture: Fixture) async throws {
		fixture.controller.tearDown(.preservingRemoval)
		await fixture.history.prepareForTermination()
		try await ScrollbackFixture.close(fixture.context)
		try? FileManager.default.removeItem(at: fixture.directory)
	}

	private func hit(for index: Int, in fixture: Fixture) async throws -> ScrollbackSearchHit {
		let outcome = await fixture.history.search(ScrollbackSearchQuery(
			text: String(format: "%04d", index), viewIdentifiers: [fixture.identifier]
		))
		guard case let .results(hits, _) = outcome else {
			Issue.record("Expected results, got \(outcome)")
			throw CocoaError(.fileReadUnknown)
		}
		return try #require(hits.first)
	}

	private func displays(_ index: Int, in fixture: Fixture) -> Bool {
		fixture.view.displayedLines.contains { $0.body.plainText == body(index) }
	}

	@Test("An old line is shown inside a window of its neighbours, and the view is no longer live")
	func windowShowsAnOldLine() async throws {
		let fixture = try await makeFixture()
		#expect(displays(299, in: fixture))
		#expect(displays(10, in: fixture) == false)
		let target = try await hit(for: 10, in: fixture)

		let shown = await fixture.controller.showHistoryWindow(around: target)

		#expect(shown)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive)
		#expect(displays(10, in: fixture))
		#expect(displays(0, in: fixture))
		#expect(displays(60, in: fixture))
		#expect(displays(61, in: fixture) == false)
		#expect(displays(299, in: fixture) == false)
		#expect(fixture.view.containsLine(identifier: target.lineIdentifier))
		try await finish(fixture)
	}

	@Test("Lines that arrive while a window shows are stored and come back with the live end")
	func liveLinesWaitForTheReturn() async throws {
		let fixture = try await makeFixture()
		let middle = try await hit(for: 150, in: fixture)
		#expect(await fixture.controller.showHistoryWindow(around: middle))

		var live = ChatLine()
		live.messageBody = "arrived while detached"
		live.nickname = "bob"
		live.lineType = .privateMessage
		fixture.controller.print(live)
		await fixture.controller.drainRenderJobs()

		// Stored, and not drawn into a window of old lines.
		#expect(fixture.view.containsLine(identifier: live.uniqueIdentifier) == false)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive)

		fixture.controller.returnToLive()
		await fixture.controller.drainRenderJobs()

		#expect(fixture.controller.historyRecovery.isDetachedFromLive == false)
		#expect(fixture.view.containsLine(identifier: live.uniqueIdentifier))
		#expect(displays(299, in: fixture))
		#expect(displays(150, in: fixture) == false)
		try await finish(fixture)
	}

	@Test("Jump to Present from a window returns to the live end")
	func jumpToPresentReturns() async throws {
		let fixture = try await makeFixture()
		let early = try await hit(for: 20, in: fixture)
		#expect(await fixture.controller.showHistoryWindow(around: early))

		fixture.controller.jumpToPresent()
		await fixture.controller.drainRenderJobs()

		#expect(fixture.controller.historyRecovery.isDetachedFromLive == false)
		#expect(displays(299, in: fixture))
		try await finish(fixture)
	}

	@Test("A line already on screen is scrolled to and no window replaces the view")
	func loadedLineNeedsNoWindow() async throws {
		let fixture = try await makeFixture()
		let target = try await hit(for: 290, in: fixture)

		let shown = await fixture.controller.showHistoryWindow(around: target)

		#expect(shown)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive == false)
		#expect(displays(299, in: fixture))
		try await finish(fixture)
	}

	@Test("A line that has been pruned since the search leaves the view as it was")
	func prunedLineLeavesTheViewAlone() async throws {
		let fixture = try await makeFixture()
		let target = try await hit(for: 5, in: fixture)
		_ = await fixture.history.removeHistory(fixture.identifier, forget: false)

		let shown = await fixture.controller.showHistoryWindow(around: target)

		#expect(shown == false)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive == false)
		#expect(displays(299, in: fixture))
		try await finish(fixture)
	}

	@Test("A hit from another conversation is refused")
	func foreignHitIsRefused() async throws {
		let fixture = try await makeFixture(count: 120)
		var target = try await hit(for: 3, in: fixture)
		target = ScrollbackSearchHit(
			viewIdentifier: "someone-else", lineIdentifier: target.lineIdentifier, sender: target.sender,
			text: target.text, timestamp: target.timestamp, cursor: target.cursor
		)

		#expect(await fixture.controller.showHistoryWindow(around: target) == false)
		#expect(fixture.controller.historyRecovery.isDetachedFromLive == false)
		try await finish(fixture)
	}

	@Test("Leaving the window with nothing detached does nothing")
	func returnWithoutAWindowIsANoOp() async throws {
		let fixture = try await makeFixture(count: 120)
		let before = fixture.view.displayedLines.map(\.lineNumber)

		fixture.controller.returnToLive()
		await fixture.controller.drainRenderJobs()

		#expect(fixture.view.displayedLines.map(\.lineNumber) == before)
		try await finish(fixture)
	}
}
