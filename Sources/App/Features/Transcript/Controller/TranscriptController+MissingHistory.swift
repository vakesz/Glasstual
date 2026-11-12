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

	/** Stores lines that fall somewhere before the live end and reads the
	 history again so they are drawn. A window of stored history keeps what it
	 shows; the lines are there the next time history is read.

	 A fill arrives a page at a time, faster than a read of the store finishes.
	 A page stored while a read is under way is drawn by one more read once
	 that one ends: the read in flight may have started before the page was in
	 the store, and it is the only thing that would otherwise draw it. */
	func archiveRecoveredChatLines(_ chatLines: [ChatLine]) {
		guard !terminating, let associatedItem, chatLines.isEmpty == false else { return }
		let viewIdentifier = associatedItem.uniqueIdentifier
		for line in chatLines {
			scrollback.writeNewEntry(line.scrollbackEntry(forView: viewIdentifier), for: line)
		}
		guard historyRecovery.isDetachedFromLive == false else { return }
		guard historyRecovery.isReloading == false else {
			historyRecovery.recoveredLinesAwaitReload = true
			return
		}
		reloadHistory()
	}

	/// Reads the history once more for lines that were recovered during the
	/// read that just ended.
	func reloadForRecoveredLinesIfNeeded() {
		guard historyRecovery.recoveredLinesAwaitReload, historyRecovery.isReloading == false else { return }
		historyRecovery.recoveredLinesAwaitReload = false
		guard historyRecovery.isDetachedFromLive == false else { return }
		reloadHistory()
	}
}
