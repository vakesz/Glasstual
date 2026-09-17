// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Message tag parsing")
struct MessageParsingTests {
	@Test("Escapes are resolved and the known tags are lifted out")
	func messageTagsDecodeEscapesAndMetadata() {
		let parsed = MessageTagParser
			.parsedTags(fromSection: "msgid=abc;account=alice;a=b\\:c\\sd\\\\e\\r\\n;flag")

		#expect(parsed.tags["a"] == "b;c d\\e\r\n")
		#expect(parsed.tags["flag"] == "")
		#expect(parsed.messageIdentifier == "abc")
		#expect(parsed.senderAccount == "alice")
	}

	@Test("The last spelling of a duplicated tag wins and an unknown escape drops its backslash")
	func messageTagsPreserveLastDuplicateAndUnknownEscapeRules() {
		let parsed = MessageTagParser
			.parsedTags(fromSection: "a=first;;a=second;b=x\\qy;c=end\\")

		#expect(parsed.tags["a"] == "second")
		#expect(parsed.tags["b"] == "xqy")
		#expect(parsed.tags["c"] == "end")

		#expect(parsed.messageIdentifier == nil)
		#expect(parsed.senderAccount == nil)
	}
}
