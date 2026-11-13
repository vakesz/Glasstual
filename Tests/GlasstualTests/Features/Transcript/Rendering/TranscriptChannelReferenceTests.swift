// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript channel references")
@MainActor
struct TranscriptChannelReferenceTests {
	private func names(_ body: String, prefixes: [String] = ["#"]) -> [String] {
		let source = body as NSString
		return TranscriptChannelReference.locate(in: body, prefixes: prefixes).map { source.substring(with: $0) }
	}

	@Test("Punctuation that ends a sentence is not part of the name")
	func trailingPunctuationIsTrimmed() {
		#expect(names("see #swift.") == ["#swift"])
		#expect(names("is it #swift?") == ["#swift"])
		#expect(names("(join #swift)") == ["#swift"])
		#expect(names("#swift: hello") == ["#swift"])
	}

	@Test("A prefix inside a word does not begin a name")
	func midWordPrefixIsNotAName() {
		#expect(names("foo#bar").isEmpty)
		#expect(names("issue#42 and #real") == ["#real"])
	}

	@Test("Names may follow an opening bracket or a comma")
	func namesAfterPunctuation() {
		#expect(names("(#a,#b)") == ["#a", "#b"])
		#expect(names("\"#quoted\"") == ["#quoted"])
	}

	@Test("Only the advertised prefixes begin a name")
	func advertisedPrefixesOnly() {
		#expect(names("&local and #x", prefixes: ["&"]) == ["&local"])
		#expect(names("&local and #x", prefixes: ["#", "&"]) == ["&local", "#x"])
		#expect(names("#x", prefixes: []).isEmpty)
	}

	@Test("Dots, plus signs and other characters stay in the name")
	func nameCharacters() {
		#expect(names("#a.b") == ["#a.b"])
		#expect(names("#c++ is #ünï") == ["#c++", "#ünï"])
		#expect(names("##chan") == ["##chan"])
	}

	@Test("A prefix alone is not a name")
	func barePrefix() {
		#expect(names("#").isEmpty)
		#expect(names("# heading").isEmpty)
		#expect(names("#.").isEmpty)
	}

	@Test("Ranges are in UTF-16 units after astral characters")
	func rangesCountUTF16Units() {
		let ranges = TranscriptChannelReference.locate(in: "😀 #swift", prefixes: ["#"])
		#expect(ranges == [NSRange(location: 3, length: 6)])
	}

	@Test("A bell character ends a name")
	func controlCharacterEndsName() {
		#expect(names("#swift\u{07}more") == ["#swift"])
	}

	@Test("A name inside a link is not annotated as a channel")
	func nameInsideLinkIsNotLinked() {
		let body = TranscriptRenderer.renderNativeBody(
			"https://example.com/#anchor and #swift",
			withAttributes: TranscriptRenderOptions(renderLinks: true, lineType: .privateMessage),
			members: []
		)
		let channels = body.runs.compactMap { run -> String? in
			guard case let .channel(name) = run.action else { return nil }
			return name
		}
		#expect(channels == ["#swift"])
	}

	@Test("The renderer uses the prefixes it is given")
	func rendererHonoursPrefixes() {
		let body = TranscriptRenderer.renderNativeBody(
			"&local #x",
			withAttributes: TranscriptRenderOptions(lineType: .privateMessage, channelPrefixes: ["&"]),
			members: []
		)
		#expect(body.runs.contains { $0.action == .channel("&local") })
		#expect(body.runs.contains { $0.action == .channel("#x") } == false)
	}
}
