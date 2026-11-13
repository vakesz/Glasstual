// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Showing a line that is stored but not loaded, and coming back.

 A transcript holds the newest page of history and whatever the reader has
 scrolled up through. A line a search found can be far older, so the view is
 replaced by a window of stored rows around it, and is then *detached from
 live*: lines that arrive are stored and not drawn, and the banner offers the
 way back. Returning clears the window and reads the newest page again, which
 includes everything stored meanwhile; nothing is lost and no queue is kept,
 because the store is the queue. */
extension TranscriptController {
	/// How many stored rows are shown on each side of the line a search found.
	static let historyWindowRadius: UInt = 50

	/** Replaces the transcript with a window of stored history around `hit`,
	 and scrolls to it. A line already on screen is only scrolled to.

	 The answer is whether the line is showing. A hit whose row has since been
	 pruned, or whose page cannot be read, leaves the view as it was. */
	@discardableResult
	func showHistoryWindow(around hit: ScrollbackSearchHit) async -> Bool {
		guard !terminating, let associatedItem, acceptsRenderJobs,
		      hit.viewIdentifier == associatedItem.uniqueIdentifier
		else { return false }
		ensureBackingView()
		if backingView?.jump(to: hit.lineIdentifier) == true {
			return true
		}

		/* A first load still in flight would add the newest page on top of the
		 window; let it finish, and the window replaces it. */
		await settleInitialHistory()
		guard !terminating, let view = backingView else { return false }
		if view.jump(to: hit.lineIdentifier) {
			return true
		}

		let request = ScrollbackFetchRequest(
			viewIdentifier: associatedItem.uniqueIdentifier,
			kind: .window(around: hit.cursor, olderLimit: Self.historyWindowRadius, newerLimit: Self.historyWindowRadius)
		)
		return await showHistoryWindow(request) { $0.cursor == hit.cursor }
	}

	/** Fetches a window of stored rows and shows it, scrolled to the row
	 `isAnchor` picks. Reports whether that row is showing. */
	func showHistoryWindow(
		_ request: ScrollbackFetchRequest,
		anchoredAt isAnchor: (ScrollbackEntry) -> Bool
	) async -> Bool {
		guard let associatedItem else { return false }
		let generation = renderScheduler.generation
		let outcome = await historyPageFetcher(request)
		guard case let .page(entries) = outcome, entries.isEmpty == false else { return false }
		let rows = entries.compactMap { row in ChatLine(entry: row).map { (row: row, line: $0) } }
		guard let anchor = rows.first(where: { isAnchor($0.row) }) else { return false }
		let anchorLineIdentifier = anchor.row.cursor?.lineIdentifier ?? anchor.line.uniqueIdentifier

		let context = makeHistoryRenderContext()
		let snapshots = rows.map { ChatLineSnapshot($0.line, in: context, historyCursor: $0.row.cursor) }
		let results = await Self.renderWindow(snapshots, context: context)
		guard acceptsRenderGeneration(generation), backingView != nil else { return false }

		cancelOlderHistory()
		historyRecovery.beginDetached()
		scrollback.duplicates.indexChatLines(rows.map(\.line), forView: associatedItem.uniqueIdentifier)
		applyReloadedLines(results, isReload: false)
		_ = backingView?.jump(to: anchorLineIdentifier)
		backingView?.updateJumpToLatestVisibility()
		return true
	}

	/** Leaves a window of old history for the live end of the conversation.

	 The view is emptied and the newest page is read from the store as a first
	 load would, ending at the present, so the lines stored while the window
	 was showing come back in their place. */
	func returnToLive() {
		guard historyRecovery.isDetachedFromLive, !terminating else { return }
		historyRecovery.endDetached()
		historyRecovery.clearLoadedHistory()
		cancelOlderHistory()
		markViewLoadedNow()
		backingView?.clearLines()
		reloadHistory()
		backingView?.updateJumpToLatestVisibility()
	}

	/// Waits, a bounded number of turns, for a history read in flight.
	func settleInitialHistory() async {
		var turns = 0
		while historyRecovery.isReloading, turns < 50, !terminating {
			await drainRenderJobs()
			await Task.yield()
			turns += 1
		}
	}

	@concurrent
	private static func renderWindow(
		_ snapshots: [ChatLineSnapshot],
		context: TranscriptRenderContext
	) async -> [TranscriptRenderResult] {
		renderJob(snapshots, context: context)
	}
}
