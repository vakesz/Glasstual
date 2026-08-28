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

/// RFC 2812 §2.3: "IRC messages are always lines of characters terminated with
/// a CR-LF pair, and these messages SHALL NOT exceed 512 characters in length,
/// counting all characters including the trailing CR-LF. Thus, there are 510
/// characters maximum allowed for the command and its parameters."
///
/// The server relays a client's PRIVMSG with the sender's prefix in front of
/// it, so an outgoing message has to leave room for a prefix it never writes
/// itself.
@Suite("Outbound line limits")
@MainActor
struct IRCSpecOutboundLimitsTests {
	private static let hostmask = "me!user@example.org"

	private func client(lineLength: UInt = 0) -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "user"])

		client.userHostmask = Self.hostmask

		if lineLength > 0 {
			client.supportInfo.processConfigurationData("LINELEN=\(lineLength)")
		}

		return client
	}

	/// The line the server would relay for a message this client sends.
	private func relayedLine(_ body: String, target: String, command: String) -> String {
		":\(Self.hostmask) \(command) \(target) :\(body)\r\n"
	}

	private func split(
		_ text: String,
		target: String,
		on client: GLTTestClient,
		as lineType: TVCLogLineType
	) -> [String] {
		let remaining = NSMutableAttributedString(string: text)
		var pieces: [String] = []

		while remaining.length > 0, pieces.count < 200 {
			let lengthBefore = remaining.length
			let piece = remaining.stringFormatted(forChannel: target, on: client, with: lineType)

			guard remaining.length < lengthBefore else {
				break
			}

			pieces.append(piece)
		}

		return pieces
	}

	/// Every piece a long PRIVMSG is split into has to fit in 512 bytes once
	/// the server has put the sender's prefix and the CR-LF back on.
	@Test(
		"RFC 2812 §2.3: no relayed PRIVMSG exceeds 512 bytes",
		arguments: [200, 510, 512, 1000, 5000]
	)
	func splitPrivateMessagesFitTheLineLimit(_ length: Int) {
		let client = client()
		let pieces = split(
			String(repeating: "a", count: length),
			target: "#channel",
			on: client,
			as: .privateMessage
		)

		#expect(pieces.isEmpty == false)

		for piece in pieces {
			#expect(relayedLine(piece, target: "#channel", command: "PRIVMSG").utf8.count <= 512)
		}
	}

	/// The same budget applies to a NOTICE and to an ACTION, which carries its
	/// CTCP framing inside the message body.
	@Test("RFC 2812 §2.3: notices and actions share the budget")
	func noticesAndActionsShareTheBudget() {
		let client = client()
		let text = String(repeating: "b", count: 2000)

		for piece in split(text, target: "#channel", on: client, as: .notice) {
			#expect(relayedLine(piece, target: "#channel", command: "NOTICE").utf8.count <= 512)
		}

		for piece in split(text, target: "#channel", on: client, as: .action) {
			let framed = CTCPPayload.action(piece)

			#expect(relayedLine(framed, target: "#channel", command: "PRIVMSG").utf8.count <= 512)
		}
	}

	/// The limit is a byte budget, not a character count: multi-byte text has
	/// to be measured as it will be encoded.
	@Test("RFC 2812 §2.3: the budget counts bytes, not characters")
	func theBudgetCountsBytes() {
		let client = client()
		let pieces = split(
			String(repeating: "é", count: 600),
			target: "#channel",
			on: client,
			as: .privateMessage
		)

		#expect(pieces.count > 1)

		for piece in pieces {
			#expect(relayedLine(piece, target: "#channel", command: "PRIVMSG").utf8.count <= 512)
		}
	}

	/// Splitting never cuts a character in half: half of a multi-byte
	/// character is not text the receiver can decode.
	@Test("Splitting never cuts a character in half")
	func splittingNeverCutsACharacter() {
		let client = client()
		let pieces = split(
			String(repeating: "🎉", count: 400),
			target: "#channel",
			on: client,
			as: .privateMessage
		)

		#expect(pieces.isEmpty == false)
		#expect(pieces.joined() == String(repeating: "🎉", count: 400))
	}

	/// The budget has to leave room for a prefix the client never sends, so a
	/// long hostmask leaves less room for the message.
	@Test("A longer hostmask leaves less room for the message")
	func aLongerHostmaskLeavesLessRoom() throws {
		let shortHostmask = client()
		let longHostmask = client()

		longHostmask.userHostmask = "me!" + String(repeating: "u", count: 60) + "@example.org"

		let text = String(repeating: "c", count: 2000)
		let shortPieces = split(text, target: "#channel", on: shortHostmask, as: .privateMessage)
		let longPieces = split(text, target: "#channel", on: longHostmask, as: .privateMessage)

		let shortFirst = try #require(shortPieces.first)
		let longFirst = try #require(longPieces.first)

		#expect(shortFirst.count > longFirst.count)
	}

	/// modern.ircdocs.horse `LINELEN`: a server may raise the line limit, and
	/// the client is allowed to use the extra room.
	@Test("ISUPPORT LINELEN raises the budget")
	func lineLengthTokenRaisesTheBudget() {
		let defaultBudget = client()
		let raisedBudget = client(lineLength: 1024)
		let text = String(repeating: "d", count: 3000)

		let defaultPieces = split(text, target: "#channel", on: defaultBudget, as: .privateMessage)
		let raisedPieces = split(text, target: "#channel", on: raisedBudget, as: .privateMessage)

		#expect(raisedPieces.count < defaultPieces.count)
	}

	// MARK: - JOIN batching

	/// RFC 2812 §3.2.1: `JOIN <channel>{,<channel>} [<key>{,<key>}]`. The whole
	/// command still has to fit one line, so a long autojoin list becomes
	/// several JOINs rather than one truncated one.
	@Test("A long JOIN list is split into lines that fit")
	func longJoinListsAreSplit() {
		let targets = (0 ..< 200).map { IRCJoinBatching.Target(name: "#channel-\($0)") }
		let batches = IRCJoinBatching.batches(for: targets)

		#expect(batches.count > 1)
		#expect(batches.flatMap(\.channels).count == targets.count)

		for batch in batches {
			let line = "JOIN " + batch.channels.joined(separator: ",")

			#expect(line.utf8.count <= IRCProtocolLimits.maximumBodyLength)
		}
	}

	/// Keys are positional, so a keyed channel may not be batched with a
	/// keyless one: the server would hand the key to the wrong channel.
	@Test("Keyed and keyless channels are never batched together")
	func keyedChannelsAreBatchedSeparately() {
		let targets = [
			IRCJoinBatching.Target(name: "#open"),
			IRCJoinBatching.Target(name: "#secret", key: "hunter2"),
			IRCJoinBatching.Target(name: "#alsoopen"),
		]
		let batches = IRCJoinBatching.batches(for: targets)

		for batch in batches {
			#expect(batch.keys.isEmpty || batch.keys.count == batch.channels.count)
		}

		#expect(batches.contains { $0.channels == ["#open", "#alsoopen"] && $0.keys.isEmpty })
		#expect(batches.contains { $0.channels == ["#secret"] && $0.keys == ["hunter2"] })
	}

	/// `TARGMAX=JOIN:n` caps how many channels one JOIN may name, and an empty
	/// limit means the server set none.
	@Test("TARGMAX caps the channels in one JOIN")
	func targetMaximumCapsOneJoin() {
		let targets = (0 ..< 10).map { IRCJoinBatching.Target(name: "#c\($0)") }

		#expect(IRCJoinBatching.batches(for: targets, maximumTargets: 4).allSatisfy { $0.channels.count <= 4 })
		#expect(IRCJoinBatching.batches(for: targets, maximumTargets: 0).count == 1)
	}

	// MARK: - The serialiser

	/// RFC 1459 §2.3.1: only the last parameter may carry spaces, and it needs
	/// the `:` that says so. A parameter with no space needs no colon.
	@Test("Only a parameter that needs the colon gets one")
	func onlyTheTrailingParameterGetsAColon() {
		#expect(SendingMessage.string(command: "JOIN", arguments: ["#chan"]) == "JOIN #chan")
		#expect(
			SendingMessage.string(command: "PRIVMSG", arguments: ["#chan", "hello world"])
				== "PRIVMSG #chan :hello world"
		)
		#expect(
			SendingMessage.string(command: "PRIVMSG", arguments: ["#chan", ":-)"])
				== "PRIVMSG #chan ::-)"
		)
	}

	/// The command a client sends is upper case on the wire, which RFC 1459
	/// §2.3 allows for and every server expects.
	@Test("RFC 1459 §2.3: outgoing commands are upper-cased")
	func outgoingCommandsAreUpperCased() {
		#expect(SendingMessage.string(command: "privmsg", arguments: ["#chan", "hi"]) == "PRIVMSG #chan :hi")
	}
}
