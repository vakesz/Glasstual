/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

private func makeLogLine(
	body: String = "hello",
	lineType: LogLineType = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil
) -> LogLine {
	var line = LogLine()
	line.messageBody = body
	line.lineType = lineType
	line.nickname = "alice"
	line.messageIdentifier = messageIdentifier
	line.reactions = reactions
	return line
}

private func makeSnapshot(
	body: String = "hello",
	lineType: LogLineType = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil,
	in context: TranscriptRenderContext = TranscriptRenderContext()
) -> LogLineSnapshot {
	LogLineSnapshot(
		makeLogLine(body: body, lineType: lineType, messageIdentifier: messageIdentifier, reactions: reactions),
		in: context
	)
}

/// A line from a session other than this one, built the way an archive
/// restores one: the identity comes back from the archive rather than being
/// minted, which is what makes it belong to an earlier session.
private func makePreviousSessionLine(body: String = "previous") -> LogLine {
	var line = LogLine()
	line.messageBody = body
	line.lineType = .privateMessage
	line.nickname = "alice"
	line.restoreIdentity(
		uniqueIdentifier: "previous-session-line",
		sessionIdentifier: LogLine.currentSessionIdentifier() == 1
			? 2
			: LogLine.currentSessionIdentifier() - 1
	)
	return line
}

@Suite("Native log line rendering")
@MainActor
struct TranscriptRenderRequestTests {
	@Test("A rendered line carries semantic context without markup")
	func renderCarriesContextIntoResult() {
		let line = makeLogLine()
		let context = TranscriptRenderContext(inlineMediaEnabled: true)
		let result = TranscriptController.renderJob(TranscriptRenderRequest(line: LogLineSnapshot(line, in: context), context: context))

		#expect(result.lineNumber == line.uniqueIdentifier)
		#expect(result.transcriptLine.body.plainText == "hello")
		#expect(result.transcriptLine.nickname == "alice")
		#expect(result.processesInlineMedia)
	}

	@Test("A keyword match is represented semantically")
	func keywordMatchIsAHighlight() {
		var line = makeLogLine(body: "hello alice")
		line.highlightKeywords = ["alice"]
		let context = TranscriptRenderContext()
		let result = TranscriptController.renderJob(
			TranscriptRenderRequest(line: LogLineSnapshot(line, in: context), context: context)
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
		let historical = makePreviousSessionLine()
		let current = makeLogLine(body: "current")
		let context = TranscriptRenderContext()

		let results = TranscriptController.renderJob(
			[LogLineSnapshot(historical, in: context), LogLineSnapshot(current, in: context)],
			context: context
		)
		var boundary = TranscriptSessionBoundaryState()
		let markerLineNumber = boundary.prepareInitialHistory(
			[historical],
			renderedLines: results
		)

		#expect(markerLineNumber == current.uniqueIdentifier)
		#expect(boundary.newestPreviousSessionLineNumber == historical.uniqueIdentifier)
		#expect(boundary.firstCurrentSessionLineNumber == current.uniqueIdentifier)
	}

	@Test("A current-session marker waits for the first live line when replay contains only history")
	func currentSessionMarkerCanWaitForLiveTraffic() {
		let historical = makePreviousSessionLine()
		let current = makeLogLine(body: "current")
		let context = TranscriptRenderContext()
		let historicalResult = TranscriptController.renderJob(
			TranscriptRenderRequest(line: LogLineSnapshot(historical, in: context), context: context)
		)
		let currentResult = TranscriptController.renderJob(
			TranscriptRenderRequest(line: LogLineSnapshot(current, in: context), context: context)
		)
		var boundary = TranscriptSessionBoundaryState()

		let initialMarker = boundary.prepareInitialHistory([historical], renderedLines: [historicalResult])
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
