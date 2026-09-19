// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

private func makeChatLine(
	body: String = "hello",
	lineType: ChatLineKind = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil
) -> ChatLine {
	var line = ChatLine()
	line.messageBody = body
	line.lineType = lineType
	line.nickname = "alice"
	line.messageIdentifier = messageIdentifier
	line.reactions = reactions
	return line
}

private func makeSnapshot(
	body: String = "hello",
	lineType: ChatLineKind = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil,
	in context: TranscriptRenderContext = TranscriptRenderContext()
) -> ChatLineSnapshot {
	ChatLineSnapshot(
		makeChatLine(body: body, lineType: lineType, messageIdentifier: messageIdentifier, reactions: reactions),
		in: context
	)
}

/// A line from a session other than this one, built the way an archive
/// restores one: the identity comes back from the archive rather than being
/// minted, which is what makes it belong to an earlier session.
private func makePreviousSessionLine(body: String = "previous") -> ChatLine {
	var line = ChatLine()
	line.messageBody = body
	line.lineType = .privateMessage
	line.nickname = "alice"
	line.restoreIdentity(
		uniqueIdentifier: "previous-session-line",
		sessionIdentifier: ChatLine.currentSessionIdentifier() == 1
			? 2
			: ChatLine.currentSessionIdentifier() - 1
	)
	return line
}

@Suite("Native log line rendering")
@MainActor
struct TranscriptRenderRequestTests {
	@Test("A rendered line carries semantic context without markup")
	func renderCarriesContextIntoResult() {
		let line = makeChatLine()
		let context = TranscriptRenderContext(inlineMediaEnabled: true)
		let result = TranscriptController.renderJob(TranscriptRenderRequest(line: ChatLineSnapshot(line, in: context), context: context))

		#expect(result.lineNumber == line.uniqueIdentifier)
		#expect(result.transcriptLine.body.plainText == "hello")
		#expect(result.transcriptLine.nickname == "alice")
		#expect(result.processesInlineMedia)
	}

	@Test("A keyword match is represented semantically")
	func keywordMatchIsAHighlight() {
		var line = makeChatLine(body: "hello alice")
		line.highlightKeywords = ["alice"]
		let context = TranscriptRenderContext()
		let result = TranscriptController.renderJob(
			TranscriptRenderRequest(line: ChatLineSnapshot(line, in: context), context: context)
		)

		#expect(result.isHighlight)
		#expect(result.transcriptLine.body.runs.contains { $0.traits.contains(.highlighted) })
	}

	@Test("Inline images only apply to message rows")
	func inlineMediaOnlyAppliesToMessages() {
		let context = TranscriptRenderContext(inlineMediaEnabled: true)
		let request = TranscriptRenderRequest(line: makeSnapshot(lineType: .topic, in: context), context: context)

		#expect(TranscriptController.renderJob(request).processesInlineMedia == false)
	}

	@Test("A batch preserves line order")
	func batchPreservesOrder() {
		let lines = [makeSnapshot(body: "one"), makeSnapshot(body: "two")]
		let results = TranscriptController.renderJob(lines, context: TranscriptRenderContext())

		#expect(results.map(\.lineNumber) == lines.map(\.uniqueIdentifier))
		#expect(results.map(\.transcriptLine.body.plainText) == ["one", "two"])
	}

	@Test("The current-session marker separates restored history from the first live line")
	func currentSessionMarkerFollowsHistory() {
		let scrollbackLine = makePreviousSessionLine()
		let current = makeChatLine(body: "current")
		let context = TranscriptRenderContext()

		let results = TranscriptController.renderJob(
			[ChatLineSnapshot(scrollbackLine, in: context), ChatLineSnapshot(current, in: context)],
			context: context
		)
		var boundary = TranscriptSessionBoundaryState()
		let markerLineNumber = boundary.prepareInitialHistory(
			[scrollbackLine],
			renderedLines: results
		)

		#expect(markerLineNumber == current.uniqueIdentifier)
		#expect(boundary.newestPreviousSessionLineNumber == scrollbackLine.uniqueIdentifier)
		#expect(boundary.firstCurrentSessionLineNumber == current.uniqueIdentifier)
	}

	@Test("A current-session marker waits for the first live line when replay contains only history")
	func currentSessionMarkerCanWaitForLiveTraffic() {
		let scrollbackLine = makePreviousSessionLine()
		let current = makeChatLine(body: "current")
		let context = TranscriptRenderContext()
		let scrollbackResult = TranscriptController.renderJob(
			TranscriptRenderRequest(line: ChatLineSnapshot(scrollbackLine, in: context), context: context)
		)
		let currentResult = TranscriptController.renderJob(
			TranscriptRenderRequest(line: ChatLineSnapshot(current, in: context), context: context)
		)
		var boundary = TranscriptSessionBoundaryState()

		let initialMarker = boundary.prepareInitialHistory([scrollbackLine], renderedLines: [scrollbackResult])
		let firstConsumption = boundary.consumePendingMarker(for: currentResult)
		let secondConsumption = boundary.consumePendingMarker(for: currentResult)

		#expect(initialMarker == nil)
		#expect(firstConsumption)
		#expect(secondConsumption == false)
		#expect(boundary.firstCurrentSessionLineNumber == current.uniqueIdentifier)
	}
}

@Suite("Log line render context reactions")
@MainActor
struct TranscriptRenderContextReactionTests {
	@Test("Archived and session reactions merge without duplicate nicknames")
	func reactionsMerge() {
		let line = makeSnapshot(messageIdentifier: "mid", reactions: ["👍": ["alice"]])
		let context = TranscriptRenderContext(
			sessionReactions: ["mid": ["👍": ["alice", "bob"], "🎉": ["carol"]]]
		)

		#expect(context.reactions(for: line) == ["👍": ["alice", "bob"], "🎉": ["carol"]])
	}

	@Test("Reactions stay keyed by message identifier")
	func reactionsDoNotLeak() {
		let line = makeSnapshot(messageIdentifier: "mid")
		let context = TranscriptRenderContext(sessionReactions: ["other": ["🎉": ["bob"]]])

		#expect(context.reactions(for: line).isEmpty)
	}
}
