// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

/** One page of local scrollback the transcript pulls in. Shared so the initial
 replay and the older-page fetch cannot drift apart. */
nonisolated enum HistoryFetch {
	static let pageSize: UInt = 100
}

/** Everything that puts older lines into a transcript: the initial replay from
 local storage, the scrollback pages the reader pulls in, and the server-history
 handshake behind them. The controller's own file owns live printing and the
 view's life cycle; the state the two halves share is declared there. */
extension TranscriptController {
	func maybeReloadHistory() {
		guard viewIsLoaded, !historyRecovery.isLoaded, !historyRecovery.isReloading else {
			return
		}
		reloadHistory()
	}

	func reloadHistory() {
		guard !terminating, !historyRecovery.isReloading else {
			return
		}
		let firstLoad = !historyRecovery.hasEverLoaded
		let conversation = associatedConversation
		let includeStoredHistory = HistoryLoadPolicy(
			firstLoad: firstLoad,
			reloadsScrollbackOnLaunch: reloadsScrollbackOnLaunch(),
			isConsole: conversation?.isConsole == true,
			isDirectChat: conversation?.isDirectChat == true,
			isDirect: conversation?.isDirect == true,
			remembersDirectConversations: SettingsKeys.Appearance.rememberDirectConversations.value
		).includesStoredHistory
		if loadsHistoryLazily(), !viewIsVisible {
			return
		}

		/* The latch closes only for a fetch that reached the pipeline. Nothing
		 else reopens it: a view that latched on a job it never submitted would
		 refuse every later reload and park its deferred prepends for good. */
		if fetchHistory(firstLoad: firstLoad, includeStoredHistory: includeStoredHistory) {
			historyRecovery.beginReload()
		}
	}
}

