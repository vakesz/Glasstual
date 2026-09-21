// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SlashCommandRequestTests {
	@Test(arguments: ["", "hello", " /join", "//join", "///", "/join\n#chat", "/join\r#chat", "/join\u{2028}#chat"])
	func excludesTextThatIsNotASingleCommandLine(text: String) {
		#expect(SlashCommandRequest(text: text, selection: caret(atEndOf: text)) == nil)
	}

	@Test(arguments: [
		NSRange(location: 0, length: 0),
		NSRange(location: NSNotFound, length: 0),
		NSRange(location: 20, length: 0),
		NSRange(location: 1, length: 2),
	])
	func excludesSelectionsAndInvalidCarets(selection: NSRange) {
		#expect(SlashCommandRequest(text: "/join", selection: selection) == nil)
	}

	@Test
	func completesTheWholeCommandTokenWithoutDiscardingArguments() throws {
		let text = "/jwrong  #café 🔔"
		let request = try #require(SlashCommandRequest(text: text, selection: NSRange(location: 2, length: 0)))
		let replacement = request.replacement(for: joinSuggestion)
		#expect(request.commandName == "jwrong")
		#expect(request.commandPrefix == "j")
		#expect(request.isEditingCommand)
		#expect((text as NSString).replacingCharacters(in: replacement.range, with: replacement.text) == "/join  #café 🔔")
		#expect(replacement.selection == NSRange(location: 5, length: 0))
	}

	@Test
	func completesBareSlashAndAppendsASingleSeparator() throws {
		let request = try #require(SlashCommandRequest(text: "/", selection: NSRange(location: 1, length: 0)))
		let replacement = request.replacement(for: joinSuggestion)
		#expect(replacement.range == NSRange(location: 0, length: 1))
		#expect(replacement.text == "/join ")
		#expect(replacement.selection == NSRange(location: 6, length: 0))
	}

	@Test
	func preservesWhitespaceAndCaretInsideUnicodeArguments() throws {
		let text = "/j\t#café 🔔"
		let request = try #require(SlashCommandRequest(text: text, selection: caret(atEndOf: text)))
		let replacement = request.replacement(for: joinSuggestion)
		let result = (text as NSString).replacingCharacters(in: replacement.range, with: replacement.text)
		#expect(request.isEditingCommand == false)
		#expect(result == "/join\t#café 🔔")
		#expect(replacement.selection == caret(atEndOf: result))
	}

	@Test
	func rejectsCaretInsideSurrogatePair() {
		#expect(SlashCommandRequest(text: "/me 🔔", selection: NSRange(location: 5, length: 0)) == nil)
	}

	private var joinSuggestion: SlashCommandSuggestion {
		SlashCommandSuggestion(name: "join", description: "", syntax: "", argumentHint: "", isScript: false)
	}

	private func caret(atEndOf text: String) -> NSRange {
		NSRange(location: text.utf16.count, length: 0)
	}
}
