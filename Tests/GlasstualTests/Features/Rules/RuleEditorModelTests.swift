// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// What the rule editor accepts. The rules used to live inside the editor's
/// `View`, where none of this could be asked without a window.
@Suite("Rule editor model")
@MainActor
struct RuleEditorModelTests {
	private func model(_ configure: (inout MessageRule) -> Void = { _ in }) -> RuleEditorModel {
		var rule = MessageRule()
		rule.title = "Rule"
		rule.action = "/say hello"
		configure(&rule)
		return RuleEditorModel(rule: rule)
	}

	@Test("A rule needs a title and something to do")
	func savingNeedsATitleAndAnAction() {
		let untitled = model { $0.title = "   " }
		#expect(untitled.canSave == false)
		#expect(untitled.ruleForSubmission() == nil)

		let idle = model { $0.action = "" }
		#expect(idle.canSave == false)

		/* Hiding the message is something to do on its own, and so is forwarding
		 it somewhere. */
		let hiding = model {
			$0.action = ""
			$0.ignoresContent = true
		}
		#expect(hiding.canSave)

		let forwarding = model {
			$0.action = ""
			$0.forwardDestination = "elsewhere"
		}
		#expect(forwarding.canSave)
	}

	@Test("A pattern that does not compile is refused, and the sender's is ignored where it cannot apply")
	func patternsAreValidated() {
		let broken = model { $0.match = "([" }
		#expect(broken.matchError != nil)
		#expect(broken.canSave == false)

		broken.rule.match = "hello"
		#expect(broken.matchError == nil)
		#expect(broken.canSave)

		let sender = model { $0.senderMatch = "([" }
		#expect(sender.senderMatchError != nil)

		/* A rule limited to the person's own messages matches no sender, so the
		 pattern it is not going to use cannot refuse the save. */
		sender.rule.isLimitedToMyself = true
		#expect(sender.senderMatchError == nil)
	}

	@Test("A forwarding destination is refused past its length, and for characters a name cannot hold")
	func forwardDestinationIsValidated() {
		let limit = RuleEditorModel.forwardDestinationLengthLimit
		let atLimit = model { $0.forwardDestination = String(repeating: "a", count: limit) }
		#expect(atLimit.forwardDestinationError == nil)

		let overLimit = model { $0.forwardDestination = String(repeating: "a", count: limit + 1) }
		#expect(overLimit.forwardDestinationError == String(localized: .Rules.destinationTooLong))

		let punctuated = model { $0.forwardDestination = "no*stars" }
		#expect(punctuated.forwardDestinationError == String(localized: .Rules.destinationInvalid))
		#expect(punctuated.canSave == false)
	}

	@Test("Commands are numerics padded to three digits or upper-cased names, without duplicates")
	func commandsAreNormalised() {
		let editor = model()

		#expect(editor.normalizedCommands(from: "1, 001, privmsg, PRIVMSG") == ["001", "PRIVMSG"])
		#expect(editor.normalizedCommands(from: "  ,, notice ") == ["NOTICE"])
		#expect(editor.normalizedCommands(from: "") == [])
	}

	@Test("A command that is not one refuses the whole list")
	func invalidCommandsAreRefused() {
		let editor = model()

		#expect(editor.normalizedCommands(from: "0") == nil)
		#expect(editor.normalizedCommands(from: "1234") == nil)
		#expect(editor.normalizedCommands(from: "PRIV MSG") == nil)
		#expect(editor.normalizedCommands(from: "join!") == nil)

		let tooLong = String(repeating: "A", count: RuleEditorModel.commandLengthLimit + 1)
		#expect(editor.normalizedCommands(from: tooLong) == nil)
		#expect(editor.normalizedCommands(from: String(tooLong.dropLast())) == [String(tooLong.dropLast())])
	}

	@Test("A saved rule keeps its trimmed text, its normalised commands, and drops an operator rule it cannot apply")
	func submissionNormalisesTheRule() throws {
		let editor = model {
			$0.title = "  Rule  "
			$0.action = "  /say hello  "
			$0.forwardDestination = "  elsewhere  "
			$0.additionalCommands = ["1", "privmsg"]
		}

		let saved = try #require(editor.ruleForSubmission())
		#expect(saved.title == "Rule")
		#expect(saved.action == "/say hello")
		#expect(saved.forwardDestination == "elsewhere")
		#expect(saved.additionalCommands == ["001", "PRIVMSG"])
		/* The rule still answers the default message events, so ignoring
		 operators means something and is kept. */
		#expect(saved.ignoresOperators)

		editor.rule.events = []
		let withoutMessages = try #require(editor.ruleForSubmission())
		#expect(withoutMessages.ignoresOperators == false)
	}

	@Test("A rule limited to private messages can only answer the three message events")
	func availableEventsFollowTheDestination() {
		let anywhere = model()
		#expect(anywhere.eventIsAvailable(.userJoinedChannel))

		let privateOnly = model { $0.destination = .privateMessages }
		#expect(privateOnly.eventIsAvailable(.plainTextMessage))
		#expect(privateOnly.eventIsAvailable(.actionMessage))
		#expect(privateOnly.eventIsAvailable(.noticeMessage))
		#expect(privateOnly.eventIsAvailable(.userJoinedChannel) == false)
	}
}
