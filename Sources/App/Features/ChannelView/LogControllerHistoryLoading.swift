/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit
import CocoaExtensions
import Foundation
import GlasstualPluginKit

/** Everything that puts older lines into a transcript: the initial replay from
 local storage, the scrollback pages the reader pulls in, and the server-history
 handshake behind them. The controller's own file owns live printing and the
 view's life cycle; the state the two halves share is declared there. */
extension LogController {
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
		let channel = associatedChannel
		let includeStoredHistory = !(firstLoad && !Preferences.Logging.reloadScrollbackOnLaunch.value ||
			channel?.isUtility == true ||
			channel?.isDirectChat == true ||
			(firstLoad && channel?.isPrivateMessage == true && !Preferences.Appearance.rememberQueryStates.value))
		if Preferences.Logging.loadHistoryLazily.value, !viewIsVisible {
			return
		}

		/* The latch closes only for a fetch that reached the pipeline. Nothing
		 else reopens it: a view that latched on a job it never submitted would
		 refuse every later reload and park its deferred prepends for good. */
		reloadingHistory = fetchHistory(firstLoad: firstLoad, includeStoredHistory: includeStoredHistory)
	}
}

private extension LogController {
	/// Submits the initial history read, and reports whether it was submitted.
	/// A view with nothing to attribute the lines to, or no pipeline left to
	/// render them, enqueues nothing and starts no replay.
	func fetchHistory(firstLoad: Bool, includeStoredHistory: Bool) -> Bool {
		guard let associatedItem, acceptsRenderJobs else {
			return false
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let replay = transcriptProjection.beginReplay()
		let context = makeRenderContext()
		let generation = renderGeneration
		let fetch = historyPageFetcher
		let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
		let request = HistoricLogFetchRequest(
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
			let xpcEntries: [HistoricLogEntry]
			let failure: HistoricLogFetchFailure?
			let fetchSucceeded: Bool
			switch outcome {
			case let .page(entries):
				xpcEntries = entries
				failure = nil
				fetchSucceeded = true
			case let .failed(reason):
				xpcEntries = []
				failure = reason
				fetchSucceeded = false
			case .cancelled:
				xpcEntries = []
				failure = nil
				fetchSucceeded = false
			}
			let rows = Array(xpcEntries.reversed())
			let historicEntries = HistoricLogClient.logLines(from: rows)
			let entries = historicEntries + replay.lines
			let renderedReplay = Dictionary(uniqueKeysWithValues: replay.results.map { ($0.lineNumber, $0) })
			var consumedReplay = Set<String>()
			var slots: [LogLineRenderResult?] = []
			var freshSnapshots: [LogLineSnapshot] = []
			var freshSlots: [Int] = []
			for row in rows {
				guard let line = LogLine.logLine(from: row) else { continue }
				if var replayed = renderedReplay[line.uniqueIdentifier],
				   consumedReplay.insert(line.uniqueIdentifier).inserted
				{
					replayed.transcriptLine.historyCursor = row.cursor
					slots.append(replayed)
				} else {
					freshSlots.append(slots.count)
					freshSnapshots.append(LogLineSnapshot(line, in: context, historyCursor: row.cursor))
					slots.append(nil)
				}
			}
			/* A plugin that rewrites a message before it is drawn is a main-actor
			 callback, so the pass that runs them is taken there, once for the
			 page. Turning the text into runs stays here, off the main actor. */
			if freshSnapshots.isEmpty == false {
				let prepared = await MainActor.run {
					LogController.applyingMessageRenderers(to: freshSnapshots, for: viewController)
				}
				for (slot, rendered) in zip(freshSlots, Self.renderJob(prepared, context: context)) {
					slots[slot] = rendered
				}
			}
			var results = slots.compactMap(\.self)
			results += replay.results.filter { !consumedReplay.contains($0.lineNumber) }
			return TranscriptHistoryRenderOutput(
				historicEntries: historicEntries,
				entries: entries,
				results: results,
				fetchSucceeded: fetchSucceeded && historicEntries.count == xpcEntries.count,
				failure: historicEntries.count == xpcEntries.count ? failure : .invalidEntry
			)
		} apply: { [weak self] (loaded: TranscriptHistoryRenderOutput) in
			self?.applyReloadedHistory(
				loaded.historicEntries,
				loaded.entries,
				results: loaded.results,
				forView: viewIdentifier,
				firstLoad: firstLoad,
				replayedLineNumbers: replay.lineNumbers,
				fetchSucceeded: loaded.fetchSucceeded,
				failure: loaded.failure
			)
		}
	}

	private func applyReloadedHistory(
		_ historicEntries: [LogLine],
		_ entries: [LogLine],
		results inputResults: [LogLineRenderResult],
		forView viewIdentifier: String,
		firstLoad: Bool,
		replayedLineNumbers: Set<String>,
		fetchSucceeded: Bool,
		failure: HistoricLogFetchFailure?
	) {
		historyLoadFailure = failure
		var results = inputResults
		historicLog.indexLogLines(historicEntries, forView: viewIdentifier)
		if lastLineStorage == nil {
			lastLineStorage = entries.last
		}
		if firstLoad {
			let markerLineNumber = transcriptSessionBoundary.prepareInitialHistory(
				historicEntries,
				renderedLines: results
			)
			newestLineNumberFromPreviousSession = transcriptSessionBoundary
				.newestPreviousSessionLineNumber
			if let markerLineNumber,
			   let markerIndex = results.firstIndex(where: { $0.lineNumber == markerLineNumber })
			{
				results[markerIndex].transcriptLine.markers.insert(
					.currentSession(MainWindowStrings.Conversation.currentSession),
					at: 0
				)
			}
		}
		enqueueReloadedLines(
			Array(results.suffix(bufferPolicy.hardLimit)),
			isReload: !firstLoad,
			suppressingPluginMessages: replayedLineNumbers.union(transcriptProjection.pendingLineNumbers)
		) { [weak self] in
			self?.continueHistoryReplay(fetchSucceeded: fetchSucceeded)
		}
	}

	private func enqueueReloadedLines(
		_ results: [LogLineRenderResult],
		isReload: Bool,
		suppressingPluginMessages suppressed: Set<String>,
		completion: @escaping @MainActor () -> Void
	) {
		let generation = renderGeneration
		var applications: [@MainActor () -> Void] = []
		for start in stride(from: 0, to: results.count, by: 32) {
			let chunk = Array(results[start ..< min(start + 32, results.count)])
			applications.append { [weak self] in
				guard let self, acceptsRenderGeneration(generation) else { return }
				applyReloadedLines(chunk, isReload: isReload || start > 0, suppressingPluginMessages: suppressed)
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
				.currentSession(MainWindowStrings.Conversation.currentSession),
				at: 0
			)
		}
		if !pending.isEmpty {
			enqueueReloadedLines(pending, isReload: true,
			                     suppressingPluginMessages: Set(pending.map(\.lineNumber)))
			{ [weak self] in
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
		for (identifier, reactions) in reactionsByMessageIdentifier {
			backingView?.updateReactions(reactions, messageIdentifier: identifier)
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

extension LogController {
	func retryHistory() {
		guard !historyRecovery.isRetrying else { return }
		if terminating {
			retryStorageOnly()
			return
		}
		guard !reloadingHistory else { return }
		let generation = renderGeneration
		let storage = historicLog
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
		guard historyRecovery.localMessage != nil || historyStorageRecovery.localMessage != nil else { return }
		historyRecovery.isRetrying = true
		/* The banner outlives the controller, so the state is held strongly:
		 whoever is still watching it has to see the spinner stop. */
		let state = historyRecovery
		let storage = historicLog
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

extension LogController {
	func loadOlderHistory() {
		guard !terminating, !reloadingHistory, !loadingOlderHistory, serverHistoryRequest == nil,
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
		let kind: HistoricLogFetchRequest.Kind
		let limit = UInt(min(100, backingView.displayedBounds.remainingCapacity))
		if let cursor = backingView.displayedLines.first?.historyCursor {
			kind = .rowPage(before: cursor, fetchLimit: limit, limitToDate: nil)
		} else {
			kind = .before(uniqueIdentifier: oldestDisplayedLineNumber, fetchLimit: limit, limitToDate: nil)
		}
		let request = HistoricLogFetchRequest(
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
			let xpcEntries: [HistoricLogEntry]
			switch outcome {
			case let .page(entries): xpcEntries = entries
			case let .failed(failure):
				loadingOlderHistory = false
				olderHistoryFailure = failure
				return
			case .cancelled:
				loadingOlderHistory = false
				return
			}
			let ordered: [HistoricLogEntry] = if case .rowPage = request.kind {
				Array(xpcEntries.reversed())
			} else {
				xpcEntries
			}
			let entries = HistoricLogClient.logLines(from: ordered)
			guard entries.count == xpcEntries.count else {
				loadingOlderHistory = false
				olderHistoryFailure = .invalidEntry
				return
			}
			guard entries.isEmpty == false else {
				loadingOlderHistory = false
				locallyExhaustedBefore = oldestDisplayedLineNumber
				noteLocalScrollbackExhausted()
				return
			}
			prependHistoricLogLines(entries, before: oldestDisplayedLineNumber, cursors: ordered.map(\.cursor))
		}
	}

	private func noteLocalScrollbackExhausted() {
		guard let channel = associatedChannel,
		      let client = associatedClient,
		      client.chatHistoryIsAvailable(for: channel),
		      let oldestDate = backingView?.displayedLines.first?.receivedAt,
		      serverHistoryRequest == nil, serverHistoryExhaustedBefore != oldestDate,
		      serverHistoryCompletedBefore != oldestDate
		else {
			return
		}
		let request = ServerHistoryRequest(id: UUID(), before: oldestDate, oldestLineNumber: oldestLineNumber)
		serverHistoryRequest = request
		if client.requestServerHistory(request, in: channel, presentation: self) {
			serverHistoryFailed = false
		} else {
			serverHistoryRequest = nil
		}
	}

	func receiveServerHistory(_ outcome: ServerHistoryOutcome, for request: ServerHistoryRequest) {
		guard !terminating, serverHistoryRequest?.id == request.id else { return }
		guard oldestLineNumber == request.oldestLineNumber,
		      backingView?.displayedLines.first?.receivedAt == request.before
		else {
			serverHistoryRequest = nil
			return
		}
		switch outcome {
		case let .page(lines, extent):
			serverHistoryFailed = false
			guard !lines.isEmpty else {
				serverHistoryRequest = nil
				serverHistoryCompletedBefore = request.before
				if extent == .exhausted {
					serverHistoryExhaustedBefore = request.before
				}
				return
			}
			prependHistoricLogLines(lines, before: request.oldestLineNumber) { [weak self] accepted in
				guard let self, serverHistoryRequest?.id == request.id else { return }
				serverHistoryRequest = nil
				serverHistoryCompletedBefore = nil
				guard !accepted.isEmpty else { return }
				let acceptedIdentifiers = Set(accepted)
				for line in lines where acceptedIdentifiers.contains(line.uniqueIdentifier) {
					historicLog.writeNewEntry(with: line, forView: uniqueIdentifier)
				}
				// The local store was already exhausted before this older server page.
				locallyExhaustedBefore = oldestLineNumber
				if accepted.count == Set(lines.map(\.uniqueIdentifier)).count {
					serverHistoryCompletedBefore = request.before
					if extent ==
						.exhausted
					{
						serverHistoryExhaustedBefore = backingView?.displayedLines.first?.receivedAt
					}
				}
			}
		case let .failed(reason):
			serverHistoryRequest = nil
			serverHistoryFailed = true
			historyRecovery.serverFailureReason = reason
			serverHistoryCompletedBefore = nil
		case .cancelled:
			serverHistoryRequest = nil
			serverHistoryCompletedBefore = nil
		}
	}

	/** Whether Retry Server History has anything left to ask for.

	 A request already in flight is one answer; the other belongs to the client,
	 which retires the connection's server-history slot when an unlabeled request
	 times out, so the button is offered only while the client would act on it. */
	var serverHistoryRetryIsAvailable: Bool {
		guard !terminating, serverHistoryRequest == nil,
		      let client = associatedClient, let channel = associatedChannel
		else { return false }
		return client.canRetryServerHistory(for: channel)
	}

	/// Copies the answer into the observable recovery state the banner draws
	/// from, since none of the inputs above are observable themselves.
	func refreshServerRetryAvailability() {
		historyRecovery.serverRetryIsAvailable = serverHistoryRetryIsAvailable
	}

	func retryServerHistory() {
		guard serverHistoryRetryIsAvailable else { return }
		serverHistoryCompletedBefore = nil
		serverHistoryExhaustedBefore = nil
		noteLocalScrollbackExhausted()
	}

	func prependHistoricLogLines(_ logLines: [LogLine]) {
		prependHistoricLogLines(logLines, before: nil)
	}

	private func prependHistoricLogLines(
		_ logLines: [LogLine], before expectedOldest: String?, cursors: [HistoricLogRowCursor?] = [],
		completion: (@MainActor ([String]) -> Void)? = nil
	) {
		guard !terminating, !logLines.isEmpty, let associatedItem else {
			completion?([])
			return
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let context = makeRenderContext()
		let lines = logLines.enumerated().map {
			LogLineSnapshot(
				$0.element,
				in: context,
				historyCursor: cursors.indices.contains($0.offset) ? cursors[$0.offset] : nil
			)
		}
		/* The plugin renderers run here, on the main actor they are declared for;
		 the render job that follows is a function of the snapshots alone. */
		let snapshots = Self.applyingMessageRenderers(to: lines, for: self)
		enqueueRenderJob {
			Self.renderJob(snapshots, context: context)
		} apply: { [weak self] (results: [LogLineRenderResult]) in
			guard let self else { return }
			let generation = renderGeneration
			let apply: @MainActor () -> Void = { [weak self] in
				guard let self, acceptsRenderGeneration(generation) else { return }
				let accepted = applyPrependedLines(
					logLines,
					results: results,
					before: expectedOldest,
					forView: viewIdentifier
				)
				completion?(accepted)
			}
			if reloadingHistory {
				deferredPrepends.append(apply)
			} else {
				apply()
			}
		}
	}

	private func applyPrependedLines(
		_ logLines: [LogLine], results: [LogLineRenderResult], before expectedOldest: String?,
		forView viewIdentifier: String
	) -> [String] {
		if expectedOldest != nil {
			loadingOlderHistory = false
		}
		guard expectedOldest == nil || oldestLineNumber == expectedOldest else { return [] }
		let accepted = Set(backingView?.prependLines(results.map { applyingCurrentState(to: $0.transcriptLine) }) ?? [])
		historicLog.indexLogLines(
			zip(logLines, results).filter { accepted.contains($0.1.lineNumber) }.map(\.0), forView: viewIdentifier
		)
		for result in results where accepted.contains(result.lineNumber) {
			if var pluginMessage = result.pluginMessage?.makeObject(resolvingMembersIn: associatedChannel) {
				pluginMessage.isProcessedInBulk = true
				PluginDispatcher.dispatchDidPostNewMessage(pluginMessage)
			}
			if result.processesInlineMedia {
				processInlineMedia(result.links, atLineNumber: result.lineNumber)
			}
		}
		return results.map(\.lineNumber).filter { accepted.contains($0) }
	}
}
