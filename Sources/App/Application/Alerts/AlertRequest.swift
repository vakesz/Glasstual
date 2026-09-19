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

/// Everything one alert needs. Building the request is separate from showing
/// it, which is what lets the suppression policy be exercised without a window
/// server.
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
		style: AlertStyle = .informational
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
	 turns a reflex into a loss. Where the destructive button is the only one,
	 nothing is defaulted and the reader has to choose.  */
	var returnButton: AlertResponse? {
		guard destructiveButton == .default else {
			return .default
		}
		return alternateButton == nil ? nil : .alternate
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
