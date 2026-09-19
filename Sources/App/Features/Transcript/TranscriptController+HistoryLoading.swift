// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

/** Everything that puts older lines into a transcript: the initial replay from
 local storage, the scrollback pages the reader pulls in, and the server-history
 handshake behind them. The controller's own file owns live printing and the
 view's life cycle; the state the two halves share is declared there. */
extension TranscriptController {
	func maybeReloadHistory() {
		guard viewIsLoaded, !historyLoaded, !reloadingHistory else {
			return
		}
		reloadHistory()
	}

	func reloadHistory() {
		guard !terminating, !reloadingHistory else {
			return
		}
		let firstLoad = !historyLoadedForFirstTime
		let conversation = associatedConversation
		let includeStoredHistory = !(firstLoad && !SettingsKeys.Logging.reloadScrollbackOnLaunch.value ||
			conversation?.isConsole == true ||
			conversation?.isDirectChat == true ||
			(firstLoad && conversation?.isDirect == true && !SettingsKeys.Appearance.rememberDirectConversations.value))
		if loadsHistoryLazily(), !viewIsVisible {
			return
		}

		/* The latch closes only for a fetch that reached the pipeline. Nothing
		 else reopens it: a view that latched on a job it never submitted would
		 refuse every later reload and park its deferred prepends for good. */
		reloadingHistory = fetchHistory(firstLoad: firstLoad, includeStoredHistory: includeStoredHistory)
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
		let replayedResults = transcriptProjection.beginReplay()
		let context = makeHistoryRenderContext()
		let generation = renderGeneration
		let fetch = historyPageFetcher
		let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
		let request = ScrollbackFetchRequest(
			viewIdentifier: viewIdentifier,
			kind: .rowPage(before: nil, fetchLimit: 100, limitToDate: limitDate)
		)
		/* Everything the render needs is a value, so the fetch is awaited inside
		 the job rather than before it. The job is standalone, so later prints do
		 not queue behind the fetch; the projection's replay buffer is what holds
		 them until the history has been applied. */
		return enqueueRenderJob(isStandalone: true) { [weak self] in
			let outcome = includeStoredHistory ? await fetch(request) : .page([])
			guard let viewController = self, !Task.isCancelled,
			      await viewController.acceptsRenderGeneration(generation) else { return nil }
			let storedEntries: [ScrollbackEntry]
			let failure: ScrollbackFetchFailure?
			let fetchSucceeded: Bool
			switch outcome {
			case let .page(entries):
				storedEntries = entries
				failure = nil
				fetchSucceeded = true
			case let .failed(reason):
				storedEntries = []
				failure = reason
				fetchSucceeded = false
			case .cancelled:
				storedEntries = []
				failure = nil
				fetchSucceeded = false
			}
			let rows = Array(storedEntries.reversed())
			let decoded = ScrollbackSession.decode(rows)
			let scrollbackLines = decoded.lines
			let renderedReplay = Dictionary(uniqueKeysWithValues: replayedResults.map { ($0.lineNumber, $0) })
			var consumedReplay = Set<String>()
			var slots: [TranscriptRenderResult?] = []
			var freshSnapshots: [ChatLineSnapshot] = []
			var freshSlots: [Int] = []
			for row in rows {
				guard let line = ChatLine(entry: row) else { continue }
				if var replayed = renderedReplay[line.uniqueIdentifier],
				   consumedReplay.insert(line.uniqueIdentifier).inserted
				{
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
			results += replayedResults.filter { !consumedReplay.contains($0.lineNumber) }
			return TranscriptHistoryRenderOutput(
				scrollbackLines: scrollbackLines,
				results: results,
				fetchSucceeded: fetchSucceeded && decoded.isWholePage,
				failure: decoded.isWholePage ? failure : .invalidEntry
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
		historyLoadFailure = failure
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
		let generation = renderGeneration
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
		pendingApplications.insert(contentsOf: applications, at: 0)
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
		reloadingHistory = false
		historyLoaded = fetchSucceeded
		historyLoadedForFirstTime = historyLoadedForFirstTime || fetchSucceeded
		if viewIsVisible, let associatedItem {
			attachedWindow?.noteItemWasViewed(associatedItem)
		}
		pendingApplications.insert(contentsOf: deferredPrepends, at: 0)
		deferredPrepends.removeAll()
	}

	private func restoreTranscriptProjectionState() {
		for update in transcriptProjection.deliveryUpdates.values {
			backingView?.updateDelivery(update)
		}
		for (identifier, merged) in reactions.all {
			backingView?.updateReactions(merged, messageIdentifier: identifier)
		}
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
		guard !reloadingHistory else { return }
		let generation = renderGeneration
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
				if !historyLoaded {
					reloadHistory()
				} else if olderHistoryFailure != nil {
					locallyExhaustedBefore = nil
					loadOlderHistory()
				}
				await drainRenderJobs()
			} else if historyLoadFailure == nil {
				historyLoadFailure = .unavailable
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
				historyLoadFailure = nil
				olderHistoryFailure = nil
			}
			state.isRetrying = false
		}
	}
}

extension TranscriptController {
	func loadOlderHistory() {
		guard !terminating, !reloadingHistory, !loadingOlderHistory, serverHistory.request == nil,
		      let associatedItem,
		      let backingView, backingView.displayedBounds.remainingCapacity > 0,
		      let oldestDisplayedLineNumber = oldestLineNumber
		else { return }
		if locallyExhaustedBefore == oldestDisplayedLineNumber {
			noteLocalScrollbackExhausted()
			return
		}
		loadingOlderHistory = true
		olderHistoryFailure = nil
		let generation = renderGeneration
		let fetch = historyPageFetcher
		let viewIdentifier = associatedItem.uniqueIdentifier
		let kind: ScrollbackFetchRequest.Kind
		let limit = UInt(min(100, backingView.displayedBounds.remainingCapacity))
		if let cursor = backingView.displayedLines.first?.historyCursor {
			kind = .rowPage(before: cursor, fetchLimit: limit, limitToDate: nil)
		} else {
			kind = .before(uniqueIdentifier: oldestDisplayedLineNumber, fetchLimit: limit, limitToDate: nil)
		}
		let request = ScrollbackFetchRequest(
			viewIdentifier: viewIdentifier,
			kind: kind
		)
		olderHistoryTask = Task { @MainActor [weak self] in
			let outcome = await fetch(request)
			guard let self, !Task.isCancelled, acceptsRenderGeneration(generation) else { return }
			guard oldestLineNumber == oldestDisplayedLineNumber else {
				loadingOlderHistory = false
				return
			}
			let storedEntries: [ScrollbackEntry]
			switch outcome {
			case let .page(entries): storedEntries = entries
			case let .failed(failure):
				loadingOlderHistory = false
				olderHistoryFailure = failure
				return
			case .cancelled:
				loadingOlderHistory = false
				return
			}
			let ordered: [ScrollbackEntry] = if case .rowPage = request.kind {
				Array(storedEntries.reversed())
			} else {
				storedEntries
			}
			let decoded = ScrollbackSession.decode(ordered)
			guard decoded.isWholePage else {
				loadingOlderHistory = false
				olderHistoryFailure = .invalidEntry
				return
			}
			let entries = decoded.lines
			guard entries.isEmpty == false else {
				loadingOlderHistory = false
				locallyExhaustedBefore = oldestDisplayedLineNumber
				noteLocalScrollbackExhausted()
				return
			}
			prependEarlierChatLines(entries, before: oldestDisplayedLineNumber, cursors: ordered.map(\.cursor))
		}
	}

	private func noteLocalScrollbackExhausted() {
		guard let conversation = associatedConversation,
		      let session = associatedSession,
		      session.chatHistoryIsAvailable(for: conversation),
		      let oldestDate = backingView?.displayedLines.first?.receivedAt,
		      serverHistory.canAsk(before: oldestDate)
		else {
			return
		}
		let request = ServerHistoryRequest(id: UUID(), before: oldestDate, oldestLineNumber: oldestLineNumber)
		serverHistory.request = request
		if session.requestServerHistory(request, in: conversation, presentation: self) {
			serverHistory.noteAdmitted()
		} else {
			serverHistory.retire()
		}
	}

	func receiveServerHistory(_ outcome: ServerHistoryOutcome, for request: ServerHistoryRequest) {
		guard !terminating, serverHistory.isCurrent(request) else { return }
		guard oldestLineNumber == request.oldestLineNumber,
		      backingView?.displayedLines.first?.receivedAt == request.before
		else {
			serverHistory.retire()
			return
		}
		switch outcome {
		case let .page(lines, extent):
			serverHistory.noteAdmitted()
			guard !lines.isEmpty else {
				serverHistory.retire()
				serverHistory.noteAnswered(before: request.before, extent: extent, oldestCursor: request.before)
				return
			}
			prependEarlierChatLines(
				lines,
				before: request.oldestLineNumber,
				archivesForStorage: true
			) { [weak self] accepted, entries in
				guard let self, serverHistory.isCurrent(request) else { return }
				serverHistory.retire(forgettingAnsweredCursor: true)
				guard !accepted.isEmpty else { return }
				let acceptedIdentifiers = Set(accepted)
				for (line, entry) in zip(lines, entries) where acceptedIdentifiers.contains(line.uniqueIdentifier) {
					scrollback.writeNewEntry(entry, for: line)
				}
				// The local store was already exhausted before this older server page.
				locallyExhaustedBefore = oldestLineNumber
				if accepted.count == Set(lines.map(\.uniqueIdentifier)).count {
					serverHistory.noteAnswered(
						before: request.before,
						extent: extent,
						oldestCursor: backingView?.displayedLines.first?.receivedAt
					)
				}
			}
		case let .failed(reason):
			serverHistory.noteFailed(reason: reason)
		case .cancelled:
			serverHistory.retire(forgettingAnsweredCursor: true)
		}
	}

	/** Whether Retry Server History has anything left to ask for.

	 A request already in flight is one answer; the other belongs to the session,
	 which retires the connection's server-history slot when an unlabeled request
	 times out, so the button is offered only while the session would act on it. */
	var serverHistoryRetryIsAvailable: Bool {
		guard !terminating, serverHistory.request == nil,
		      let session = associatedSession, let conversation = associatedConversation
		else { return false }
		return session.canRetryServerHistory(for: conversation)
	}

	/// Copies the answer into the observable recovery state the banner draws
	/// from, since none of the inputs above are observable themselves.
	func refreshServerRetryAvailability() {
		historyRecovery.serverRetryIsAvailable = serverHistoryRetryIsAvailable
	}

	func retryServerHistory() {
		guard serverHistoryRetryIsAvailable else { return }
		serverHistory.forgetAnsweredCursors()
		noteLocalScrollbackExhausted()
	}

	func prependEarlierChatLines(_ chatLines: [ChatLine]) {
		prependEarlierChatLines(chatLines, before: nil)
	}

	/** Renders older lines and puts them above what the view shows.

	 `archivesForStorage` is for lines the store does not have yet, a server
	 page: they are archived beside the render, off the main actor, and handed
	 to `completion` with the identifiers the view accepted. */
	private func prependEarlierChatLines(
		_ chatLines: [ChatLine], before expectedOldest: String?, cursors: [ScrollbackRowCursor?] = [],
		archivesForStorage: Bool = false,
		completion: (@MainActor (_ accepted: [String], _ entries: [ScrollbackEntry]) -> Void)? = nil
	) {
		guard !terminating, !chatLines.isEmpty, let associatedItem else {
			completion?([], [])
			return
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let context = makeHistoryRenderContext()
		let lines = chatLines.enumerated().map {
			ChatLineSnapshot(
				$0.element,
				in: context,
				historyCursor: cursors.indices.contains($0.offset) ? cursors[$0.offset] : nil
			)
		}
		let snapshots = lines
		enqueueRenderJob {
			(
				results: Self.renderJob(snapshots, context: context),
				entries: archivesForStorage ? chatLines.map { $0.scrollbackEntry(forView: viewIdentifier) } : []
			)
		} apply: { [weak self] (rendered: (results: [TranscriptRenderResult], entries: [ScrollbackEntry])) in
			guard let self else { return }
			let generation = renderGeneration
			let apply: @MainActor () -> Void = { [weak self] in
				guard let self, acceptsRenderGeneration(generation) else { return }
				let accepted = applyPrependedLines(
					chatLines,
					results: rendered.results,
					before: expectedOldest,
					forView: viewIdentifier
				)
				completion?(accepted, rendered.entries)
			}
			if reloadingHistory {
				deferredPrepends.append(apply)
			} else {
				apply()
			}
		}
	}

	/** The render context for lines that come back from history.

	 The same as a live line's, except that none of them fetches its inline
	 images on its own: every relaunch replays the stored page, and a preview
	 fetched for it asks the linked host again for a message the reader saw
	 days ago. */
	func makeHistoryRenderContext() -> TranscriptRenderContext {
		var context = makeRenderContext(includingMembers: true)
		context.inlineMediaEnabled = false
		return context
	}

	private func applyPrependedLines(
		_ chatLines: [ChatLine], results: [TranscriptRenderResult], before expectedOldest: String?,
		forView viewIdentifier: String
	) -> [String] {
		if expectedOldest != nil {
			loadingOlderHistory = false
		}
		guard expectedOldest == nil || oldestLineNumber == expectedOldest else { return [] }
		let accepted = Set(backingView?.prependLines(results.map { applyingCurrentState(to: $0.transcriptLine) }) ?? [])
		scrollback.duplicates.indexChatLines(
			zip(chatLines, results).filter { accepted.contains($0.1.lineNumber) }.map(\.0), forView: viewIdentifier
		)
		for result in results where accepted.contains(result.lineNumber) && result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: result.lineNumber)
		}
		return results.map(\.lineNumber).filter { accepted.contains($0) }
	}
}
