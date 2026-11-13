// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Typed lines into answers. A security question takes only its answer
 spelled out; `/no` is always the way out. */
@MainActor
@Suite("Prompt answer parser")
struct PromptAnswerParserTests {
	private static let routine = AlertRequest(
		title: "Delete #old?", body: "", defaultButton: "Delete", alternateButton: "Cancel",
		destructiveButton: .default, keywords: [.default: .delete, .alternate: .cancel]
	)
	private static let security = ServerSession.credentialConsentAlert(host: "irc.example.test")

	@Test("The answering commands parse; everything else is left alone", arguments: [
		("/answer 3 send", PromptCommand.answer(number: 3, choice: "send", remember: false)),
		("/ANSWER 3 Send Line by Line --remember", .answer(number: 3, choice: "Send Line by Line", remember: true)),
		("/answer 4", .answer(number: 4, choice: nil, remember: false)),
		("/answer send", .malformed(.answer)),
		("/yes", .yes(number: nil, remember: false)),
		("/yes 2 --remember", .yes(number: 2, remember: true)),
		("/no 7", .no(number: 7)),
		("/no x", .malformed(.no)),
		("/prompts", .list),
		("/dcc trust d1 remember", .dcc(reference: "d1", word: "remember")),
		("/dcc accept d2", .dcc(reference: "d2", word: "accept")),
		("/dcc trust d1", .malformed(.dcc)),
	])
	func parsing(_ testCase: (line: String, command: PromptCommand)) {
		#expect(PromptCommand(line: testCase.line) == testCase.command)
	}

	@Test("Messages, //text, other commands and multi-line pastes are not prompt commands", arguments: [
		"yes", "//yes", "/dcc send bob file", "/msg bob /yes", "/yes\n/no", "/answers 3",
	])
	func notPromptCommands(_ line: String) {
		#expect(PromptCommand(line: line) == nil)
	}

	@Test("A routine answer is named by its word, its title or its position")
	func routineAnswers() {
		#expect(PromptAnswerParser.resolve(.choice("delete"), for: Self.routine) == .success(.button(.default)))
		#expect(PromptAnswerParser.resolve(.choice("CANCEL"), for: Self.routine) == .success(.button(.alternate)))
		#expect(PromptAnswerParser.resolve(.choice("2"), for: Self.routine) == .success(.button(.alternate)))
		#expect(PromptAnswerParser.resolve(.yes, for: Self.routine) == .success(.button(.default)))
		#expect(PromptAnswerParser.resolve(.no, for: Self.routine) == .success(.button(.alternate)))
		#expect(PromptAnswerParser.resolve(.choice("maybe"), for: Self.routine) == .failure(.unknownChoice("maybe")))
	}

	@Test("A localized button title counts, whatever its case and accents")
	func localizedTitle() {
		let request = AlertRequest(
			title: "Kérdés", body: "", defaultButton: "Törlés", alternateButton: "Mégsem",
			keywords: [.default: .delete, .alternate: .cancel]
		)
		#expect(PromptAnswerParser.resolve(.choice("torles"), for: request) == .success(.button(.default)))
		#expect(PromptAnswerParser.resolve(.choice("MÉGSEM"), for: request) == .success(.button(.alternate)))
	}

	@Test("A security question refuses /yes and a position, and takes its word")
	func securityAnswers() {
		#expect(PromptAnswerParser.resolve(.yes, for: Self.security) == .failure(.spellOut(.send)))
		#expect(PromptAnswerParser.resolve(.choice("2"), for: Self.security) == .failure(.spellOut(.send)))
		#expect(PromptAnswerParser.resolve(.choice(nil), for: Self.security) == .failure(.spellOut(.send)))
		#expect(PromptAnswerParser.resolve(.choice("send"), for: Self.security) == .success(.button(.alternate)))
		#expect(PromptAnswerParser.resolve(.no, for: Self.security) == .success(.button(.default)))
	}

	@Test("A question with two ways forward needs one named")
	func ambiguousYes() {
		let request = ServerSession.multilineChoiceAlert(for: MultilineProposal(
			lines: [], limits: MultilineLimits(maximumBytes: 4096, maximumLines: 10)
		))
		#expect(request.affirmativeButton == nil)
		#expect(PromptAnswerParser.resolve(.yes, for: request) == .failure(.needsChoice))
		#expect(PromptAnswerParser.resolve(.choice("line-by-line"), for: request) == .success(.button(.alternate)))
	}

	@Test("A secret is never taken from the command line; a text answer is")
	func fields() {
		var secret = Self.routine
		secret.field = .secure(placeholder: "Password")
		var text = Self.routine
		text.field = .text(placeholder: "vhost", initialValue: "")

		#expect(PromptAnswerParser.resolve(.choice("hunter2"), for: secret) == .failure(.secretAsArgument))
		#expect(PromptAnswerParser.resolve(.choice(nil), for: secret) == .success(.focusField))
		#expect(PromptAnswerParser.resolve(.choice("my.vhost"), for: text) == .success(.text("my.vhost")))
	}

	@Test("A /dcc word names a button by its word only")
	func dccWord() {
		let request = AlertRequest(
			title: "Changed", body: "", defaultButton: "Cancel", alternateButton: "Replace",
			destructiveButton: .alternate, cancelButton: .default, sensitivity: .security,
			keywords: [.default: .reject, .alternate: .replace], reference: "d1"
		)
		#expect(PromptAnswerParser.resolve(.dccWord("replace"), for: request) == .success(.button(.alternate)))
		#expect(PromptAnswerParser.resolve(.dccWord("once"), for: request) == .failure(.unknownChoice("once")))
		#expect(PromptAnswerParser.resolve(.dccWord("Cancel"), for: request) == .failure(.unknownChoice("Cancel")))
	}
}
