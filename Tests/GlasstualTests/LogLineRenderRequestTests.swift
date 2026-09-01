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
	in context: LogLineRenderContext = LogLineRenderContext()
) -> LogLineSnapshot {
	LogLineSnapshot(
		makeLogLine(body: body, lineType: lineType, messageIdentifier: messageIdentifier, reactions: reactions),
		in: context
	)
}

private func makePreviousSessionLine(body: String = "previous") -> LogLine {
	var values = LogLineArchive.DecodedValues()
	values.messageBody = body
	values.lineType = .privateMessage
	values.nickname = "alice"
	values.uniqueIdentifier = "previous-session-line"
	values.sessionIdentifier = LogLine.currentSessionIdentifier() == 1
		? 2
		: LogLine.currentSessionIdentifier() - 1
	var line = LogLine()
	line.restore(from: values)
	return line
}

@Suite("Native log line rendering")
@MainActor
struct LogLineRenderRequestTests {
	@Test("A rendered line carries semantic context without markup")
	func renderCarriesContextIntoResult() throws {
		let line = makeLogLine()
		let context = LogLineRenderContext(
			networkName: "ExampleNet",
			inlineMediaEnabled: true,
			nicknameFormat: "<%n>"
		)
		let result = try #require(LogController.renderJob(LogLineRenderRequest(logLine: line, context: context)))

		#expect(result.lineNumber == line.uniqueIdentifier)
		#expect(result.transcriptLine.body.plainText == "hello")
		#expect(result.transcriptLine.formattedNickname == "<alice>")
		#expect(result.processesInlineMedia)
	}

	@Test("A keyword match is represented semantically")
	func keywordMatchIsAHighlight() throws {
		var line = makeLogLine(body: "hello alice")
		line.highlightKeywords = ["alice"]
		let result = try #require(LogController.renderJob(
			LogLineRenderRequest(logLine: line, context: LogLineRenderContext())
		))

		#expect(result.isHighlight)
		#expect(result.transcriptLine.body.runs.contains { $0.traits.contains(.highlighted) })
	}

	@Test("Inline images only apply to message rows")
	func inlineMediaOnlyAppliesToMessages() throws {
		let context = LogLineRenderContext(inlineMediaEnabled: true)
		let request = LogLineRenderRequest(logLine: makeLogLine(lineType: .topic), context: context)

		#expect(try #require(LogController.renderJob(request)).processesInlineMedia == false)
	}

	@Test("A batch preserves line order")
	func batchPreservesOrder() {
		let lines = [makeSnapshot(body: "one"), makeSnapshot(body: "two")]
		let results = LogController.renderJob(lines, context: LogLineRenderContext())

		#expect(results.map(\.lineNumber) == lines.map(\.uniqueIdentifier))
		#expect(results.map(\.transcriptLine.body.plainText) == ["one", "two"])
	}

	@Test("The current-session marker separates restored history from the first live line")
	func currentSessionMarkerFollowsHistory() {
		let historical = makePreviousSessionLine()
		let current = makeLogLine(body: "current")
		let context = LogLineRenderContext()

		let results = LogController.renderJob(
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
	func currentSessionMarkerCanWaitForLiveTraffic() throws {
		let historical = makePreviousSessionLine()
		let current = makeLogLine(body: "current")
		let historicalResult = try #require(LogController.renderJob(
			LogLineRenderRequest(logLine: historical, context: LogLineRenderContext())
		))
		let currentResult = try #require(LogController.renderJob(
			LogLineRenderRequest(logLine: current, context: LogLineRenderContext())
		))
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
struct LogLineRenderContextReactionTests {
	@Test("Archived and session reactions merge without duplicate nicknames")
	func reactionsMerge() {
		let line = makeSnapshot(messageIdentifier: "mid", reactions: ["👍": ["alice"]])
		let context = LogLineRenderContext(
			sessionReactions: ["mid": ["👍": ["alice", "bob"], "🎉": ["carol"]]]
		)

		#expect(context.reactions(for: line) == ["👍": ["alice", "bob"], "🎉": ["carol"]])
	}

	@Test("Reactions stay keyed by message identifier")
	func reactionsDoNotLeak() {
		let line = makeSnapshot(messageIdentifier: "mid")
		let context = LogLineRenderContext(sessionReactions: ["other": ["🎉": ["bob"]]])

		#expect(context.reactions(for: line).isEmpty)
	}
}
