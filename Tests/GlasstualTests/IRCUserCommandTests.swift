/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/// The command line the user types is parsed once, into a command index entry
/// and a cursor over the arguments. These pin the parsing, the arity the index
/// declares, and the developer-mode flag that gates dispatch.
@MainActor
struct IRCUserCommandTests {
	private func parsed(_ input: String) throws -> ParsedUserCommand {
		CommandIndex.populateCommandIndex()

		return try #require(ParsedUserCommand(input))
	}

	@Test
	func resolvesTheCommandIndexEntryForATypedCommand() throws {
		let command = try parsed("/JOIN #channel key")

		#expect(command.command == "JOIN")
		#expect(command.localCommand == .join)
		#expect(command.isDeveloperModeOnly == false)
		#expect(command.arguments.rest == "#channel key")
	}

	@Test
	func acceptsACommandWithoutTheLeadingSlash() throws {
		#expect(try parsed("join #channel").localCommand == .join)
	}

	@Test
	func resolvesTheShorthandCommandsToTheirOwnCases() throws {
		#expect(try parsed("/m +o alice").localCommand == .modeShortcut)
		#expect(try parsed("/t new topic").localCommand == .topicShortcut)
	}

	@Test
	func leavesAnUnknownCommandWithoutAnIndexEntry() throws {
		let command = try parsed("/nosuchcommand argument")

		#expect(command.localCommand == nil)
		#expect(command.command == "nosuchcommand")
		#expect(command.arguments.rest == "argument")
	}

	@Test
	func rejectsAnEmptyLine() {
		#expect(ParsedUserCommand("") == nil)
	}

	/// The index marks a handful of commands developer-only. The flag has to
	/// survive parsing, because dispatch is what refuses them.
	@Test(arguments: ["recv", "join_random", "tage"])
	func reportsDeveloperOnlyCommands(name: String) throws {
		#expect(try parsed("/\(name)").isDeveloperModeOnly)
	}

	@Test(arguments: ["join", "msg", "topic", "quit"])
	func doesNotReportOrdinaryCommandsAsDeveloperOnly(name: String) throws {
		#expect(try parsed("/\(name)").isDeveloperModeOnly == false)
	}
}

@MainActor
struct CommandArgumentsTests {
	@Test
	func walksTokensLeftToRightWithoutDestroyingTheLine() {
		var arguments = CommandArguments("#channel alice bye now")

		#expect(arguments.next() == "#channel")
		#expect(arguments.next() == "alice")
		#expect(arguments.rest == "bye now")
	}

	/// The struct is a value: a dispatcher that pulls a token cannot disturb
	/// the copy the next dispatcher is handed.
	@Test
	func copiesDoNotShareACursor() {
		var arguments = CommandArguments("one two three")
		var copy = arguments

		_ = arguments.next()

		#expect(arguments.rest == "two three")
		#expect(copy.rest == "one two three")
		#expect(copy.next() == "one")
	}

	@Test
	func keepsReturningTheEmptyStringOnceExhausted() {
		var arguments = CommandArguments("only")

		#expect(arguments.next() == "only")
		#expect(arguments.next() == "")
		#expect(arguments.isEmpty)
	}

	@Test
	func readsAQuotedTokenAsOneArgument() {
		var arguments = CommandArguments("\"two words\" tail")

		#expect(arguments.nextQuoted() == "two words")
		#expect(arguments.rest == "tail")
	}

	/// The cursor stays put when the line does not start with a quote, so the
	/// caller can fall back to a plain token.
	@Test
	func leavesTheCursorAloneWhenThereIsNoQuotedToken() {
		var arguments = CommandArguments("plain tail")

		#expect(arguments.nextQuoted() == "")
		#expect(arguments.next() == "plain")
	}

	@Test
	func countsTheTokensThatAreLeft() {
		var arguments = CommandArguments("a b c")

		#expect(arguments.tokenCount == 3)
		_ = arguments.next()
		#expect(arguments.tokenCount == 2)
	}

	@Test
	func handsBackTheUnconsumedRemainderWithItsAttributes() {
		let key = NSAttributedString.Key("CommandArgumentsTest")
		let source = NSMutableAttributedString(string: "target hello")
		source.addAttribute(key, value: true, range: NSRange(location: 7, length: 5))

		var arguments = CommandArguments(source)
		#expect(arguments.next() == "target")

		let remainder = arguments.attributedRest
		#expect(remainder.string == "hello")
		#expect(remainder.attribute(key, at: 0, effectiveRange: nil) as? Bool == true)
	}

	@Test
	func returnsAnEmptyRemainderOnceTheLineIsConsumed() {
		var arguments = CommandArguments("only")
		_ = arguments.next()

		#expect(arguments.attributedRest.length == 0)
	}
}

struct CommandArityTests {
	struct SyntaxCase: Sendable {
		let syntax: String
		let arity: CommandArity
	}

	@Test(arguments: [
		SyntaxCase(syntax: "<message>", arity: CommandArity(required: 1, optional: 0)),
		SyntaxCase(syntax: "[comment]", arity: CommandArity(required: 0, optional: 1)),
		SyntaxCase(syntax: "[channel] <nickname> [comment]", arity: CommandArity(required: 1, optional: 2)),
		SyntaxCase(syntax: "<subcommand> <target> [arguments]", arity: CommandArity(required: 2, optional: 1)),
		SyntaxCase(syntax: "<channel[,channel]]> [key[,key]]", arity: CommandArity(required: 1, optional: 1)),
	])
	func countsTheGroupsTheSyntaxStringDeclares(testCase: SyntaxCase) {
		#expect(CommandArity(syntax: testCase.syntax) == testCase.arity)
	}

	@Test
	func treatsACommandWithNoSyntaxAsTakingNothing() {
		#expect(CommandArity(syntax: nil) == .none)
	}

	@MainActor
	@Test
	func carriesTheDeclaredArityOntoTheParsedArguments() throws {
		CommandIndex.populateCommandIndex()

		let command = try #require(ParsedUserCommand("/chathistory latest #channel"))

		#expect(command.arguments.arity.required == 2)
		#expect(command.arguments.satisfiesDeclaredArity)
	}

	@MainActor
	@Test
	func failsTheDeclaredArityWhenTooFewArgumentsAreGiven() throws {
		CommandIndex.populateCommandIndex()

		let command = try #require(ParsedUserCommand("/chathistory latest"))

		#expect(command.arguments.satisfiesDeclaredArity == false)
	}
}
