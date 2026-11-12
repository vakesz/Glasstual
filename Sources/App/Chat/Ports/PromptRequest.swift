// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Which of an alert's up to three buttons the user chose. The names describe
/// button position, which is what the nib-era API promised its callers.
nonisolated enum AlertResponse: UInt, Sendable {
	case `default` = 1000
	case alternate = 1001
	case other = 1002
}

/// So the button a suppressed alert answers with can be stored beside the flag.
extension AlertResponse: SettingEnum {}

/// How loudly an alert speaks. The two that warn are badged with the system
/// caution mark.
nonisolated enum AlertStyle: Sendable {
	case informational
	case warning
	case critical
}

/// Which of an alert's buttons destroys something. That button carries the
/// destructive role, which is what tints it and tells VoiceOver the action
/// cannot be taken back.
nonisolated enum AlertDestructiveButton: Sendable {
	case `default`
	case alternate
}

/** Everything one question needs. Building the request is separate from
 showing it, which is what lets the suppression policy and the routing between
 a dialog and the conversation be exercised without a window server.

 The value belongs to the prompt port: the protocol layer says what to ask, and
 the application decides whether it opens as an alert or appears in the
 conversation. */
nonisolated struct AlertRequest: Sendable {
	var title: String
	var body: String
	var defaultButton: String
	var alternateButton: String?
	var otherButton: String?
	var destructiveButton: AlertDestructiveButton?
	/// Which button Escape presses. An alert with an alternate button assumes
	/// that one; name another where the way out is somewhere else, as it is
	/// when the third button is the one that changes nothing.
	var cancelButton: AlertResponse?
	/// The base key recording a "do not show again" choice. Without one the
	/// checkbox is not offered, because nothing would remember the answer.
	var suppressionKey: String?
	var suppressionText: String?
	var style: AlertStyle
	/// What an Accessibility client finds the alert by; its buttons take this
	/// plus the response they give. `nil` leaves the alert unidentified.
	var accessibilityIdentifier: String?
	/// What an answer needs beyond a button, or `nil` for a question answered
	/// by a button alone.
	var field: PromptField?
	/// How hard the question is to answer by accident. A security question is
	/// never answered by Return, `/yes`, a numeric shortcut or a stray click.
	var sensitivity: PromptSensitivity
	/// The word each button is typed as, in the conversation. A button without
	/// one is typed as ``PromptKeyword/fallback(for:in:)``.
	var keywords: [AlertResponse: PromptKeyword]
	/// `false` for a question that stays a dialog whatever the reader chose,
	/// because answering it needs what only a dialog shows.
	var allowsInline: Bool
	/// An identifier the asker's own typed command answers the question by,
	/// such as the `d1` of `/dcc trust d1 remember`.
	var reference: String?

	init(
		title: String,
		body: String,
		defaultButton: String,
		alternateButton: String? = nil,
		otherButton: String? = nil,
		destructiveButton: AlertDestructiveButton? = nil,
		cancelButton: AlertResponse? = nil,
		suppressionKey: String? = nil,
		suppressionText: String? = nil,
		style: AlertStyle = .informational,
		field: PromptField? = nil,
		sensitivity: PromptSensitivity = .routine,
		keywords: [AlertResponse: PromptKeyword] = [:],
		allowsInline: Bool = true,
		reference: String? = nil,
		accessibilityIdentifier: String? = nil
	) {
		self.title = title
		self.body = body
		self.defaultButton = defaultButton
		self.alternateButton = alternateButton
		self.otherButton = otherButton
		self.destructiveButton = destructiveButton
		self.cancelButton = cancelButton
		self.suppressionKey = suppressionKey
		self.suppressionText = suppressionText
		self.style = style
		self.field = field
		self.sensitivity = sensitivity
		self.keywords = keywords
		self.allowsInline = allowsInline
		self.reference = reference
		self.accessibilityIdentifier = accessibilityIdentifier
	}

	/** The button Escape presses.

	 Every alert has one: an alert with no way out but its own action is a trap,
	 and Escape on a single-button alert means "I have read it". */
	var escapeButton: AlertResponse {
		if let cancelButton {
			return cancelButton
		}
		return alternateButton == nil ? .default : .alternate
	}

	/** The button Return presses, if any.

	 Never the destructive one: a confirmation whose Return key erases something
	 turns a reflex into a loss. Nor is Cancel made the default of a routine
	 question to stand in for it, because Cancel already answers Escape and a
	 button carries one key equivalent: a destructive confirmation has no
	 default button at all, so the reader has to choose, as the Human Interface
	 Guidelines ask.

	 A security question is the deliberate exception: its Return presses only
	 its way out, so a password, a file or a connection is never let through by
	 a reflex, and that button answers Escape as well. */
	var returnButton: AlertResponse? {
		if sensitivity == .security {
			return isDestructive(escapeButton) ? nil : escapeButton
		}
		if isDestructive(.default) {
			return nil
		}
		/* A routine question whose way out is its first button and which can
		 destroy something has Cancel in the default's place. */
		if destructiveButton != nil, escapeButton == .default {
			return nil
		}
		return .default
	}

	/// Whether Return and Escape press the same button, as they do for a notice
	/// and for a security question.
	var returnIsEscape: Bool {
		returnButton == escapeButton
	}

	/// The buttons the question offers, in the order they read.
	var responses: [AlertResponse] {
		[.default] + (alternateButton == nil ? [] : [.alternate]) + (otherButton == nil ? [] : [.other])
	}

	/// What a button says.
	func title(for response: AlertResponse) -> String? {
		switch response {
		case .default: defaultButton
		case .alternate: alternateButton
		case .other: otherButton
		}
	}

	/// Whether the button destroys something.
	func isDestructive(_ response: AlertResponse) -> Bool {
		switch destructiveButton {
		case .default: response == .default
		case .alternate: response == .alternate
		case nil: false
		}
	}

	/// The word a button is typed as.
	func keyword(for response: AlertResponse) -> PromptKeyword {
		keywords[response] ?? PromptKeyword.fallback(for: response, in: self)
	}

	/// A one-button question with nothing to type: it tells rather than asks.
	var isNotice: Bool {
		alternateButton == nil && otherButton == nil && field == nil
	}

	/** The button `/yes` stands for, or `nil` when `/yes` cannot answer.

	 It is the one button that is not the way out. A security question never
	 has one, nor does a question with two buttons besides the way out, because
	 "yes" would not say which. */
	var affirmativeButton: AlertResponse? {
		guard sensitivity == .routine else { return nil }
		if isNotice {
			return .default
		}
		let others = responses.filter { $0 != escapeButton }
		return others.count == 1 ? others.first : nil
	}
}

