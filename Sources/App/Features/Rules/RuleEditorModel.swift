// Copyright (c) 2015 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/** Whether a match pattern compiles.

 Compiling is expensive and a `body` pass asks about two patterns, so this is
 computed when a pattern changes rather than each time the sheet is drawn. How
 long a pattern takes to run is bounded at match time by
 `RegularExpression.matchBudget` instead. */
struct RulePatternValidation: Equatable {
	var error: String?

	init(pattern: String = "") {
		guard pattern.isEmpty == false else { return }

		do {
			_ = try NSRegularExpression(pattern: pattern)
		} catch let failure {
			error = String(
				localized: .Rules.regularExpressionInvalid(failure.localizedDescription)
			)
		}
	}
}

/** The rule the editor is editing, and everything that decides whether it can
 be saved.

 The editor's forms are six tabs of fields over one value, and what makes that
 value acceptable -- a title, something to do, two patterns that compile, a
 command list the server would recognise and a forwarding destination it would
 accept -- is the part worth testing without a window. */
@MainActor
@Observable
final class RuleEditorModel {
	/// How long a forwarding destination may be. A channel name plus its
	/// network's longest prefix, with room to spare.
	static let forwardDestinationLengthLimit = 125

	/// The longest command name the editor accepts, past which the value is not
	/// a command but a sentence.
	static let commandLengthLimit = 20

	var rule: MessageRule {
		didSet {
			if rule.match != oldValue.match {
				matchValidation = RulePatternValidation(pattern: rule.match)
			}
			if rule.senderMatch != oldValue.senderMatch {
				senderValidation = RulePatternValidation(pattern: rule.senderMatch)
			}
		}
	}

	private var matchValidation: RulePatternValidation
	private var senderValidation: RulePatternValidation

	init(rule: MessageRule) {
		self.rule = rule
		matchValidation = RulePatternValidation(pattern: rule.match)
		senderValidation = RulePatternValidation(pattern: rule.senderMatch)
	}

	var canSave: Bool {
		let title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
		let action = rule.action.trimmingCharacters(in: .whitespacesAndNewlines)
		let destination = rule.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)

		return title.isEmpty == false &&
			(rule.ignoresContent || action.isEmpty == false || destination.isEmpty == false) &&
			matchError == nil && senderMatchError == nil && commandsError == nil && forwardDestinationError == nil
	}

	/// Whether the rule answers any of the three events a message arrives as.
	/// Ignoring operators only means something for those.
	var hasMessageEvent: Bool {
		rule.events.isDisjoint(with: [.plainTextMessage, .actionMessage, .noticeMessage]) == false
	}

	var matchError: String? {
		matchValidation.error
	}

	var senderMatchError: String? {
		rule.isLimitedToMyself ? nil : senderValidation.error
	}

	var commandsError: String? {
		normalizedCommands(from: rule.additionalCommands.joined(separator: ", ")) == nil
			? String(localized: .Rules.commandsInvalid)
			: nil
	}

	var forwardDestinationError: String? {
		let destination = rule.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		guard destination.isEmpty == false else { return nil }
		if destination.count > Self.forwardDestinationLengthLimit {
			return String(localized: .Rules.destinationTooLong)
		}
		let isValid = destination.allSatisfy { $0.isLetter || $0.isNumber || "-_ ".contains($0) }
		return isValid ? nil : String(localized: .Rules.destinationInvalid)
	}

	/// Whether an event can be answered at all: a rule limited to private
	/// messages can only see the three events a message arrives as.
	func eventIsAvailable(_ event: MessageRuleEvent) -> Bool {
		rule.destination != .privateMessages ||
			[MessageRuleEvent.plainTextMessage, .actionMessage, .noticeMessage].contains(event)
	}

	/** The rule as it is saved, or `nil` where it cannot be.

	 Saving is where the typed text becomes the stored value: the free-text
	 fields lose the whitespace around them, the command list is normalised, and
	 a rule that answers no message event stops claiming to ignore operators,
	 because there is nothing left for that to apply to. */
	func ruleForSubmission() -> MessageRule? {
		guard canSave else { return nil }

		var submitted = rule
		submitted.title = rule.title.trimmingCharacters(in: .whitespacesAndNewlines)
		submitted.action = rule.action.trimmingCharacters(in: .whitespacesAndNewlines)
		submitted.forwardDestination = rule.forwardDestination.trimmingCharacters(in: .whitespacesAndNewlines)
		submitted.additionalCommands = normalizedCommands(
			from: rule.additionalCommands.joined(separator: ", ")
		) ?? []
		if hasMessageEvent == false {
			submitted.ignoresOperators = false
		}
		return submitted
	}

	/** The command list as the engine stores it, or `nil` where one of them is
	 not a command.

	 A numeric is three digits, zero-padded, so `1` and `001` are one entry; a
	 name is upper-cased. Anything else -- punctuation, a name longer than a
	 command can be, a numeric of zero -- refuses the whole list rather than
	 quietly dropping the part that could not be read. */
	func normalizedCommands(from value: String) -> [String]? {
		var result: [String] = []
		for rawValue in value.components(separatedBy: ",") {
			let command = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
			guard command.isEmpty == false else { continue }
			let normalized: String
			if command.allSatisfy(\.isNumber) {
				guard command.count <= 3, let numeric = Int(command), numeric > 0 else {
					return nil
				}
				normalized = String(format: "%03d", numeric)
			} else if command.allSatisfy({ $0.isLetter || $0.isNumber }), command.count <= Self.commandLengthLimit {
				normalized = command.uppercased()
			} else {
				return nil
			}
			if result.contains(normalized) == false {
				result.append(normalized)
			}
		}
		return result
	}
}
