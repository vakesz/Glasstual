/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// Stands in for the theme and the live renderer. `renderTemplate` echoes the
/// template attributes it was handed into the HTML so that a test can see what
/// crossed the request-to-result boundary.
private struct StubLogLineRenderer: LogLineRendering {
	var keywordMatchFound = false
	var templateIsMissing = false

	func renderBody(
		_ body: String,
		attributes: [String: Any],
		members: [RenderedMember],
		results: inout [String: Any]
	) -> String {
		results[LogRendererResultKey.keywordMatchFound.rawValue] = NSNumber(value: keywordMatchFound)
		results[LogRendererResultKey.bodyWithoutEffects.rawValue] = body
		let renderLinks = (attributes[LogRendererConfigurationKey.renderLinks.rawValue] as? Bool) ?? false
		return "body(\(body),links=\(renderLinks),members=\(members.count))"
	}

	func renderTemplate(for lineType: TVCLogLineType, attributes: ThemeTemplateAttributes) -> String? {
		guard templateIsMissing == false else {
			return nil
		}
		let fields = [
			"type=\(lineType.rawValue)",
			"line=\(attributes[.lineNumber] as? String ?? "")",
			"server=\(attributes[.configuredServerName] as? String ?? "")",
			"style=\(attributes[.activeStyleAbsolutePath] as? String ?? "")",
			"highlight=\(attributes[.isHighlight] as? Bool ?? false)",
			"media=\(attributes[.inlineMediaEnabled] as? Bool ?? false)",
			"session=\(attributes[.showSessionIndicator] as? Bool ?? false)",
			"message=\(attributes[.formattedMessage] as? String ?? "")",
		]
		return "<\(fields.joined(separator: "|"))>"
	}
}

private func makeLogLine(
	body: String = "hello",
	lineType: TVCLogLineType = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil
) -> LogLine {
	let logLine = LogLine()
	logLine.messageBody = body
	logLine.lineType = lineType
	logLine.nickname = "alice"
	logLine.messageIdentifier = messageIdentifier
	logLine.reactions = reactions
	return logLine
}

/// The snapshot the pipeline actually renders, taken the way the controller
/// takes it but without the plugin hook a live controller would apply.
private func makeSnapshot(
	body: String = "hello",
	lineType: TVCLogLineType = .privateMessage,
	messageIdentifier: String? = nil,
	reactions: [String: [String]]? = nil,
	in context: LogLineRenderContext = LogLineRenderContext()
) -> LogLineSnapshot {
	LogLineSnapshot(
		makeLogLine(body: body, lineType: lineType, messageIdentifier: messageIdentifier, reactions: reactions),
		in: context
	)
}

@Suite("Log line render request")
@MainActor
struct LogLineRenderRequestTests {
	@Test("A rendered line carries its snapshot of main-actor state into the HTML")
	func renderCarriesContextIntoResult() throws {
		let logLine = makeLogLine()
		let context = LogLineRenderContext(
			networkName: "ExampleNet",
			styleAbsolutePath: "/tmp/style",
			inlineMediaEnabled: true,
			sessionIndicatorLineNumber: logLine.uniqueIdentifier
		)
		let request = LogLineRenderRequest(logLine: logLine, context: context)

		let result = try #require(LogController.render(request, using: StubLogLineRenderer()))

		#expect(result.lineNumber == logLine.uniqueIdentifier)
		#expect(result.timestamp == logLine.receivedAt.timeIntervalSince1970)
		#expect(result.isHighlight == false)
		#expect(result.processesInlineMedia)
		#expect(result.html == "<type=\(TVCLogLineType.privateMessage.rawValue)"
			+ "|line=\(logLine.uniqueIdentifier)"
			+ "|server=ExampleNet"
			+ "|style=/tmp/style"
			+ "|highlight=false"
			+ "|media=true"
			+ "|session=true"
			+ "|message=body(hello,links=true,members=0)>")
	}

	@Test("A keyword match is reported as a highlight")
	func keywordMatchIsAHighlight() throws {
		let request = LogLineRenderRequest(logLine: makeLogLine(), context: LogLineRenderContext())
		let renderer = StubLogLineRenderer(keywordMatchFound: true)

		let result = try #require(LogController.render(request, using: renderer))

		#expect(result.isHighlight)
		#expect(result.html.contains("highlight=true"))
	}

	@Test("Inline media stays off for line types that cannot carry it")
	func inlineMediaOnlyAppliesToMessages() throws {
		let context = LogLineRenderContext(inlineMediaEnabled: true)
		let request = LogLineRenderRequest(logLine: makeLogLine(lineType: .topic), context: context)

		let result = try #require(LogController.render(request, using: StubLogLineRenderer()))

		#expect(result.processesInlineMedia == false)
	}

	@Test("A line the theme has no template for is skipped rather than rendered")
	func missingTemplateSkipsTheLine() {
		let request = LogLineRenderRequest(logLine: makeLogLine(), context: LogLineRenderContext())
		let renderer = StubLogLineRenderer(templateIsMissing: true)

		#expect(LogController.render(request, using: renderer) == nil)
	}

	@Test("Rendering a batch keeps the lines that succeeded")
	func batchRenderKeepsSuccessfulLines() {
		let lines = [makeSnapshot(body: "one"), makeSnapshot(body: "two")]

		let results = LogController.render(lines, context: LogLineRenderContext(), using: StubLogLineRenderer())

		#expect(results.map(\.lineNumber) == lines.map(\.uniqueIdentifier))
		#expect(results.allSatisfy { $0.html.isEmpty == false })
	}

	@Test("Rendering a batch drops every line when no template resolves")
	func batchRenderDropsUnrenderableLines() {
		let lines = [makeSnapshot(body: "one"), makeSnapshot(body: "two")]
		let renderer = StubLogLineRenderer(templateIsMissing: true)

		#expect(LogController.render(lines, context: LogLineRenderContext(), using: renderer).isEmpty)
	}
}

