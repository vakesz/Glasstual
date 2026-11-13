// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What the scrollback store knows of each view without asking the database:
 how many rows it holds, the highest entry identifier it has written, and the
 retention pass armed for it. */
nonisolated struct ScrollbackViewCounts {
	struct ScheduledResize {
		let identifier: UUID
		let task: Task<Void, Never>
	}

	private struct ViewState {
		var totalLineCount: UInt
		var maximumIdentifier: UInt
		var resize: ScheduledResize?
	}

	private var views: [String: ViewState] = [:]
	private(set) var maximumLineCount: UInt = 100

	func contains(_ identifier: String) -> Bool {
		views[identifier] != nil
	}

	mutating func insert(_ identifier: String, lineCount: UInt, maximumIdentifier: UInt) {
		views[identifier] = ViewState(totalLineCount: lineCount, maximumIdentifier: maximumIdentifier)
	}

	func maximumIdentifier(of identifier: String) -> UInt? {
		views[identifier]?.maximumIdentifier
	}

	/// A row was written under `entryIdentifier`, the next after the view's highest.
	mutating func noteInserted(_ identifier: String, entryIdentifier: UInt) {
		guard let count = views[identifier]?.totalLineCount else { return }
		views[identifier]?.maximumIdentifier = entryIdentifier
		views[identifier]?.totalLineCount = saturatedAdd(count, 1)
	}

	mutating func subtract(_ count: UInt, from identifier: String) {
		if let total = views[identifier]?.totalLineCount {
			views[identifier]?.totalLineCount = total - min(total, count)
		}
	}

	/** Sets the most rows a view keeps and returns every view, each of which
	 may now need a pass.

	 A pass already waiting was armed for the old limit and may not be due for
	 another half hour. Lowering the limit retires it, which is what lets the
	 new limit arm a pass of its own. */
	mutating func setMaximumLineCount(_ count: UInt) -> [String] {
		guard count > 0 else { return [] }
		let lowered = count < maximumLineCount
		maximumLineCount = count
		if lowered {
			for identifier in views.keys {
				cancelResize(identifier)
			}
		}
		return Array(views.keys)
	}

	/// Whether the view is over the limit with no pass armed.
	func needsResize(_ identifier: String) -> Bool {
		guard let state = views[identifier], state.resize == nil else { return false }
		return state.totalLineCount > maximumLineCount
	}

	mutating func armResize(_ identifier: String, _ resize: ScheduledResize) {
		views[identifier]?.resize = resize
	}

	/// Whether a pass, nil for one asked for directly, is still the view's own.
	func isCurrent(_ requestIdentifier: UUID?, for identifier: String) -> Bool {
		requestIdentifier == nil || requestIdentifier == views[identifier]?.resize?.identifier
	}

	/// A cancelled pass can finish after a replacement is scheduled for the same view.
	mutating func releaseResizeSlot(_ identifier: String, requestIdentifier: UUID?) {
		guard isCurrent(requestIdentifier, for: identifier) else { return }
		if requestIdentifier == nil {
			views[identifier]?.resize?.task.cancel()
		}
		views[identifier]?.resize = nil
	}

	mutating func cancelResize(_ identifier: String) {
		views[identifier]?.resize?.task.cancel()
		views[identifier]?.resize = nil
	}

	mutating func removeView(_ identifier: String) {
		views[identifier]?.resize?.task.cancel()
		views.removeValue(forKey: identifier)
	}

	func cancelAllResizes() {
		for state in views.values {
			state.resize?.task.cancel()
		}
	}

	/// Forgets every armed pass without cancelling it.
	mutating func forgetResizes() {
		for identifier in views.keys {
			views[identifier]?.resize = nil
		}
	}

	mutating func removeAll() {
		views.removeAll()
	}
}

nonisolated func saturatedAdd(_ lhs: UInt, _ rhs: UInt) -> UInt { // nonisolated: pure
	let (result, overflow) = lhs.addingReportingOverflow(rhs)
	return overflow ? UInt.max : result
}
