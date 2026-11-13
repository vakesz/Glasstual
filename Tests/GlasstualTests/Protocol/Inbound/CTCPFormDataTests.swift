// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct CTCPFormDataTests {
	/// A hostile server controls the LAGCHECK payload; repeating a key used
	/// to abort the process through `Dictionary(uniqueKeysWithValues:)`.
	@Test
	func duplicateKeysAreMergedRatherThanTrapping() {
		let form = CTCPPolicy.formData("a=1&a=2&b=3")

		#expect(form == ["a": "1", "b": "3"])
	}

	@Test
	func fieldsWithoutASeparatorAreIgnored() {
		#expect(CTCPPolicy.formData("a=1&nonsense&b=2") == ["a": "1", "b": "2"])
		#expect(CTCPPolicy.formData("").isEmpty)
	}

	@Test
	func valuesMayContainTheSeparator() {
		#expect(CTCPPolicy.formData("time=1=2") == ["time": "1=2"])
	}

	/// `/mylag` names the channel to answer in, and a channel name is made of
	/// the characters a form escapes: `#`, and `&` for a local channel. Read
	/// back undecoded, `%23chat` named no channel and the reply went nowhere.
	@Test("A form written by the session reads back to the same fields", arguments: [
		"#chat", "&local", "#a=b+c&d", "#ünïcode", "#100%",
	])
	func encodedFormRoundTrips(channelName: String) {
		let payload = CTCPPolicy.formEncoded([
			(key: "connection", value: "abc-123"),
			(key: "channel", value: channelName),
		])

		#expect(CTCPPolicy.formData(payload) == ["connection": "abc-123", "channel": channelName])
	}

	/// `/lag` queries the session itself, so with echo-message the copy the
	/// server sends back is the only one — and it was set aside with the echoes
	/// of queries sent to other people.
	@Test("A lag check answered through echo-message replies in the channel it names")
	func lagCheckIsReadThroughEchoMessage() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "user"])
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		session.markAsLoggedIn()
		session.enableCapability(.echoMessage)
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.activate()

		let payload = CTCPPolicy.formEncoded([
			(key: "connection", value: connection.uniqueIdentifier),
			(key: "time", value: String(Date().timeIntervalSince1970)),
			(key: "channel", value: "#chat"),
		])
		let message = try #require(Message(line: ":me!user@example.org PRIVMSG me :\u{01}LAGCHECK \(payload)\u{01}", on: session))

		session.receiveCTCPQuery(message, text: "LAGCHECK \(payload)")

		let sent = session.sentLines.compactMap { $0 as? String }
		#expect(sent.contains { $0.hasPrefix("PRIVMSG #chat :") })
	}

	@Test("A field with invalid percent-encoding is dropped")
	func invalidPercentEncodingIsDropped() {
		#expect(CTCPPolicy.formData("a=%zz&b=2") == ["b": "2"])
	}
}
