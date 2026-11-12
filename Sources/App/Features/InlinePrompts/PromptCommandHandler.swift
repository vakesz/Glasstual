// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What carrying out a typed prompt command came to.
nonisolated enum PromptCommandOutcome: Equatable, Sendable {
	case answered
	/// The question's field was focused, for the reader to type into.
	case focusedField
	/// Nothing was answered; this says why, or lists what is waiting.
	case feedback(String)
	/// A secret was typed on the command line and refused. The line has to
	/// stay out of input history.
	case refusedSecret(String)

	/// Whether the typed line may be kept in input history.
	var keepsLineInHistory: Bool {
		if case .refusedSecret = self {
			return false
		}
		return true
	}
}

/** Carries out `/answer`, `/yes`, `/no`, `/prompts` and the answering `/dcc`
 subcommands typed in one conversation.

 Without a number, `/yes` and `/no` answer the one question waiting in the
 conversation they were typed in; with more than one waiting they name none and
 list them instead. A number answers that question wherever it waits. */
@MainActor
struct PromptCommandHandler {
	let registry: PendingPromptRegistry
	/// The chat item the command was typed in.
	let itemID: String?
	/// The session of that chat item, which a DCC identifier belongs to.
	let sessionID: String?
	/// What a chat item is called, for `/prompts`.
	var itemName: (String) -> String? = { _ in nil }

	func perform(_ command: PromptCommand) -> PromptCommandOutcome {
		switch command {
		case let .answer(number, choice, remember):
			guard let prompt = registry.prompt(numbered: number) else {
				return .feedback(String(localized: .InlinePrompts.unknownNumber(number)))
			}
			return answer(prompt, typed: .choice(choice), remember: remember)
		case let .yes(number, remember):
			return target(number).map { answer($0, typed: .yes, remember: remember) } ?? missingTarget(number)
		case let .no(number):
			return target(number).map { answer($0, typed: .no, remember: false) } ?? missingTarget(number)
		case .list:
			return .feedback(listing())
		case let .dcc(reference, word):
			guard let sessionID, let prompt = registry.prompt(reference: reference, inSession: sessionID) else {
				return .feedback(String(localized: .IRC.dccQuestionUnknown(reference)))
			}
			guard let word else {
				return .feedback(String(localized: .InlinePrompts.usage))
			}
			switch PromptAnswerParser.resolve(.dccWord(word), for: prompt.request) {
			case let .success(.button(response)):
				return settle(registry.answer(prompt, with: response), prompt)
			case .success, .failure:
				return .feedback(String(localized: .IRC.dccQuestionWrongAnswer(reference, word)))
			}
		case .malformed:
			return .feedback(String(localized: .InlinePrompts.usage))
		}
	}

	/// The question a command without a number means: the only one waiting
	/// in this conversation.
	private func target(_ number: Int?) -> PendingPrompt? {
		if let number {
			return registry.prompt(numbered: number)
		}
		let here = itemID.map(registry.inlinePrompts(inItem:)) ?? []
		return here.count == 1 ? here.first : nil
	}

	private func missingTarget(_ number: Int?) -> PromptCommandOutcome {
		if let number {
			return .feedback(String(localized: .InlinePrompts.unknownNumber(number)))
		}
		let here = itemID.map(registry.inlinePrompts(inItem:)) ?? []
		guard here.isEmpty == false else {
			return .feedback(String(localized: .InlinePrompts.noneWaitingHere))
		}
		let entries = here.map { String(localized: .InlinePrompts.listEntry($0.number, $0.request.title)) }
		return .feedback(([String(localized: .InlinePrompts.severalWaiting(here.count))] + entries).joined(separator: "\n"))
	}

	private func answer(_ prompt: PendingPrompt, typed: TypedPromptAnswer, remember: Bool) -> PromptCommandOutcome {
		let request = prompt.request
		switch PromptAnswerParser.resolve(typed, for: request) {
		case let .success(.button(response)):
			return settle(registry.answer(prompt, with: response, text: prompt.text, remember: remember), prompt)
		case let .success(.text(text)):
			return settle(registry.answer(prompt, with: .default, text: text, remember: remember), prompt)
		case .success(.focusField):
			if typed == .yes, prompt.text.trimmingCharacters(in: .whitespaces).isEmpty == false, request.field?.isSecure == false {
				return settle(registry.answer(prompt, with: .default, text: prompt.text, remember: remember), prompt)
			}
			registry.fieldFocusRequest = prompt.number
			return .focusedField
		case let .failure(.spellOut(keyword)):
			return .feedback(String(localized: .InlinePrompts.spellOut(prompt.number, keyword.rawValue)))
		case .failure(.needsChoice):
			return .feedback(String(localized: .InlinePrompts.needsChoice(prompt.number, choices(of: request))))
		case let .failure(.unknownChoice(typed)):
			return .feedback(String(localized: .InlinePrompts.unknownChoice(prompt.number, typed, choices(of: request))))
		case .failure(.secretAsArgument):
			registry.fieldFocusRequest = prompt.number
			return .refusedSecret(String(localized: .InlinePrompts.secretAsArgument(prompt.number)))
		}
	}

	private func settle(_ result: PromptAnswerResult, _ prompt: PendingPrompt) -> PromptCommandOutcome {
		switch result {
		case .answered: .answered
		case .notPending: .feedback(String(localized: .InlinePrompts.notPending(prompt.number)))
		case .connectionChanged: .feedback(String(localized: .InlinePrompts.connectionChanged(prompt.number)))
		}
	}

	/// The words a question's answers are typed as.
	private func choices(of request: AlertRequest) -> String {
		request.responses.map { request.keyword(for: $0).rawValue }.formatted(.list(type: .or))
	}

	/// Every waiting question and where it waits.
	private func listing() -> String {
		guard registry.pending.isEmpty == false else {
			return String(localized: .InlinePrompts.noneWaiting)
		}
		let lines = registry.pending.map { prompt in
			let location = prompt.route.itemID.flatMap(itemName) ?? String(localized: .InlinePrompts.locationDialog)
			return String(localized: .InlinePrompts.listEntryWithLocation(prompt.number, prompt.request.title, location))
		}
		return lines.joined(separator: "\n")
	}
}
