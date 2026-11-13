// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** One question waiting for its answer.

 It is the question whichever form it takes: an alert shows it, or a card in
 the conversation does, and either way a typed command can answer it by its
 number. What the reader types into its field is held here until the question
 is answered, and dropped then. */
@MainActor
@Observable
final class PendingPrompt: Identifiable {
	/// What the reader types to answer it, as in `/answer 3 send`. Numbers count
	/// up from 1 for the life of the process and are never reused.
	let number: Int
	let request: AlertRequest
	let scope: PromptScope
	let route: PromptRoute
	/// Whether the "Don't ask again" choice is ticked.
	var remembers = false
	/// What has been typed into the question's field. A secret lives here only
	/// while it is being typed.
	var text: String

	var id: Int {
		number
	}

	@ObservationIgnored fileprivate var waiters: [UUID: CheckedContinuation<PromptAnswer, Never>] = [:]
	@ObservationIgnored fileprivate var isSettled = false
	/// The alert showing the question, taken down when it is answered some other way.
	@ObservationIgnored var dialog: Task<Void, Never>?

	fileprivate init(number: Int, request: AlertRequest, scope: PromptScope, route: PromptRoute) {
		self.number = number
		self.request = request
		self.scope = scope
		self.route = route
		text = if case let .text(_, initialValue, _) = request.field {
			initialValue
		} else {
			""
		}
	}

	/// Whether a later question is the same one, so its asker can wait on this
	/// answer instead of asking twice.
	fileprivate func matches(_ request: AlertRequest, scope: PromptScope, route: PromptRoute) -> Bool {
		request.field == nil && self.request.field == nil
			&& self.request.title == request.title && self.request.body == request.body
			&& self.request.responses == request.responses && self.request.reference == request.reference
			&& self.scope == scope && self.route == route
	}
}

/// A note about a typed answer, for the conversation it was typed in.
nonisolated struct PromptFeedback: Equatable, Sendable {
	/// The chat item the command was typed in.
	let itemID: String?
	let text: String
}

/// What answering a question came to.
nonisolated enum PromptAnswerResult: Equatable, Sendable {
	case answered
	/// It was answered or withdrawn already.
	case notPending
	/// The connection it was asked on has gone, so it was withdrawn instead.
	case connectionChanged
}

/** Every question waiting for an answer, in the order they were asked.

 Owned by the application, so a question outlives a conversation switch, a
 window rebuild or a theme reload. Each question is settled exactly once: by
 its answer, or by being withdrawn with its Escape answer. Nothing here is
 printed, logged or stored: an answered question leaves no trace. */
@MainActor
@Observable
final class PendingPromptRegistry {
	private(set) var pending: [PendingPrompt] = []
	/// The question whose field a typed `/answer` asked to type into.
	var fieldFocusRequest: Int?
	/// What the last typed answering command had to say, shown above the
	/// message field instead of being printed, so nothing about a question
	/// reaches the transcript, the scrollback or a log.
	var feedback: PromptFeedback?

	/// Whether the connection a question was bound to is still the one the
	/// session is on. An answer is only accepted while it is.
	@ObservationIgnored var isConnectionCurrent: @MainActor (PromptScope) -> Bool = { _ in true }
	@ObservationIgnored private var nextNumber = 1

	/// Records a question, or the identical one already waiting. The flag is
	/// `true` for a new question, which has to be shown.
	func register(_ request: AlertRequest, scope: PromptScope, route: PromptRoute) -> (prompt: PendingPrompt, isNew: Bool) {
		if let existing = pending.first(where: { $0.matches(request, scope: scope, route: route) }) {
			return (existing, false)
		}
		let prompt = PendingPrompt(number: nextNumber, request: request, scope: scope, route: route)
		nextNumber += 1
		pending.append(prompt)
		return (prompt, true)
	}

	/// Suspends until `prompt` is settled. A prompt settled already answers
	/// with its Escape button.
	func wait(for prompt: PendingPrompt, waiter: UUID) async -> PromptAnswer {
		await withCheckedContinuation { continuation in
			guard prompt.isSettled == false else {
				continuation.resume(returning: .escape(for: prompt.request))
				return
			}
			prompt.waiters[waiter] = continuation
		}
	}

	/// Lets one asker stop waiting, for a task that was cancelled. The question
	/// is withdrawn when nobody else waits on it.
	func removeWaiter(_ waiter: UUID, from prompt: PendingPrompt) {
		guard let continuation = prompt.waiters.removeValue(forKey: waiter) else { return }
		continuation.resume(returning: .escape(for: prompt.request))
		if prompt.waiters.isEmpty {
			withdraw(prompt)
		}
	}

	/** Answers `prompt` with a button.

	 Only a pending question takes an answer, and only while the connection it
	 was asked on is the session's; otherwise the question is withdrawn with
	 its Escape answer. `remember` counts only for a question that offers
	 "Don't ask again". */
	@discardableResult
	func answer(
		_ prompt: PendingPrompt,
		with response: AlertResponse,
		text: String? = nil,
		remember: Bool = false
	) -> PromptAnswerResult {
		guard prompt.isSettled == false, prompt.request.responses.contains(response) else { return .notPending }
		guard isConnectionCurrent(prompt.scope) else {
			withdraw(prompt)
			return .connectionChanged
		}
		let remembered = remember && prompt.request.suppressionKey != nil
		settle(prompt, with: PromptAnswer(
			outcome: AlertOutcome(response: response, isSuppressed: remembered),
			text: prompt.request.field == nil ? nil : text
		))
		return .answered
	}

	/// Withdraws `prompt` with its Escape answer: nobody needs it any more.
	func withdraw(_ prompt: PendingPrompt) {
		guard prompt.isSettled == false else { return }
		settle(prompt, with: .escape(for: prompt.request))
	}

	/// Withdraws every question that matches.
	func withdraw(where shouldWithdraw: (PendingPrompt) -> Bool) {
		for prompt in pending where shouldWithdraw(prompt) {
			withdraw(prompt)
		}
	}

	/** Forgets what has been typed into every secure field, for a reader who
	 switched conversations or left the window. The questions stay waiting; only
	 a half-typed secret goes, so none is left on screen unattended. */
	func discardTypedSecrets() {
		for prompt in pending where prompt.request.field?.isSecure == true {
			prompt.text = ""
		}
	}

	func prompt(numbered number: Int) -> PendingPrompt? {
		pending.first { $0.number == number }
	}

	/// The questions shown in the conversation of one chat item, oldest first.
	func inlinePrompts(inItem itemID: String) -> [PendingPrompt] {
		pending.filter { $0.route.itemID == itemID }
	}

	/// The question an asker's own command names, such as `d1` for a DCC question.
	func prompt(reference: String, inSession sessionID: String) -> PendingPrompt? {
		pending.first {
			$0.scope.sessionID == sessionID && $0.request.reference?.caseInsensitiveCompare(reference) == .orderedSame
		}
	}

	private func settle(_ prompt: PendingPrompt, with answer: PromptAnswer) {
		prompt.isSettled = true
		prompt.text = ""
		pending.removeAll { $0 === prompt }
		if fieldFocusRequest == prompt.number {
			fieldFocusRequest = nil
		}
		let waiters = prompt.waiters.values
		prompt.waiters.removeAll()
		prompt.dialog?.cancel()
		prompt.dialog = nil
		for waiter in waiters {
			waiter.resume(returning: answer)
		}
	}
}
