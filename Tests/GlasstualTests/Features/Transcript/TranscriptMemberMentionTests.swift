// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript member mentions")
struct TranscriptMemberMentionTests {
	@Test("Ordinary words matching member names keep their original appearance")
	func ordinaryWordsAreNotMentions() {
		let text = "I am not sure if I would count assembly as untyped, but I get the idea."
		let body = render(text, nicknames: ["I", "am", "get"])
		#expect(body.plainText == text)
		#expect(body.runs == [TranscriptTextRun(text: text)])
		#expect(body.mentionedNicknames.isEmpty)
		#expect(body.isHighlight == false)
	}

	@Test("Explicit mentions retain punctuation and canonical nickname targets")
	func explicitMentions() {
		let body = render("(@GET), get: hello!", nicknames: ["get"])
		#expect(body.mentionedNicknames == ["get"])
		#expect(body.runs == [
			TranscriptTextRun(text: "(@"),
			TranscriptTextRun(text: "GET", action: .nickname("get")),
			TranscriptTextRun(text: "), "),
			TranscriptTextRun(text: "get", action: .nickname("get")),
			TranscriptTextRun(text: ": hello!"),
		])
	}

	@Test("Mentions require a complete nickname and an unambiguous marker", arguments: [
		"get", "forget:", "@get_more", "@get-away", "get_more:", "get-away:",
		"person@get", "person@get:", "@@get", "@get@example.test", "@unknown", "@",
	])
	func completeNicknameAndMarker(text: String) {
		let body = render(text, nicknames: ["get"])
		#expect(body.mentionedNicknames.isEmpty)
		#expect(body.runs.allSatisfy { $0.action != .nickname("get") })
	}

	@Test("IRC nickname punctuation remains part of the target")
	func nicknamePunctuation() {
		let body = render("@get_more get-away:", nicknames: ["get", "get_more", "get-away"])
		#expect(body.mentionedNicknames == ["get_more", "get-away"])
		#expect(body.runs.filter { $0.action != nil }.map(\.text) == ["get_more", "get-away"])
	}

	@Test("Mentions use the server's nickname casemapping", arguments: [
		ISupportCaseMapping.ascii, .rfc1459, .strictRFC1459, .rfc7613,
	])
	func nicknameCaseMapping(mapping: ISupportCaseMapping) {
		let body = render("@{aLiCe} @nick~ @GET", nicknames: ["[Alice]", "nick^", "get"], mapping: mapping)
		let expected: [String] = switch mapping {
		case .rfc1459: ["[Alice]", "nick^", "get"]
		case .strictRFC1459: ["[Alice]", "get"]
		case .ascii, .rfc7613: ["get"]
		}
		#expect(body.mentionedNicknames == expected)
	}

	@Test("Unicode normalization preserves source ranges after supplementary characters")
	func unicodeNicknameRanges() {
		let body = render("🙂 @CAFE\u{301}, CAFÉ:", nicknames: ["Café"], mapping: .rfc7613)
		#expect(body.mentionedNicknames == ["Café"])
		#expect(body.runs == [
			TranscriptTextRun(text: "🙂 @"),
			TranscriptTextRun(text: "CAFE\u{301}", action: .nickname("Café")),
			TranscriptTextRun(text: ", "),
			TranscriptTextRun(text: "CAFÉ", action: .nickname("Café")),
			TranscriptTextRun(text: ":"),
		])
	}

	@Test("Nickname markers inside links remain links")
	func linksAreExcluded() {
		let body = render("https://example.test/@get https://get:6697/ @get", nicknames: ["get"])
		#expect(body.links.count == 2)
		#expect(body.mentionedNicknames == ["get"])
		#expect(body.runs.filter { $0.action == .nickname("get") }.map(\.text) == ["get"])
	}

	@Test("Bare own-nickname and explicit keyword highlights remain independent of member coloring",
	      arguments: [NicknameHighlightMatchMode.exact, .regularExpression])
	func notificationKeywordsRemainUnchanged(mode: NicknameHighlightMatchMode) {
		let body = TranscriptRenderer.renderNativeBody(
			"I can get that",
			withAttributes: TranscriptRenderOptions(
				lineType: .privateMessage,
				highlightKeywords: ["get"],
				textPolicy: TranscriptTextRules(highlightMatchingMethod: mode)
			),
			members: [RenderedMember(nickname: "get")]
		)
		#expect(body.isHighlight)
		#expect(body.mentionedNicknames.isEmpty)
		#expect(body.runs.filter { $0.traits.contains(.highlighted) }.map(\.text) == ["get"])
		#expect(body.runs.allSatisfy { $0.action == nil })
	}

	@Test("Bare nickname floods still suppress highlight notifications")
	func bareNicknameSpamRemainsSuppressed() {
		let body = TranscriptRenderer.renderNativeBody(
			"me " + Array(repeating: "get", count: 25).joined(separator: " "),
			withAttributes: TranscriptRenderOptions(lineType: .privateMessage, highlightKeywords: ["me"]),
			members: [RenderedMember(nickname: "get")]
		)
		#expect(body.isHighlight == false)
		#expect(body.mentionedNicknames.isEmpty)
	}

	@Test("Excluded keyword phrases still suppress notifications without hiding explicit member targets")
	func excludedKeywordsRemainUnchanged() {
		let body = TranscriptRenderer.renderNativeBody(
			"@get that",
			withAttributes: TranscriptRenderOptions(
				lineType: .privateMessage, highlightKeywords: ["get"], excludedKeywords: ["get that"]
			),
			members: [RenderedMember(nickname: "get")]
		)
		#expect(body.isHighlight == false)
		#expect(body.mentionedNicknames == ["get"])
		#expect(body.runs.contains { $0.action == .nickname("get") })
	}

	private func render(
		_ text: String,
		nicknames: [String],
		mapping: ISupportCaseMapping = .rfc1459
	) -> TranscriptBody {
		TranscriptRenderer.renderNativeBody(
			text,
			withAttributes: TranscriptRenderOptions(renderLinks: true, lineType: .privateMessage, caseMapping: mapping),
			members: RenderedMemberDirectory(nicknames.map { RenderedMember(nickname: $0) }, caseMapping: mapping)
		)
	}
}
