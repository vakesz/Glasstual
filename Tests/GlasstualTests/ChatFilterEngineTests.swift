/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import Testing

/// A chat filter's action is a user-authored template that a remote message is
/// substituted into, and every line of it that starts with a slash is sent as a
/// command. Everything here is about keeping the remote half of that inert.
@Suite("Chat filter engine")
@MainActor
struct ChatFilterEngineTests {
	/// The template was split into lines only after the message body had been
	/// substituted into it, so any of these separators inside a peer's message
	/// started a new line — and a line beginning with a slash is a command.
	/// Every one of them is legal in an IRC message body.
	@Test(
		"A separator in a remote message cannot start a command",
		arguments: [
			(name: "line feed", scalar: "\n"),
			(name: "carriage return", scalar: "\r"),
			(name: "vertical tab", scalar: "\u{000B}"),
			(name: "form feed", scalar: "\u{000C}"),
			(name: "next line", scalar: "\u{0085}"),
			(name: "line separator", scalar: "\u{2028}"),
			(name: "paragraph separator", scalar: "\u{2029}"),
		]
	)
	func remoteSeparatorsCannotStartACommand(_ separator: (name: String, scalar: String)) {
		let commands = ChatFilterEngine.actionCommands(
			in: "/say caught one: %_originalMessage_%",
			replacing: ["%_originalMessage_%": "hello\(separator.scalar)/quit goodbye"]
		)

		#expect(commands.count == 1)
		#expect(commands.first?.hasPrefix("say caught one: ") == true)
		#expect(commands.contains { $0.hasPrefix("quit") } == false)
		#expect(commands.first?.contains(separator.scalar) == false)
	}

	/// The same for a value that is nothing but a command, which is the shortest
	/// form of the attack.
	@Test("A remote message that is only a command line is inert")
	func remoteCommandOnlyMessageIsInert() {
		let commands = ChatFilterEngine.actionCommands(
			in: "/msg #ops %_originalMessage_%",
			replacing: ["%_originalMessage_%": "\u{2028}/quit"]
		)

		#expect(commands == ["msg #ops /quit"])
	}

	@Test("The template's own lines are what become commands")
	func templateLinesBecomeCommands() {
		let commands = ChatFilterEngine.actionCommands(
			in: "/say one\r\n/say two\nnot a command\n//escaped\n/",
			replacing: [:]
		)

		#expect(commands == ["say one", "say two"])
	}

	/// Substitution used to walk a dictionary, replacing one token at a time
	/// over the whole template, so a value written by an earlier iteration was
	/// still there to be matched by a later one — and the iteration order of a
	/// dictionary is not even fixed between runs.
	@Test("A token inside a substituted value is not expanded again")
	func substitutedValuesAreNotRescanned() {
		let commands = ChatFilterEngine.actionCommands(
			in: "/say %_originalMessage_% from %_senderHostmask_%",
			replacing: [
				"%_originalMessage_%": "%_senderHostmask_%",
				"%_senderHostmask_%": "alice!user@example.test",
			]
		)

		#expect(commands == ["say %_senderHostmask_% from alice!user@example.test"])
	}

	/// The same property with the token spelled by a numbered parameter, which
	/// was substituted in a second loop after the named ones.
	@Test("A parameter token inside a message body stays literal")
	func parameterTokenInMessageBodyStaysLiteral() {
		let commands = ChatFilterEngine.actionCommands(
			in: "/say %_originalMessage_%|%_Parameter_0_%",
			replacing: ["%_originalMessage_%": "%_Parameter_0_%", "%_Parameter_0_%": "#secret"]
		)

		#expect(commands == ["say %_Parameter_0_%|#secret"])
	}

	@Test("A token with no value expands to nothing")
	func unknownTokenExpandsToNothing() {
		#expect(
			ChatFilterEngine.actionCommands(in: "/say [%_channelName_%]", replacing: ["%_channelName_%": ""])
				== ["say []"]
		)
	}

	/// The template is the user's, so its own newlines still separate commands;
	/// only what is substituted into it is stripped.
	@Test("A multi-line template still sends every one of its commands")
	func multiLineTemplateStillSendsEveryCommand() {
		let commands = ChatFilterEngine.actionCommands(
			in: "/mode %_channelName_% +b %_senderHostmask_%\n/kick %_channelName_% %_senderNickname_%",
			replacing: [
				"%_channelName_%": "#room",
				"%_senderHostmask_%": "alice!user@example.test",
				"%_senderNickname_%": "alice",
			]
		)

		#expect(commands == ["mode #room +b alice!user@example.test", "kick #room alice"])
	}

	/// Filters are matched against remote text on the main actor, once per
	/// arriving line, so the subject a user-authored pattern sees is bounded.
	@Test("Filter matching is bounded to a message-sized subject")
	func matchingIsBounded() {
		#expect(ChatFilterEngine.matchInputLimit == RegularExpression.inputLengthLimit)

		let subject = String(repeating: "a", count: ChatFilterEngine.matchInputLimit + 32) + "needle"

		#expect(RegularExpression.string(subject, isMatchedByRegex: "needle", withoutCase: true))
		#expect(
			RegularExpression.string(
				subject,
				isMatchedByRegex: "needle",
				withoutCase: true,
				inputLimit: ChatFilterEngine.matchInputLimit
			) == false
		)
	}
}
