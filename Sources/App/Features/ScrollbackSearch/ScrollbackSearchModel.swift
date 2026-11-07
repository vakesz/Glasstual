// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** The state of the search window: what is being asked, over what, and what
 came back.

 The model owns the search: every change to the query restarts it after a short
 pause, an older search still running is cancelled, and an answer that arrives
 after a newer question was asked is dropped. Everything outside it is passed in,
 so a test drives it without a store, a chat session or a window. */
@MainActor
@Observable
final class ScrollbackSearchModel {
	enum Phase: Equatable {
		/// Nothing has been asked yet, or the query asks for nothing.
		case idle
		case searching
		case finished
		case failed(String)
	}

	typealias Search = @MainActor @Sendable (ScrollbackSearchQuery) async -> ScrollbackSearchOutcome
	typealias Reveal = @MainActor (ScrollbackSearchHit) async -> Bool

	var text = "" {
		didSet { queryChanged(from: oldValue, to: text) }
	}

	var sender = "" {
		didSet { queryChanged(from: oldValue, to: sender) }
	}

	var scope = ScrollbackSearchScope.all {
		didSet { queryChanged(from: oldValue, to: scope) }
	}

	var restrictsDates = false {
		didSet { queryChanged(from: oldValue, to: restrictsDates) }
	}

	var fromDate = Calendar.current.date(byAdding: .month, value: -1, to: .now) ?? .now {
		didSet { queryChanged(from: oldValue, to: fromDate) }
	}

	var throughDate = Date.now {
		didSet { queryChanged(from: oldValue, to: throughDate) }
	}

	var selection: ScrollbackSearchRow.ID?

	private(set) var phase = Phase.idle
	private(set) var groups: [ScrollbackSearchGroup] = []
	private(set) var resultCount = 0
	private(set) var isTruncated = false
	/// Whether the last row the reader opened could still be shown.
	private(set) var revealFailed = false
	private(set) var targets = ScrollbackSearchTargets.empty

	@ObservationIgnored private let search: Search
	@ObservationIgnored private let snapshotTargets: @MainActor () -> ScrollbackSearchTargets
	@ObservationIgnored private let reveal: Reveal
	@ObservationIgnored private let pause: Duration
	@ObservationIgnored private var pendingSearch: Task<Void, Never>?
	@ObservationIgnored private var generation = 0

	init(
		search: @escaping Search = { await Scrollback.shared.search($0) },
		targets: @escaping @MainActor () -> ScrollbackSearchTargets = { ScrollbackSearchTargets.current() },
		reveal: @escaping Reveal = { await ScrollbackSearchReveal.show($0) },
		pause: Duration = .milliseconds(250)
	) {
		self.search = search
		snapshotTargets = targets
		self.reveal = reveal
		self.pause = pause
		self.targets = targets()
	}

	isolated deinit {
		pendingSearch?.cancel()
	}

	/// Whether a scope has anything to search, so the picker can offer only
	/// those that do.
	func isAvailable(_ scope: ScrollbackSearchScope) -> Bool {
		targets.isAvailable(scope)
	}

	/// Looks at the conversations again, as when the window is shown, and
	/// repeats the search against what is there now.
	func refreshTargets() {
		targets = snapshotTargets()
		if isAvailable(scope) == false {
			scope = .all
		}
		restartSearch()
	}

	/// The query as the store is asked it, or `nil` where it asks for nothing.
	var query: ScrollbackSearchQuery? {
		let query = ScrollbackSearchQuery(
			text: text,
			sender: sender,
			viewIdentifiers: targets.viewIdentifiers(for: scope),
			from: restrictsDates ? Calendar.current.startOfDay(for: fromDate) : nil,
			through: restrictsDates
				? Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: throughDate))
				: nil
		)
		return query.isSearchable ? query : nil
	}

	private func queryChanged<Value: Equatable>(from old: Value, to new: Value) {
		guard old != new else { return }
		restartSearch()
	}

	/// Cancels whatever is running and, after a pause that lets typing settle,
	/// asks again.
	func restartSearch() {
		pendingSearch?.cancel()
		generation += 1
		let current = generation
		revealFailed = false
		guard let query else {
			pendingSearch = nil
			clearResults()
			phase = .idle
			return
		}
		phase = .searching
		let pause = pause
		let search = search
		pendingSearch = Task { [weak self] in
			if pause > .zero {
				try? await Task.sleep(for: pause)
			}
			guard !Task.isCancelled else { return }
			let outcome = await search(query)
			guard let self, !Task.isCancelled, generation == current else { return }
			apply(outcome, for: query)
		}
	}

	/// Waits for the search in flight, for a test that has to see its answer.
	func waitForSearch() async {
		await pendingSearch?.value
	}

	private func apply(_ outcome: ScrollbackSearchOutcome, for _: ScrollbackSearchQuery) {
		switch outcome {
		case let .results(hits, truncated):
			let rows = hits.map { hit in
				let target = targets.target(forView: hit.viewIdentifier)
				return ScrollbackSearchRow(
					hit: hit,
					conversationName: target?.title ?? ApplicationStrings.unknownValue,
					serverName: target?.serverName ?? ""
				)
			}
			groups = ScrollbackSearchGroup.grouping(rows)
			resultCount = rows.count
			isTruncated = truncated
			if let selection, rows.contains(where: { $0.id == selection }) == false {
				self.selection = nil
			}
			phase = .finished
		case .unavailable:
			clearResults()
			phase = .failed(PromptStrings.Logging.scrollbackFailureBody)
		case let .failed(reason):
			clearResults()
			phase = .failed(reason)
		case .cancelled:
			break
		}
	}

	private func clearResults() {
		groups = []
		resultCount = 0
		isTruncated = false
		selection = nil
	}

	/// The text the matches in a row are marked against.
	var markedText: String {
		text
	}

	/// Opens a match in the main window, at its line.
	func open(_ row: ScrollbackSearchRow) async {
		selection = row.id
		revealFailed = await reveal(row.hit) == false
	}

	/// Opens the selected match, as Return does.
	func openSelection() async {
		guard let selection, let row = groups.lazy.flatMap(\.rows).first(where: { $0.id == selection }) else { return }
		await open(row)
	}

	/// Moves the selection through the matches in the order they are listed.
	func moveSelection(by offset: Int) {
		let rows = groups.flatMap(\.rows)
		guard rows.isEmpty == false else { return }
		let current = selection.flatMap { id in rows.firstIndex { $0.id == id } }
		let next = current.map { min(max($0 + offset, 0), rows.count - 1) } ?? (offset >= 0 ? 0 : rows.count - 1)
		selection = rows[next].id
	}
}
