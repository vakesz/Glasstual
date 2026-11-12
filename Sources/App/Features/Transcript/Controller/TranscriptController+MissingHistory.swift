// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Messages the server still has that a catch-up could not reach: the banner
 that offers them, and the lines a fill brings back. */
extension TranscriptController {
	func noteMissingServerHistory(_ state: MissingServerHistoryState) {
		historyRecovery.missingServerHistory = state
	}

	/// Asks the session to load the missing messages.
	func loadMissingServerHistory() {
		guard let session = associatedSession, let conversation = associatedConversation,
		      session.fillChatHistoryGap(in: conversation)
		else { return }
	}

	/** Stores lines that fall somewhere before the live end, and draws them
	 between the lines they fall between.

	 Only a transcript that has read its history, or is reading it, draws them:
	 one that has not reads them from the store with everything else when it
	 does, and a window of stored history keeps what it shows. Lines that
	 arrive during a read wait for it to end, so they are placed among every
	 line that read brings back. */
	func archiveRecoveredChatLines(_ chatLines: [ChatLine]) {
		guard !terminating, let associatedItem, chatLines.isEmpty == false else { return }
		let viewIdentifier = associatedItem.uniqueIdentifier
		for line in chatLines {
			scrollback.writeNewEntry(line.scrollbackEntry(forView: viewIdentifier), for: line)
		}
		guard backingView != nil, historyRecovery.isDetachedFromLive == false,
		      historyRecovery.isLoaded || historyRecovery.isReloading
		else { return }
		let context = makeHistoryRenderContext()
		let snapshots = chatLines.map { ChatLineSnapshot($0, in: context) }
		enqueueRenderJob(cost: .cpu) {
			Self.renderJob(snapshots, context: context)
		} apply: { [weak self] (results: [TranscriptRenderResult]) in
			guard let self else { return }
			let generation = renderScheduler.generation
			let apply: @MainActor () -> Void = { [weak self] in
				guard let self, acceptsRenderGeneration(generation) else { return }
				applyRecoveredLines(results)
			}
			if historyRecovery.isReloading {
				renderScheduler.hold(apply)
			} else {
				apply()
			}
		}
	}

	private func applyRecoveredLines(_ results: [TranscriptRenderResult]) {
		guard historyRecovery.isDetachedFromLive == false, let backingView else { return }
		let placed = backingView.insertRecoveredLines(results.map { applyingCurrentState(to: $0.transcriptLine) })
		/* Lines older than everything drawn are in the store now, so a store
		 that had nothing older has something again. */
		if placed.heldBack.isEmpty == false {
			locallyExhaustedBefore = nil
		}
		/* A boundary kept by time belongs on the first line after it, which
		 may now be one of these. */
		if placed.accepted.isEmpty == false, case let .after(date) = transcriptProjection.mark {
			backingView.setUnreadMarker(.after(date))
		}
	}
}
