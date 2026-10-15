// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension TranscriptController {
	func noteReaction(
		_ wireEmoji: String,
		fromNickname nickname: String,
		toMessageIdentifier messageIdentifier: String
	) {
		guard holdsMessage(withIdentifier: messageIdentifier),
		      let merged = reactions.record(wireEmoji, from: nickname, forMessage: messageIdentifier)
		else {
			return
		}
		/* A view that is still replaying history has not drawn the line yet; the
		 reactions are handed to it when the replay finishes. */
		guard transcriptProjection.phase == .active else {
			return
		}
		enqueueMainActorWork { [weak self] in
			self?.backingView?.updateReactions(merged, messageIdentifier: messageIdentifier)
		}
	}

	/** Whether a reaction to `identifier` has a row to be drawn on, now or once
	 what is on its way arrives: a row the view shows or the projection keeps,
	 a printed line still rendering, or a replay that is still loading. */
	private func holdsMessage(withIdentifier identifier: String) -> Bool {
		transcriptProjection.phase != .active
			|| backingView?.document.ordinals(ofMessage: identifier) != nil
			|| transcriptProjection.containsMessage(withIdentifier: identifier)
			|| awaitingRender.lines.contains { MessageIdentifierKey.equal($0.messageIdentifier, identifier) }
	}

	/// The view trimmed the last rows of these messages.
	func transcriptDidRetireMessages(_ identifiers: [String]) {
		forgetReactions(for: identifiers)
	}

	func forgetRetiredProjectionMessages() {
		forgetReactions(for: transcriptProjection.takeRetiredMessageIdentifiers())
	}

	func forgetReactions(for identifiers: [String]) {
		reactions.forget(identifiers) { [self] identifier in
			backingView?.document.ordinals(ofMessage: identifier) != nil
				|| transcriptProjection.containsMessage(withIdentifier: identifier)
		}
	}
}
