// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Intent message validation")
struct IntentMessageTests {
	@Test("Text is trimmed, and a leading slash is kept as part of the message")
	func textIsKeptLiteral() throws {
		#expect(try IntentMessage.validated("  hello  \n") == "hello")
		#expect(try IntentMessage.validated("/quit bye") == "/quit bye")
		#expect(try IntentMessage.validated("//me") == "//me")
	}

	@Test("Empty and whitespace-only text is refused", arguments: ["", " ", "\n\t \n"])
	func emptyTextIsRefused(_ text: String) {
		#expect(throws: IntentActionError.emptyMessage) { try IntentMessage.validated(text) }
	}

	@Test("The input field's flood limits apply")
	func limitsApply() throws {
		let fourLines = "a\nb\nc\nd"
		#expect(try IntentMessage.validated(fourLines) == fourLines)
		#expect(throws: IntentActionError.messageTooLong) { try IntentMessage.validated(fourLines + "\ne") }
		#expect(try IntentMessage.validated(String(repeating: "x", count: 2040)).count == 2040)
		#expect(throws: IntentActionError.messageTooLong) {
			try IntentMessage.validated(String(repeating: "x", count: 2041))
		}
	}

	struct ChannelCase: Sendable {
		let input: String
		let expected: String?
	}

	@Test(
		"Channel names get a prefix when they have none and refuse what cannot be one",
		arguments: [
			ChannelCase(input: "swift", expected: "#swift"),
			ChannelCase(input: "#swift", expected: "#swift"),
			ChannelCase(input: "&local", expected: "&local"),
			ChannelCase(input: " swift ", expected: "#swift"),
			ChannelCase(input: "", expected: nil),
			ChannelCase(input: "two words", expected: nil),
			ChannelCase(input: "a,b", expected: nil),
			ChannelCase(input: "#", expected: nil),
		]
	)
	func channelNames(_ testCase: ChannelCase) {
		if let expected = testCase.expected {
			#expect((try? IntentMessage.channelName(testCase.input)) == expected)
		} else {
			#expect(throws: IntentActionError.invalidChannelName) { try IntentMessage.channelName(testCase.input) }
		}
	}

	@Test("A server that is connecting is waited for, and one that is not connecting is not")
	func readiness() {
		#expect(IntentServerReadiness.of(isLoggedIn: true, isConnecting: false, isConnected: true) == .ready)
		#expect(IntentServerReadiness.of(isLoggedIn: false, isConnecting: true, isConnected: false) == .wait)
		#expect(IntentServerReadiness.of(isLoggedIn: false, isConnecting: false, isConnected: true) == .wait)
		#expect(IntentServerReadiness.of(isLoggedIn: false, isConnecting: false, isConnected: false) == .unavailable)
	}

	@Test("Entity queries match names without regard to case or accents")
	func queryMatching() {
		#expect(IntentCatalog.matches("", in: ["x"]))
		#expect(IntentCatalog.matches("SWIFT", in: ["#swift"]))
		#expect(IntentCatalog.matches("cafe", in: ["Café"]))
		#expect(IntentCatalog.matches("lib", in: ["#swift", "Libera"]))
		#expect(IntentCatalog.matches("zzz", in: ["#swift"]) == false)
	}
}