private extension TranscriptController {
	/// Submits the initial history read, and reports whether it was submitted.
	/// A view with nothing to attribute the lines to, or no pipeline left to
	/// render them, enqueues nothing and starts no replay.
	func fetchHistory(firstLoad: Bool, includeStoredHistory: Bool) -> Bool {
		guard let associatedItem, acceptsRenderJobs else {
			return false
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let replayedResults = transcriptProjection.beginReplay(displaying: backingView?.displayedLines ?? [])
		let context = makeHistoryRenderContext()
		let generation = renderScheduler.generation
		let fetch = historyPageFetcher
		let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
		let request = ScrollbackFetchRequest(
			viewIdentifier: viewIdentifier,
			kind: .rowPage(before: nil, fetchLimit: HistoryFetch.pageSize, limitToDate: limitDate)
		)
		/* Everything the render needs is a value, so the fetch is awaited inside
		 the job rather than before it. The job is standalone, so later prints do
		 not queue behind the fetch; the projection's replay buffer is what holds
		 them until the history has been applied. */
		return enqueueRenderJob(isStandalone: true) { [weak self] in
			let outcome = includeStoredHistory ? await fetch(request) : .page([])
			guard let viewController = self, !Task.isCancelled,
			      await viewController.acceptsRenderGeneration(generation) else { return nil }
			let fetched = TranscriptHistoryMerge.fetched(outcome)
			let rows = Array(fetched.entries.reversed())
			let decoded = ScrollbackSession.decode(rows)
			let scrollbackLines = decoded.lines
			let renderedReplay = Dictionary(uniqueKeysWithValues: replayedResults.map { ($0.lineNumber, $0) })
			let chatLines = rows.compactMap { row in ChatLine(entry: row).map { (row, $0) } }
			let assignment = TranscriptHistoryMerge.assign(
				identifiers: chatLines.map(\.1.uniqueIdentifier),
				replayedLineNumbers: Set(renderedReplay.keys)
			)
			var slots: [TranscriptRenderResult?] = []
			var freshSnapshots: [ChatLineSnapshot] = []
			var freshSlots: [Int] = []
			for ((row, line), slot) in zip(chatLines, assignment.slots) {
				if case let .replayed(lineNumber) = slot, var replayed = renderedReplay[lineNumber] {
					replayed.transcriptLine.historyCursor = row.cursor
					slots.append(replayed)
				} else {
					freshSlots.append(slots.count)
					freshSnapshots.append(ChatLineSnapshot(line, in: context, historyCursor: row.cursor))
					slots.append(nil)
				}
			}
			if freshSnapshots.isEmpty == false {
				for (slot, rendered) in zip(freshSlots, Self.renderJob(freshSnapshots, context: context)) {
					slots[slot] = rendered
				}
			}
			var results = slots.compactMap(\.self)
			results += replayedResults.filter { !assignment.consumed.contains($0.lineNumber) }
			return TranscriptHistoryRenderOutput(
				scrollbackLines: scrollbackLines,
				results: results,
				fetchSucceeded: fetched.succeeded && decoded.isWholePage,
				failure: decoded.isWholePage ? fetched.failure : .invalidEntry
			)
		} apply: { [weak self] (loaded: TranscriptHistoryRenderOutput) in
			self?.applyReloadedHistory(
				loaded.scrollbackLines,
				results: loaded.results,
				forView: viewIdentifier,
				firstLoad: firstLoad,
				fetchSucceeded: loaded.fetchSucceeded,
				failure: loaded.failure
			)
		}
	}

	private func applyReloadedHistory(
		_ scrollbackLines: [ChatLine],
		results inputResults: [TranscriptRenderResult],
		forView viewIdentifier: String,
		firstLoad: Bool,
		fetchSucceeded: Bool,
		failure: ScrollbackFetchFailure?
	) {
		historyRecovery.initialFailure = failure
		var results = inputResults
		scrollback.duplicates.indexChatLines(scrollbackLines, forView: viewIdentifier)
		/* Only where nothing has been printed this session: every line this
		 process prints sets it, so anything newer than the stored page is
		 already there. */
		if lastLineStorage == nil {
			lastLineStorage = scrollbackLines.last
		}
		if firstLoad {
			let markerLineNumber = transcriptSessionBoundary.prepareInitialHistory(
				scrollbackLines,
				renderedLines: results
			)
			newestLineNumberFromPreviousSession = transcriptSessionBoundary
				.newestPreviousSessionLineNumber
			if let markerLineNumber,
			   let markerIndex = results.firstIndex(where: { $0.lineNumber == markerLineNumber })
			{
				results[markerIndex].transcriptLine.markers.insert(
					.currentSession(String(localized: .Transcript.currentSession)),
					at: 0
				)
			}
		}
		enqueueReloadedLines(Array(results.suffix(bufferPolicy.hardLimit)), isReload: !firstLoad) { [weak self] in
			self?.continueHistoryReplay(fetchSucceeded: fetchSucceeded)
		}
	}

	private func enqueueReloadedLines(
		_ results: [TranscriptRenderResult],
		isReload: Bool,
		completion: @escaping @MainActor () -> Void
	) {
		let generation = renderScheduler.generation
		var applications: [@MainActor () -> Void] = []
		for start in stride(from: 0, to: results.count, by: 32) {
			let chunk = Array(results[start ..< min(start + 32, results.count)])
			applications.append { [weak self] in
				guard let self, acceptsRenderGeneration(generation) else { return }
				applyReloadedLines(chunk, isReload: isReload || start > 0)
			}
		}
		applications.append { [weak self] in
			guard let self, acceptsRenderGeneration(generation) else { return }
			completion()
		}
		renderScheduler.prioritize(applications)
	}

	private func continueHistoryReplay(fetchSucceeded: Bool) {
		let displayed = Set(backingView?.displayedLines
			.flatMap { [$0.lineNumber, $0.historyCursor?.lineIdentifier].compactMap(\.self) } ?? [])
		var pending = transcriptProjection.takePendingResults(displaying: displayed)
		if let pendingIndex = pending.firstIndex(where: { transcriptSessionBoundary.consumePendingMarker(for: $0) }) {
			pending[pendingIndex].transcriptLine.markers.insert(
				.currentSession(String(localized: .Transcript.currentSession)),
				at: 0
			)
		}
		if !pending.isEmpty {
			enqueueReloadedLines(pending, isReload: true) { [weak self] in
				self?.continueHistoryReplay(fetchSucceeded: fetchSucceeded)
			}
			return
		}
		_ = transcriptProjection.finishReplay(displaying: displayed)
		restoreTranscriptProjectionState()
		historyRecovery.finishReload(succeeded: fetchSucceeded)
		if viewIsVisible, let associatedItem {
			attachedWindow?.noteItemWasViewed(associatedItem)
		}
		renderScheduler.releaseHeldApplications()
		reloadForRecoveredLinesIfNeeded()
	}

	private func restoreTranscriptProjectionState() {
		for update in Array(transcriptProjection.deliveryUpdates.values) {
			applyDeliveryUpdate(update)
		}
		forgetRetiredProjectionMessages()
		for (identifier, merged) in reactions.all {
			backingView?.updateReactions(merged, messageIdentifier: identifier.rawValue)
		}
		restoreRedactions()
		switch transcriptProjection.mark {
		case .none:
			break
		case .latest:
			backingView?.setUnreadMarker(.latest)
		case let .line(identifier):
			backingView?.setUnreadMarker(.line(identifier))
		case let .after(date):
			backingView?.setUnreadMarker(.after(date))
		}
	}
}

extension TranscriptController {
	func retryHistory() {
		guard !historyRecovery.isRetrying else { return }
		if terminating {
			retryStorageOnly()
			return
		}
		guard !historyRecovery.isReloading else { return }
		let generation = renderScheduler.generation
		let storage = scrollback
		/* The banner outlives the controller, so the recovery state is held
		 strongly and cleared on every exit: a retry whose controller died
		 mid-flight otherwise left the spinner turning for good. */
		let recovery = historyRecovery
		recovery.isRetrying = true
		historyRetryTask = Task { @MainActor [weak self] in
			defer { recovery.isRetrying = false }
			let available = await storage.retryLoading()
			guard let self, !Task.isCancelled, acceptsRenderGeneration(generation) else { return }
			if available {
				if !historyRecovery.isLoaded {
					reloadHistory()
				} else if historyRecovery.olderFailure != nil {
					locallyExhaustedBefore = nil
					loadOlderHistory()
				}
				await drainRenderJobs()
			} else if historyRecovery.initialFailure == nil {
				historyRecovery.initialFailure = .unavailable
			}
		}
	}

	/** The repair a retired view can still make.

	 Its transcript is gone, so reopening the store is the whole of it — and it
	 is the repair whichever message the banner is showing asks for, whether the
	 failure was recorded against this view or against the store itself.
	 Succeeding retires this view's own failures with it: nothing is going to
	 read history into a transcript that no longer exists. */
	private func retryStorageOnly() {
		guard historyRecovery.localMessage != nil || storageRecovery.localMessage != nil else { return }
		historyRecovery.isRetrying = true
		/* The banner outlives the controller, so the state is held strongly:
		 whoever is still watching it has to see the spinner stop. */
		let state = historyRecovery
		let storage = scrollback
		historyRetryTask = Task { @MainActor [weak self] in
			let available = await storage.retryLoading()
			if available, let self {
				historyRecovery.initialFailure = nil
				historyRecovery.olderFailure = nil
			}
			state.isRetrying = false
		}
	}
}
