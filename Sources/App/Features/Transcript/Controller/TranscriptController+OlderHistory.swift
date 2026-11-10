// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation

/** The scrollback pages the reader pulls in above what the view shows, and the
 server-history handshake behind them. The initial replay lives in
 `TranscriptController+HistoryLoading.swift`. */
extension TranscriptController {
	func loadOlderHistory() {
		guard !terminating, !historyRecovery.isReloading, !historyRecovery.isLoadingOlderPage,
		      serverHistory.request == nil,
		      let associatedItem,
		      let backingView, backingView.displayedBounds.remainingCapacity > 0,
		      let oldestDisplayedLineNumber = oldestLineNumber
		else { return }
		if locallyExhaustedBefore == oldestDisplayedLineNumber {
			noteLocalScrollbackExhausted()
			return
		}
		historyRecovery.beginOlderPage()
		historyRecovery.olderFailure = nil
		let generation = renderScheduler.generation
		let fetch = historyPageFetcher
		let viewIdentifier = associatedItem.uniqueIdentifier
		let kind: ScrollbackFetchRequest.Kind
		let limit = UInt(min(Int(HistoryFetch.pageSize), backingView.displayedBounds.remainingCapacity))
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
				historyRecovery.endOlderPage()
				return
			}
			let storedEntries: [ScrollbackEntry]
			switch outcome {
			case let .page(entries): storedEntries = entries
			case let .failed(failure):
				historyRecovery.endOlderPage()
				historyRecovery.olderFailure = failure
				return
			case .cancelled:
				historyRecovery.endOlderPage()
				return
			}
			let ordered: [ScrollbackEntry] = if case .rowPage = request.kind {
				Array(storedEntries.reversed())
			} else {
				storedEntries
			}
			let decoded = ScrollbackSession.decode(ordered)
			guard decoded.isWholePage else {
				historyRecovery.endOlderPage()
				historyRecovery.olderFailure = .invalidEntry
				return
			}
			let entries = decoded.lines
			guard entries.isEmpty == false else {
				historyRecovery.endOlderPage()
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
		      serverHistory.canAsk(before: oldestDate, lineNumber: oldestLineNumber)
		else {
			return
		}
		let request = ServerHistoryRequest(id: UUID(), before: oldestDate, oldestLineNumber: oldestLineNumber,
		                                   messageIdentifier: backingView?.displayedLines.first?.messageIdentifier)
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
				serverHistory.noteAnswered(before: request.before, extent: extent, oldestCursor: request.before,
				                           lineNumber: request.oldestLineNumber, oldestLineNumber: request.oldestLineNumber)
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
						oldestCursor: backingView?.displayedLines.first?.receivedAt,
						lineNumber: request.oldestLineNumber, oldestLineNumber: oldestLineNumber
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
		      let session = associatedSession, let conversation = associatedConversation,
		      let oldest = backingView?.displayedLines.first else { return false }
		let request = ServerHistoryRequest(id: UUID(), before: oldest.receivedAt, oldestLineNumber: oldest.lineNumber,
		                                   messageIdentifier: oldest.messageIdentifier)
		return session.canRetryServerHistory(for: conversation, request: request)
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
		enqueueRenderJob(cost: .cpu) {
			(
				results: Self.renderJob(snapshots, context: context),
				entries: archivesForStorage ? chatLines.map { $0.scrollbackEntry(forView: viewIdentifier) } : []
			)
		} apply: { [weak self] (rendered: (results: [TranscriptRenderResult], entries: [ScrollbackEntry])) in
			guard let self else { return }
			let generation = renderScheduler.generation
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
			if historyRecovery.isReloading {
				renderScheduler.hold(apply)
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
			historyRecovery.endOlderPage()
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
