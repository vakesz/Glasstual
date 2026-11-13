// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** A line typed into the message field that answers or lists questions.

 Only the message field produces one: the window reads the line before it
 reaches a session, so a script, a timer, a server's connect commands, an
 App Intent or a link never answers a question. A line a server sends is never
 parsed as a command at all. */
nonisolated enum PromptCommand: Equatable, Sendable {
	/// `/answer <number> [answer] [--remember]`.
	case answer(number: Int, choice: String?, remember: Bool)
	/// `/yes [number] [--remember]`.
	case yes(number: Int?, remember: Bool)
	/// `/no [number]`.
	case no(number: Int?)
	/// `/prompts`.
	case list
	/// `/dcc trust <id> <answer>`, `/dcc accept <id>` and `/dcc decline <id>`,
	/// which answer a DCC question by the identifier the session gave it.
	case dcc(reference: String, word: String?)
	/// A prompt command whose arguments do not parse.
	case malformed(LocalCommand)

	private static let rememberFlag = "--remember"

	/// Parses one typed line, or `nil` for a line that is not one of these.
	@MainActor
	init?(line: String) {
		let trimmed = line.trimmingCharacters(in: .whitespaces)
		guard trimmed.contains(where: \.isNewline) == false,
		      trimmed.hasPrefix("/"), trimmed.hasPrefix("//") == false
		else { return nil }
		var words = trimmed.dropFirst().split(whereSeparator: \.isWhitespace).map(String.init)
		guard let name = words.first.flatMap(LocalCommand.init(typedName:)) else { return nil }
		words.removeFirst()
		let remember = words.contains { $0.lowercased() == Self.rememberFlag }
		words.removeAll { $0.lowercased() == Self.rememberFlag }

		switch name {
		case .answer:
			guard let first = words.first, let number = Int(first), number > 0 else {
				self = .malformed(.answer)
				return
			}
			let rest = words.dropFirst().joined(separator: " ")
			self = .answer(number: number, choice: rest.isEmpty ? nil : rest, remember: remember)
		case .yes:
			switch QuestionNumber(words) {
			case let .given(number): self = .yes(number: number, remember: remember)
			case .omitted: self = .yes(number: nil, remember: remember)
			case .invalid: self = .malformed(.yes)
			}
		case .no:
			switch QuestionNumber(words) {
			case let .given(number): self = .no(number: number)
			case .omitted: self = .no(number: nil)
			case .invalid: self = .malformed(.no)
			}
		case .prompts:
			self = .list
		case .dcc:
			guard let subcommand = words.first?.lowercased(), ["trust", "accept", "decline"].contains(subcommand) else {
				return nil
			}
			guard words.count >= 2 else {
				self = .malformed(.dcc)
				return
			}
			let word: String? = switch subcommand {
			case "trust": words.count >= 3 ? words[2] : nil
			default: subcommand
			}
			guard let word else {
				self = .malformed(.dcc)
				return
			}
			self = .dcc(reference: words[1], word: word)
		default:
			return nil
		}
	}

	/// The optional question number `/yes` and `/no` take.
	private enum QuestionNumber {
		case omitted
		case given(Int)
		case invalid

		init(_ words: [String]) {
			switch words.count {
			case 0:
				self = .omitted
			case 1:
				if let number = Int(words[0]), number > 0 {
					self = .given(number)
				} else {
					self = .invalid
				}
			default:
				self = .invalid
			}
		}
	}
}

/// What a typed answer stands for, before it is matched to a question.
nonisolated enum TypedPromptAnswer: Equatable, Sendable {
	case yes
	case no
	/// What followed the number in `/answer`, or `nil` for nothing.
	case choice(String?)
	/// The answer word of a `/dcc` command.
	case dccWord(String)
}

/// What a typed answer chose.
nonisolated enum PromptChoice: Equatable, Sendable {
	case button(AlertResponse)
	/// The default button, with this in the field.
	case text(String)
	/// The question's field, to type into.
	case focusField
}

/// Why a typed answer was not taken.
nonisolated enum PromptRefusal: Error, Equatable, Sendable {
	/// A security question needs the answer spelled out, as this word.
	case spellOut(PromptKeyword)
	/// The words name none of the question's answers.
	case unknownChoice(String)
	/// The question has more than one way forward, so it needs one named.
	case needsChoice
	/// A secret belongs in the question's secure field, never on a command line.
	case secretAsArgument
}

/** Matches a typed answer to one of a question's answers.

 An answer is named by its word, as in `/answer 3 send`, or by its button's
 title as the reader sees it, whatever its case and accents. A routine question
 also takes the button's position, and `/yes` for its one way forward. A
 security question takes neither: its answer has to be spelled out. `/no` is
 always the way out, which is never the risky answer. */
nonisolated enum PromptAnswerParser {
	static func resolve(_ typed: TypedPromptAnswer, for request: AlertRequest) -> Result<PromptChoice, PromptRefusal> {
		switch typed {
		case .no:
			return .success(.button(request.escapeButton))
		case .yes:
			if let affirmative = request.affirmativeButton {
				if affirmative == .default, request.field?.isRequired == true {
					return .success(.focusField)
				}
				return .success(.button(affirmative))
			}
			return .failure(refusalForMissingChoice(in: request))
		case let .dccWord(word):
			guard let response = response(namedBy: word, in: request, acceptsTitles: false) else {
				return .failure(.unknownChoice(word))
			}
			return .success(.button(response))
		case .choice(nil):
			if request.field != nil {
				return .success(.focusField)
			}
			return .failure(refusalForMissingChoice(in: request))
		case let .choice(typed?):
			return resolve(choice: typed, for: request)
		}
	}

	private static func resolve(choice typed: String, for request: AlertRequest) -> Result<PromptChoice, PromptRefusal> {
		switch request.field {
		case .secure:
			return .failure(.secretAsArgument)
		case .text:
			return .success(.text(typed))
		case nil:
			break
		}
		if let response = response(namedBy: typed, in: request, acceptsTitles: true) {
			return .success(.button(response))
		}
		if let position = Int(typed) {
			guard request.sensitivity == .routine else {
				return .failure(refusalForMissingChoice(in: request))
			}
			let responses = request.responses
			if responses.indices.contains(position - 1) {
				return .success(.button(responses[position - 1]))
			}
		}
		return .failure(.unknownChoice(typed))
	}

	private static func refusalForMissingChoice(in request: AlertRequest) -> PromptRefusal {
		let forward = request.responses.filter { $0 != request.escapeButton }
		if request.sensitivity == .security, let first = forward.first {
			return .spellOut(request.keyword(for: first))
		}
		return .needsChoice
	}

	private static func response(namedBy typed: String, in request: AlertRequest, acceptsTitles: Bool) -> AlertResponse? {
		let folded = fold(typed)
		if let byKeyword = request.responses.first(where: { request.keyword(for: $0).rawValue == folded }) {
			return byKeyword
		}
		guard acceptsTitles else { return nil }
		return request.responses.first { response in
			request.title(for: response).map(fold) == folded
		}
	}

	/// Case, accents and a trailing ellipsis do not matter.
	private static func fold(_ text: String) -> String {
		text.trimmingCharacters(in: .whitespaces)
			.trimmingCharacters(in: CharacterSet(charactersIn: "…."))
			.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: .current)
	}
}
