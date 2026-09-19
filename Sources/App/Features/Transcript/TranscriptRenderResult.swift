// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/*  What a render was asked for and what it produced.

 The request pairs one line with the context it is drawn against; the result
 carries the row the transcript displays, plus the two facts the controller acts
 on before it hands the row to the view. */

nonisolated struct TranscriptRenderRequest: Sendable {
	var line: ChatLineSnapshot
	var context: TranscriptRenderContext
}

nonisolated struct TranscriptRenderResult: Sendable {
	var transcriptLine: TranscriptRow
	var fromCurrentSession: Bool
	var processesInlineMedia: Bool

	var lineNumber: String {
		transcriptLine.lineNumber
	}

	var isHighlight: Bool {
		transcriptLine.body.isHighlight
	}

	var links: [LinkParserResult] {
		transcriptLine.body.links
	}

	var mentionedNicknames: [String] {
		transcriptLine.body.mentionedNicknames
	}
}

/// Initial replay keeps raw archives distinct from the native rows it rendered.
nonisolated struct TranscriptHistoryRenderOutput: Sendable {
	let scrollbackLines: [ChatLine]
	let results: [TranscriptRenderResult]
	let fetchSucceeded: Bool
	let failure: ScrollbackFetchFailure?
}

extension TranscriptController {
	nonisolated static func renderJob( // nonisolated: pure
		_ lines: [ChatLineSnapshot],
		context: TranscriptRenderContext
	) -> [TranscriptRenderResult] {
		lines.map { renderJob(TranscriptRenderRequest(line: $0, context: context)) }
	}

	nonisolated static func renderJob( // nonisolated: pure
		_ request: TranscriptRenderRequest
	) -> TranscriptRenderResult {
		let line = request.line
		let attributes = TranscriptRenderOptions(
			renderLinks: !LinkParser.bannedLineTypes.contains(ChatLine.string(for: line.lineType) ?? ""),
			lineType: line.lineType,
			memberType: line.memberType,
			highlightKeywords: line.highlightKeywords ?? [],
			excludedKeywords: line.excludeKeywords ?? [],
			textPolicy: request.context.textPolicy,
			caseMapping: request.context.caseMapping
		)

		let body = TranscriptRenderer.renderNativeBody(
			line.messageBody,
			withAttributes: attributes,
			members: request.context.members.members
		)
		let markers = markers(for: request)
		let transcriptLine = TranscriptRow(
			lineNumber: line.uniqueIdentifier,
			receivedAt: line.receivedAt,
			nickname: line.nickname,
			memberType: line.memberType,
			lineType: line.lineType,
			command: line.command,
			messageIdentifier: line.messageIdentifier,
			replyToMessageIdentifier: line.replyToMessageIdentifier,
			deliveryState: line.deliveryState,
			deliveryFailureReason: nil,
			reactions: request.context.reactions(for: line),
			markers: markers,
			body: body,
			modeSymbol: line.modeSymbol,
			historyCursor: line.historyCursor
		)
		let inlineMedia = request.context.inlineMediaEnabled &&
			(line.lineType == .privateMessage || line.lineType == .action)
		return TranscriptRenderResult(
			transcriptLine: transcriptLine,
			fromCurrentSession: line.fromCurrentSession,
			processesInlineMedia: inlineMedia
		)
	}

	private nonisolated static func markers( // nonisolated: pure
		for request: TranscriptRenderRequest
	)
		-> [TranscriptMarker]
	{
		var result: [TranscriptMarker] = []
		if request.line.isFirstForDay, request.context.showsDateChanges {
			result.append(.date(DateFormatting.formatted(request.line.receivedAt, dateStyle: .long, timeStyle: .none, relative: false)))
		}
		return result
	}
}
