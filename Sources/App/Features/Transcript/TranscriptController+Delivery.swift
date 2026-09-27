// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension TranscriptController {
	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		guard let update = transcriptProjection.updateDelivery(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason,
			isDisplayed: backingView?.containsLine(identifier: lineNumber) == true
		) else { return }
		forgetRetiredProjectionMessages()
		guard transcriptProjection.phase == .active else {
			return
		}
		enqueueMainActorWork { [weak self] in
			self?.applyDeliveryUpdate(update)
		}
	}

	private func applyDeliveryUpdate(_ update: TranscriptDeliveryUpdate) {
		let previousIdentifier: String? = if let backingView, let index = backingView.document.index(ofLine: update.lineNumber) {
			backingView.document[index].messageIdentifier
		} else {
			nil
		}
		backingView?.updateDelivery(update)
		transcriptProjection.deliveryWasApplied(update)
		forgetRetiredProjectionMessages()
		if let previousIdentifier, !MessageIdentifierKey.equal(previousIdentifier, update.messageIdentifier) {
			forgetReactions(for: [previousIdentifier])
		}
		if let identifier = update.messageIdentifier, let merged = reactions.reactions(forMessage: identifier) {
			backingView?.updateReactions(merged, messageIdentifier: identifier)
		}
	}

	/// A correlated echo replaces the pending local message under the same identity.
	/// Queue it behind the original print so even an immediate echo reaches a row.
	func replacePendingLine(_ line: ChatLine, reason: String?) {
		guard !terminating, let item = associatedItem else { return }
		if lastLineStorage?.uniqueIdentifier == line.uniqueIdentifier {
			lastLineStorage = line
		}
		let context = makeRenderContext(includingMembers: line.lineType.mentionsMembers)
		let mark = line.nickname.flatMap { associatedConversation?.findMember($0)?.mark } ?? ""
		let snapshot = ChatLineSnapshot(line, in: context, modeSymbol: mark)
		let viewIdentifier = item.uniqueIdentifier
		enqueueRenderJob {
			PrintedLineRender(result: Self.renderJob(TranscriptRenderRequest(line: snapshot, context: context)),
			                  scrollbackEntry: line.scrollbackEntry(forView: viewIdentifier))
		} apply: { [weak self] rendered in
			guard let self, !terminating else { return }
			if let update = transcriptProjection.updateDelivery(
				lineNumber: line.uniqueIdentifier, state: line.deliveryState,
				messageIdentifier: line.messageIdentifier, reason: reason,
				isDisplayed: backingView?.containsLine(identifier: line.uniqueIdentifier) == true,
				replacement: rendered.result.transcriptLine
			) {
				if transcriptProjection.phase == .active {
					applyDeliveryUpdate(update)
					if rendered.result.processesInlineMedia {
						processInlineMedia(rendered.result.links, atLineNumber: line.uniqueIdentifier)
					}
				}
				forgetRetiredProjectionMessages()
			}
			if let entry = rendered.scrollbackEntry {
				scrollback.replaceEntry(entry, for: line)
			}
		}
	}
}