/// What an answer needs beyond a button.
nonisolated enum PromptField: Sendable, Equatable {
	/// A line of text, such as a virtual host. An optional one, such as the
	/// reason a message is deleted for, may be submitted empty.
	case text(placeholder: String, initialValue: String, isRequired: Bool = true)
	/// A secret, such as a password. It is never echoed, never typed into the
	/// message field and never written anywhere but to whoever asked.
	case secure(placeholder: String)

	/// Whether the field has to hold something before the question is answered.
	var isRequired: Bool {
		switch self {
		case let .text(_, _, isRequired): isRequired
		case .secure: true
		}
	}

	var isSecure: Bool {
		if case .secure = self {
			return true
		}
		return false
	}
}

/// How hard a question has to be to answer by accident.
nonisolated enum PromptSensitivity: Sendable, Equatable {
	case routine
	/** A question about where a password, a file or a connection goes. Its
	 answer has to be spelled out: Return, `/yes`, a numeric shortcut and a
	 click that lands before the question has settled on screen never count. */
	case security
}

/** The word a button is typed as, as in `/answer 3 send`.

 A command token, not prose, so it is not localized; the button's localized
 title is accepted as well, so a reader can type what they see. */
nonisolated enum PromptKeyword: String, Sendable, CaseIterable {
	case yes, no, ok, cancel
	case send, dontSend = "dont-send"
	case open, delete, remove
	case accept, decline
	case remember, once, replace, reject
	case oneMessage = "one-message", lineByLine = "line-by-line", truncate
	case existing, new
	case retry, reload, keep
	case kick, ban, kickban, banAccount = "ban-account"
	case submit, connect
	case alternative = "other"

	/// The word for a button the request did not name one for.
	static func fallback(for response: AlertResponse, in request: AlertRequest) -> PromptKeyword {
		if request.isNotice {
			return .ok
		}
		if response == request.escapeButton {
			return .cancel
		}
		return switch response {
		case .default, .alternate: request.field == nil ? .yes : .submit
		case .other: .alternative
		}
	}
}

/// What an alert came back with.
nonisolated struct AlertOutcome: Equatable, Sendable {
	let response: AlertResponse
	/// Whether the alert will not be shown again — either because the user
	/// ticked the checkbox now, or because a previous run recorded the choice
	/// and this run was skipped entirely.
	let isSuppressed: Bool
}

typealias AlertCompletion = @MainActor (AlertOutcome) -> Void