@Suite("Log line render context reactions")
@MainActor
struct LogLineRenderContextReactionTests {
	@Test("A line with no reactions anywhere has none")
	func noReactions() {
		let context = LogLineRenderContext()

		#expect(context.reactions(for: makeSnapshot()) == nil)
	}

	@Test("Reactions archived with the line survive on their own")
	func archivedReactionsOnly() {
		let line = makeSnapshot(messageIdentifier: "mid", reactions: ["👍": ["alice"]])

		#expect(LogLineRenderContext().reactions(for: line) == ["👍": ["alice"]])
	}

	@Test("Reactions seen this session apply to a line that has none archived")
	func sessionReactionsOnly() {
		let line = makeSnapshot(messageIdentifier: "mid")
		let context = LogLineRenderContext(sessionReactions: ["mid": ["🎉": ["bob"]]])

		#expect(context.reactions(for: line) == ["🎉": ["bob"]])
	}

	@Test("Archived and session reactions merge without duplicating a nickname")
	func mergedReactions() {
		let line = makeSnapshot(messageIdentifier: "mid", reactions: ["👍": ["alice"]])
		let context = LogLineRenderContext(
			sessionReactions: ["mid": ["👍": ["alice", "bob"], "🎉": ["carol"]]]
		)

		#expect(context.reactions(for: line) == ["👍": ["alice", "bob"], "🎉": ["carol"]])
	}

	@Test("Session reactions for another message do not leak into this line")
	func sessionReactionsAreKeyedByMessage() {
		let line = makeSnapshot(messageIdentifier: "mid")
		let context = LogLineRenderContext(sessionReactions: ["other": ["🎉": ["bob"]]])

		#expect(context.reactions(for: line) == nil)
	}
}

/// Deliverable of the render-pipeline step: the context carries a value
/// snapshot of the members, so nothing reaches back into the live member list
/// while a line renders off the main actor.
@Suite("Log line render member snapshot")
@MainActor
struct LogLineRenderMemberSnapshotTests {
	@Test("The sender's mode symbol comes from the snapshot rather than a live member")
	func modeSymbolComesFromTheSnapshot() {
		let context = LogLineRenderContext(
			isChannel: true,
			nicknameFormat: "<%@%n>",
			members: [RenderedMember(nickname: "Alice", mark: "@")]
		)

		#expect(makeSnapshot(in: context).formattedNickname == "<@alice>")
	}

	@Test("Members are matched the way IRC compares nicknames")
	func memberLookupIsCaseInsensitive() {
		let context = LogLineRenderContext(members: [RenderedMember(nickname: "Alice", mark: "+")])

		#expect(context.member(named: "ALICE")?.mark == "+")
		#expect(context.member(named: "bob") == nil)
	}

	@Test("Outside a channel there is no mode symbol to draw")
	func queryViewsHaveNoModeSymbol() {
		let context = LogLineRenderContext(
			isChannel: false,
			nicknameFormat: "<%@%n>",
			members: [RenderedMember(nickname: "alice", mark: "@")]
		)

		#expect(makeSnapshot(in: context).formattedNickname == "<alice>")
	}
}
