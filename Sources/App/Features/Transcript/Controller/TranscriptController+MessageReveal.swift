// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Where finding a message by its identifier ended.
enum MessageRevealOutcome: Equatable {
	case shown
	case notFound
	/// The server cannot look messages up by identifier, and none is stored.
	case unavailable
}

/** Showing the message a reply quotes, wherever it is.

 On screen it is scrolled to. Stored, a window of history around it is shown.
 Otherwise, where the server looks messages up by identifier, the page around
 it is fetched with `CHATHISTORY AROUND`, stored, and shown the same way. */
extension TranscriptController {
	func revealMessage(identifier: String) async -> MessageRevealOutcome {
		guard !terminating, identifier.isEmpty == false, let associatedItem else { return .notFound }
		ensureBackingView()
		if jumpToDisplayedMessage(identifier) {
			return .shown
		}
		await settleInitialHistory()
		if jumpToDisplayedMessage(identifier) {
			return .shown
		}
		let request = ScrollbackFetchRequest(
			viewIdentifier: associatedItem.uniqueIdentifier,
			kind: .messageWindow(
				messageIdentifier: identifier,
				olderLimit: Self.historyWindowRadius,
				newerLimit: Self.historyWindowRadius
			)
		)
		let isAnchor: (ScrollbackEntry) -> Bool = { MessageIdentifierKey.equal($0.messageIdentifier, identifier) }
		if await showHistoryWindow(request, anchoredAt: isAnchor) {
			return .shown
		}
		guard let session = associatedSession, let conversation = associatedConversation,
		      session.chatHistoryIsAvailable(for: conversation),
		      session.chatHistoryReferenceSupport.messageIdentifiers
		else {
			return .unavailable
		}
		guard await session.requestMessageContext(identifier: identifier, in: conversation) else {
			return .notFound
		}
		await settleInitialHistory()
		return await showHistoryWindow(request, anchoredAt: isAnchor) ? .shown : .notFound
	}

	/// Whether looking the message up could find it: it is on screen, or the
	/// server can be asked for it. A stored line is found either way, so this
	/// only rules out what can never be found.
	func canRevealMessage(identifier: String) -> Bool {
		if backingView?.displayedLines.contains(where: { MessageIdentifierKey.equal($0.messageIdentifier, identifier) }) == true {
			return true
		}
		guard let session = associatedSession, let conversation = associatedConversation else { return false }
		return session.chatHistoryIsAvailable(for: conversation) && session.chatHistoryReferenceSupport.messageIdentifiers
			|| Scrollback.shared.duplicates.containsMessageIdentifier(identifier, forView: conversation.uniqueIdentifier)
	}

	/// Reveals the message and says so in the transcript where it is gone.
	func showOriginalMessage(identifier: String) {
		Task { [weak self] in
			guard let self else { return }
			let outcome = await revealMessage(identifier: identifier)
			guard outcome != .shown else { return }
			historyRecovery.unavailableMessageNotice = true
		}
	}

	/// `/chathistory around`: the same lookup, with a failure printed in the
	/// conversation where the command was typed.
	func revealMessage(withIdentifier identifier: String) -> Bool {
		Task { [weak self] in
			guard let self else { return }
			let outcome = await revealMessage(identifier: identifier)
			guard outcome != .shown, let session = associatedSession, let conversation = associatedConversation else { return }
			session.printDebugInformation(String(localized: .ChatHistory.chatHistoryMessageNotFound(identifier)), in: conversation)
		}
		return true
	}

	private func jumpToDisplayedMessage(_ identifier: String) -> Bool {
		guard let line = backingView?.displayedLines.first(where: { MessageIdentifierKey.equal($0.messageIdentifier, identifier) })
		else { return false }
		return backingView?.jump(to: line.lineNumber) == true
	}
}
