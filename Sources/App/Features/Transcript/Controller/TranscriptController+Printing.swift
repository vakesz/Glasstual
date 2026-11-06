// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What a print's render job hands back: the row to draw, and the line already
/// archived for the view's store.
nonisolated struct PrintedLineRender: Sendable {
	let result: TranscriptRenderResult
	let scrollbackEntry: ScrollbackEntry?
}

extension TranscriptController {
	func print(
		_ chatLine: ChatLine,
		completionBlock postPrintBlock: PrintedLineCompletion? = nil
	) {
		guard !terminating else {
			return
		}
		if chatLine.lineType == .mode {
			refreshTopicBar()
		}
		lastLineStorage = chatLine
		let context = makeRenderContext(includingMembers: chatLine.lineType.mentionsMembers)
		let conversation = associatedConversation
		let senderMark = conversation?.isChannel == true
			? chatLine.nickname.flatMap { conversation?.findMember($0)?.mark } ?? ""
			: ""
		let line = ChatLineSnapshot(chatLine, in: context, modeSymbol: senderMark)
		let viewIdentifier = associatedItem?.uniqueIdentifier
		let enqueued = enqueueRenderJob {
			/* Archived here, beside the render, so the main actor that applies
			 the line only hands the store a finished entry. */
			PrintedLineRender(
				result: Self.renderJob(TranscriptRenderRequest(line: line, context: context)),
				scrollbackEntry: viewIdentifier.map { chatLine.scrollbackEntry(forView: $0) }
			)
		} apply: { [weak self] (rendered: PrintedLineRender) in
			self?.applyPrintedLine(chatLine, rendered: rendered, completionBlock: postPrintBlock)
		}
		/* Only a line the pipeline took can be applied, and only an applied line
		 is withdrawn again: a job refused because the application is quitting
		 would otherwise stay awaiting a render that never comes. */
		if enqueued {
			awaitingRender.append(chatLine)
		}
	}

	private func applyPrintedLine(
		_ chatLine: ChatLine,
		rendered: PrintedLineRender,
		completionBlock postPrintBlock: PrintedLineCompletion?
	) {
		let result = rendered.result
		/* Withdrawn before any guard below, so a line one of them drops is not
		 left counted as a line that is still on its way to the view. */
		awaitingRender.withdraw(chatLine)
		guard !terminating else {
			return
		}
		/* The session can be torn down between enqueueing the line and printing
		 it; there is nothing left to attribute the line to if it has been. */
		guard let session = associatedSession, let associatedItem else {
			return
		}
		let lineNumber = result.lineNumber
		let conversation = associatedConversation
		let alreadyDisplayed = backingView?.containsLine(identifier: lineNumber) == true
		/* The same line printed again, as opposed to a different line carrying
		 a message identifier the view has already seen. It was stored when it
		 was first printed, and a second row under one line identifier is a
		 cursor history can no longer page from. */
		let alreadyPrinted = alreadyDisplayed || transcriptProjection
			.containsLine(withIdentifier: chatLine.uniqueIdentifier)
		let isDuplicate = alreadyPrinted
			|| chatLine.messageIdentifier.map { scrollback.duplicates.containsMessageIdentifier(
				$0,
				forView: associatedItem.uniqueIdentifier
			) } == true
		if result.isHighlight, !isDuplicate, let conversation {
			session.cacheHighlight(in: conversation, with: chatLine)
		}
		let projectionAction = transcriptProjection.record(result)
		forgetRetiredProjectionMessages()
		if case .append = projectionAction, !alreadyDisplayed {
			var displayedLine = applyingCurrentState(to: result.transcriptLine)
			if transcriptSessionBoundary.consumePendingMarker(for: result) {
				displayedLine.markers.insert(
					.currentSession(String(localized: .Transcript.currentSession)),
					at: 0
				)
			}
			backingView?.appendLines([displayedLine])
		}
		if case .append = projectionAction, !alreadyDisplayed, result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: lineNumber)
		}
		if alreadyPrinted == false {
			scrollback.writeNewEntry(
				rendered.scrollbackEntry ?? chatLine.scrollbackEntry(forView: associatedItem.uniqueIdentifier),
				for: chatLine
			)
		}
		/* The body was scanned against the member snapshot the line rendered
		 with; the conversation weight belongs to whoever is in it now. */
		if let conversation {
			let direction: MemberConversationDirection = chatLine.memberType == .localUser ? .outgoing : .mention
			for nickname in result.mentionedNicknames where conversation.findMember(nickname) != nil {
				conversation.recordConversation(with: nickname, direction: direction)
			}
		}
		var context = PrintedLineContext(
			session: session,
			conversation: conversation,
			highlight: result.isHighlight,
			chatLine: chatLine,
			lineNumber: lineNumber
		)
		context.isDuplicate = isDuplicate
		context.isDisplayed = alreadyDisplayed || backingView?.displayedLines.last?
			.matches(identifier: lineNumber) == true
		postPrintBlock?(context)
	}
}
