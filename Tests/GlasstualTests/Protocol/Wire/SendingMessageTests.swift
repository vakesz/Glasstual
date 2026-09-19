// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

/// Migrated from the Objective-C SendingMessage test suite.
@MainActor
@Suite("Outgoing message building")
struct SendingMessageTests {
	@Test("A command without tags goes out under its wire name with a trailing last argument")
	func commandWithoutTagsIsUnchanged() throws {
		#expect(
			try SendingMessage.string(command: .privmsg, arguments: ["#c", "hello world"], tags: nil)
				== "PRIVMSG #c :hello world"
		)
		#expect(
			try SendingMessage.string(command: .privmsg, arguments: ["#c", "hi"], tags: [:])
				== "PRIVMSG #c :hi"
		)
	}

	/** The command index fixes where PRIVMSG's colon goes; it says nothing about
	 a CAP REQ that names several capabilities. The trailing parameter still has
	 to carry the colon, or the server keeps the first name and drops the rest. */
	@Test("A last argument with spaces is written as a trailing parameter even for an indexed command")
	func spacedLastArgumentIsTrailingRegardlessOfIndex() throws {
		#expect(
			try SendingMessage.string(command: .cap, arguments: ["REQ", "account-notify away-notify server-time"])
				== "CAP REQ :account-notify away-notify server-time"
		)
		#expect(try SendingMessage.string(command: .cap, arguments: ["REQ", "multi-prefix"]) == "CAP REQ multi-prefix")
		#expect(try SendingMessage.string(command: .cap, arguments: ["LS", "302"]) == "CAP LS 302")
		#expect(try SendingMessage.string(command: .cap, arguments: ["END"]) == "CAP END")
	}

	@Test("Tags are written in key order with the reserved characters escaped")
	func tagsAreSerializedSortedAndEscaped() throws {
		let tags = ["+typing": "active", "+draft/reply": "a b;c\\d\r\n", "flag": ""]

		#expect(
			SendingMessage.string(messageTags: tags)
				== "+draft/reply=a\\sb\\:c\\\\d\\r\\n;+typing=active;flag"
		)
		#expect(
			try SendingMessage.string(command: .tagmsg, arguments: ["#c"], tags: tags)
				== "@+draft/reply=a\\sb\\:c\\\\d\\r\\n;+typing=active;flag TAGMSG #c"
		)
	}

	@Test("A line built from tags parses back into the same tags")
	func tagEscapingRoundTrips() throws {
		let tags = [
			"a": "plain",
			"b": "semi;colon",
			"c": "with space",
			"d": "back\\slash",
			"e": "line\r\nbreak",
			"f": "trailing\\",
			"g": "unicode ✓",
			"h": "",
			// A value that already spells out escape sequences: the encoder has to
			// escape the backslashes so the decoder reads them back verbatim.
			"i": "a;b \r\n\\s\\:end\\",
		]
		let line = try SendingMessage.string(command: .tagmsg, arguments: ["#c"], tags: tags)
		let message = try #require(Message(line: line))

		#expect(message.command == "TAGMSG")
		#expect(message.messageTags == tags)
	}

	/// The transport is what turns a chat-history request into a line, so a
	/// labelled one gets its tag through the same path as any other tagged
	/// command.
	@Test("A labelled chat history request carries its tag and its own arguments")
	func chatHistoryRequestsAreTaggedByTheTransport() throws {
		#expect(
			try SendingMessage.string(
				command: .chathistory,
				arguments: ["BEFORE", "#swift", "timestamp=2026-08-26T12:00:00.000Z", "50"],
				tags: ["label": "history-1"]
			) == "@label=history-1 CHATHISTORY BEFORE #swift timestamp=2026-08-26T12:00:00.000Z 50"
		)
	}
}
