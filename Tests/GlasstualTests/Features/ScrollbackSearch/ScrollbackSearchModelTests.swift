// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Synchronization
import Testing

/// Records the queries a model asked and answers each from a script.
private final class SearchRecorder: Sendable {
	private let queries = Mutex<[ScrollbackSearchQuery]>([])
	private let outcome: Mutex<ScrollbackSearchOutcome>

	init(_ outcome: ScrollbackSearchOutcome = .results([], truncated: false)) {
		self.outcome = Mutex(outcome)
	}

	var asked: [ScrollbackSearchQuery] {
		queries.withLock { $0 }
	}

	func answer(_ outcome: ScrollbackSearchOutcome) {
		self.outcome.withLock { $0 = outcome }
	}

	func run(_ query: ScrollbackSearchQuery) -> ScrollbackSearchOutcome {
		queries.withLock { $0.append(query) }
		return outcome.withLock { $0 }
	}
}

@MainActor
@Suite("Scrollback search model")
struct ScrollbackSearchModelTests {
	private static let targets = ScrollbackSearchTargets(
		entries: [
			ScrollbackSearchTarget(viewIdentifier: "chan-a", title: "#a", serverIdentifier: "s1", serverName: "Libera"),
			ScrollbackSearchTarget(viewIdentifier: "chan-b", title: "#b", serverIdentifier: "s1", serverName: "Libera"),
			ScrollbackSearchTarget(viewIdentifier: "chan-c", title: "#c", serverIdentifier: "s2", serverName: "OFTC"),
		],
		selectedViewIdentifier: "chan-b",
		selectedServerIdentifier: "s1"
	)

	private func hit(_ view: String, _ text: String, at seconds: TimeInterval, row: Int) -> ScrollbackSearchHit {
		ScrollbackSearchHit(
			viewIdentifier: view, lineIdentifier: "line-\(row)", sender: "alice", text: text, timestamp: seconds,
			cursor: ScrollbackRowCursor(
				timestamp: seconds, insertionIdentifier: Int64(row), lineIdentifier: "line-\(row)", rowURI: "row-\(row)"
			)
		)
	}

	private func model(
		recorder: SearchRecorder,
		targets: ScrollbackSearchTargets = ScrollbackSearchModelTests.targets,
		reveal: @escaping ScrollbackSearchModel.Reveal = { _ in true }
	) -> ScrollbackSearchModel {
		ScrollbackSearchModel(
			search: { recorder.run($0) },
			targets: { targets },
			reveal: reveal,
			pause: .zero
		)
	}

	@Test("Nothing is asked until the query asks for something")
	func emptyQueryAsksNothing() async {
		let recorder = SearchRecorder()
		let model = model(recorder: recorder)

		model.text = "   "
		await model.waitForSearch()

		#expect(recorder.asked.isEmpty)
		#expect(model.phase == .idle)
	}

	@Test("Each scope names the views it covers", arguments: [
		(ScrollbackSearchScope.all, ["chan-a", "chan-b", "chan-c"]),
		(.server, ["chan-a", "chan-b"]),
		(.conversation, ["chan-b"]),
	])
	func scopeResolvesViews(scope: ScrollbackSearchScope, expected: [String]) async throws {
		let recorder = SearchRecorder()
		let model = model(recorder: recorder)

		model.scope = scope
		model.text = "hello"
		await model.waitForSearch()

		#expect(try #require(recorder.asked.last).viewIdentifiers == expected)
	}

	@Test("All conversations is the scope a window opens with")
	func defaultScopeIsAll() {
		#expect(model(recorder: SearchRecorder()).scope == .all)
	}

	@Test("A scope with no selection to be relative to falls back to all")
	func unavailableScopeFallsBack() {
		let none = ScrollbackSearchTargets(entries: Self.targets.entries)
		let recorder = SearchRecorder()
		let model = model(recorder: recorder, targets: none)
		#expect(model.isAvailable(.conversation) == false)
		#expect(model.isAvailable(.server) == false)
		#expect(model.isAvailable(.all))

		model.scope = .server
		model.refreshTargets()

		#expect(model.scope == .all)
	}

