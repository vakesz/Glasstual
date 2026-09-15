/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct IRCCTCPFormDataTests {
	/// A hostile server controls the LAGCHECK payload; repeating a key used
	/// to abort the process through `Dictionary(uniqueKeysWithValues:)`.
	@Test
	func duplicateKeysAreMergedRatherThanTrapping() {
		let form = IRCCTCPPolicy.formData("a=1&a=2&b=3")

		#expect(form == ["a": "1", "b": "3"])
	}

	@Test
	func fieldsWithoutASeparatorAreIgnored() {
		#expect(IRCCTCPPolicy.formData("a=1&nonsense&b=2") == ["a": "1", "b": "2"])
		#expect(IRCCTCPPolicy.formData("").isEmpty)
	}

	@Test
	func valuesMayContainTheSeparator() {
		#expect(IRCCTCPPolicy.formData("time=1=2") == ["time": "1=2"])
	}

	/// `/mylag` names the channel to answer in, and a channel name is made of
	/// the characters a form escapes: `#`, and `&` for a local channel. Read
	/// back undecoded, `%23chat` named no channel and the reply went nowhere.
	@Test("A form written by the client reads back to the same fields", arguments: [
		"#chat", "&local", "#a=b+c&d", "#ünïcode", "#100%",
	])
	func encodedFormRoundTrips(channelName: String) {
		let payload = IRCCTCPPolicy.formEncoded([
			(key: "connection", value: "abc-123"),
			(key: "channel", value: channelName),
		])

		#expect(IRCCTCPPolicy.formData(payload) == ["connection": "abc-123", "channel": channelName])
	}

	/// `/lag` queries the client itself, so with echo-message the copy the
	/// server sends back is the only one — and it was set aside with the echoes
	/// of queries sent to other people.
	@Test("A lag check answered through echo-message replies in the channel it names")
	func lagCheckIsReadThroughEchoMessage() throws {
		let client = TestClient(configDictionary: ["nickname": "me", "username": "user"])
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection
		client.markAsLoggedIn()
		client.enableCapability(.echoMessage)
		let channel = try #require(client.findChannelOrCreate("#chat"))
		channel.activate()

		let payload = IRCCTCPPolicy.formEncoded([
			(key: "connection", value: connection.uniqueIdentifier),
			(key: "time", value: String(Date().timeIntervalSince1970)),
			(key: "channel", value: "#chat"),
		])
		let message = try #require(Message(line: ":me!user@example.org PRIVMSG me :\u{01}LAGCHECK \(payload)\u{01}", on: client))

		client.receiveCTCPQuery(message, text: "LAGCHECK \(payload)")

		let sent = client.sentLines.compactMap { $0 as? String }
		#expect(sent.contains { $0.hasPrefix("PRIVMSG #chat :") })
	}

	@Test("A field with invalid percent-encoding is dropped")
	func invalidPercentEncodingIsDropped() {
		#expect(IRCCTCPPolicy.formData("a=%zz&b=2") == ["b": "2"])
	}
}