	@Test("The date range is sent as whole days, the last one included")
	func dateRangeCoversWholeDays() async throws {
		let recorder = SearchRecorder()
		let model = model(recorder: recorder)
		let calendar = Calendar.current
		let from = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 1, hour: 15)))
		let through = try #require(calendar.date(from: DateComponents(year: 2026, month: 5, day: 8, hour: 9)))

		model.restrictsDates = true
		model.fromDate = from
		model.throughDate = through
		model.text = "x"
		await model.waitForSearch()

		let query = try #require(recorder.asked.last)
		#expect(query.from == calendar.startOfDay(for: from))
		#expect(query.through == calendar.date(from: DateComponents(year: 2026, month: 5, day: 9)))
	}

	@Test("Without the date toggle no dates are sent")
	func noDatesByDefault() async throws {
		let recorder = SearchRecorder()
		let model = model(recorder: recorder)

		model.text = "x"
		await model.waitForSearch()

		let query = try #require(recorder.asked.last)
		#expect(query.from == nil)
		#expect(query.through == nil)
	}

	@Test("A sender alone is a search")
	func senderAloneSearches() async throws {
		let recorder = SearchRecorder()
		let model = model(recorder: recorder)

		model.sender = "bob"
		await model.waitForSearch()

		let query = try #require(recorder.asked.last)
		#expect(query.sender == "bob")
		#expect(query.text.isEmpty)
	}

	@Test("Matches are grouped by conversation, the newest conversation first, with names resolved")
	func resultsAreGrouped() async {
		let recorder = SearchRecorder(.results([
			hit("chan-c", "newest", at: 300, row: 3),
			hit("chan-a", "middle", at: 200, row: 2),
			hit("chan-c", "older", at: 150, row: 1),
			hit("gone", "orphan", at: 100, row: 0),
		], truncated: true))
		let model = model(recorder: recorder)

		model.text = "x"
		await model.waitForSearch()

		#expect(model.phase == .finished)
		#expect(model.resultCount == 4)
		#expect(model.isTruncated)
		#expect(model.groups.map(\.viewIdentifier) == ["chan-c", "chan-a", "gone"])
		#expect(model.groups.first?.rows.map(\.hit.text) == ["newest", "older"])
		#expect(model.groups.first?.conversationName == "#c")
		#expect(model.groups.first?.serverName == "OFTC")
		#expect(model.groups.last?.serverName == "")
	}

	@Test("A failure is reported and clears the old results")
	func failureIsShown() async {
		let recorder = SearchRecorder(.results([hit("chan-a", "one", at: 1, row: 1)], truncated: false))
		let model = model(recorder: recorder)
		model.text = "x"
		await model.waitForSearch()
		#expect(model.groups.count == 1)

		recorder.answer(.failed("disk on fire"))
		model.text = "xy"
		await model.waitForSearch()

		#expect(model.phase == .failed("disk on fire"))
		#expect(model.groups.isEmpty)
		#expect(model.resultCount == 0)
	}

	@Test("An answer to an older question never replaces the newer one")
	func staleAnswersAreDropped() async {
		let gate = AsyncGate()
		let answers = Mutex<[String: ScrollbackSearchOutcome]>([
			"first": .results([hit("chan-a", "stale", at: 1, row: 1)], truncated: false),
			"second": .results([hit("chan-a", "fresh", at: 2, row: 2)], truncated: false),
		])
		let model = ScrollbackSearchModel(
			search: { query in
				if query.text == "first" {
					await gate.wait()
				}
				return answers.withLock { $0[query.text] } ?? .results([], truncated: false)
			},
			targets: { Self.targets },
			reveal: { _ in true },
			pause: .zero
		)

		model.text = "first"
		await Task.yield()
		model.text = "second"
		await model.waitForSearch()
		await gate.open()
		await Task.yield()

		#expect(model.groups.first?.rows.map(\.hit.text) == ["fresh"])
	}

	@Test("Opening a match reveals it, and says when its line is gone")
	func openingReportsTheOutcome() async throws {
		let shown = Mutex<[String]>([])
		let succeed = Mutex(true)
		let recorder = SearchRecorder(.results([hit("chan-a", "one", at: 1, row: 1)], truncated: false))
		let model = model(recorder: recorder, reveal: { hit in
			shown.withLock { $0.append(hit.id) }
			return succeed.withLock { $0 }
		})
		model.text = "x"
		await model.waitForSearch()
		let row = try #require(model.groups.first?.rows.first)

		await model.open(row)
		#expect(shown.withLock { $0 } == ["row-1"])
		#expect(model.selection == row.id)
		#expect(model.revealFailed == false)

		succeed.withLock { $0 = false }
		await model.open(row)
		#expect(model.revealFailed)
	}

	@Test("The selection moves through the matches in listed order and stops at the ends")
	func selectionMoves() async {
		let recorder = SearchRecorder(.results([
			hit("chan-a", "one", at: 3, row: 3),
			hit("chan-b", "two", at: 2, row: 2),
			hit("chan-a", "three", at: 1, row: 1),
		], truncated: false))
		let model = model(recorder: recorder)
		model.text = "x"
		await model.waitForSearch()
		let listed = model.groups.flatMap(\.rows).map(\.id)

		model.moveSelection(by: 1)
		#expect(model.selection == listed.first)
		model.moveSelection(by: 1)
		model.moveSelection(by: 1)
		model.moveSelection(by: 1)
		#expect(model.selection == listed.last)
		model.moveSelection(by: -10)
		#expect(model.selection == listed.first)
	}
}

/// Holds a caller until the test lets it go.
private actor AsyncGate {
	private var opened = false
	private var waiting: [CheckedContinuation<Void, Never>] = []

	func wait() async {
		guard !opened else { return }
		await withCheckedContinuation { waiting.append($0) }
	}

	func open() {
		opened = true
		waiting.forEach { $0.resume() }
		waiting.removeAll()
	}
}
