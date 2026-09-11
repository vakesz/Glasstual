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
		as lineType: LogLineType
	) -> [String] {
		var cursor = IRCLineCursor(NSAttributedString(string: text))
		var pieces: [String] = []

		while pieces.count < 200,
		      let piece = cursor.nextLine(forChannel: target, on: client, with: lineType)
		{
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

	/** `TARGMAX=JOIN:n` caps how many channels one JOIN may name. No limit at
	 all leaves the batch bounded only by the line budget, because a channel
	 list is core JOIN syntax rather than something a server has to advertise —
	 which is why zero here means "as many as fit" while the same zero for
	 PRIVMSG means "one target per line". */
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

	// MARK: - The assembled line

	/** RFC 1459 §2.3: a line is at most 512 bytes with its CR LF, so 510 for
	 the rest. Nothing measured the finished line, so a long enough command left
	 the client over the limit and the server cut it wherever it landed. */
	@Test("An over-long line is cut to the protocol's body length")
	func assembledLinesAreCutToTheBodyLength() {
		let line = "PRIVMSG #chan :" + String(repeating: "a", count: 600)
		let enforced = IRCProtocolLimits.enforcedWireLine(line)

		#expect(enforced.utf8.count == IRCProtocolLimits.maximumBodyLength)
		#expect(line.hasPrefix(enforced))
	}

	/** The enforcement used to pin 510 while everything that sized the text
	 going into the line — the message splitter, the JOIN batcher, the parameter
	 budget — read `LINELEN`. On a server carrying 1024 the last stop before the
	 socket therefore cut text the server would have taken. */
	@Test("The cut follows the length the server advertised")
	func theCutFollowsTheAdvertisedLineLength() {
		let line = "PRIVMSG #chan :" + String(repeating: "a", count: 2000)
		let raised = IRCProtocolLimits.bodyLimit(forAdvertisedLineLength: 1024)

		#expect(raised == 1022)
		#expect(IRCProtocolLimits.enforcedWireLine(line, bodyLimit: raised).utf8.count == raised)
		// A server that advertised nothing, or nonsense, keeps the RFC's budget.
		#expect(IRCProtocolLimits.bodyLimit(forAdvertisedLineLength: 0) == IRCProtocolLimits.maximumBodyLength)
		#expect(IRCProtocolLimits.bodyLimit(forAdvertisedLineLength: 1) == IRCProtocolLimits.maximumBodyLength)
		// And one that advertises more than is believable is clamped, not trusted.
		#expect(
			IRCProtocolLimits.bodyLimit(forAdvertisedLineLength: 1_000_000)
				== IRCProtocolLimits.maximumServerLineLength - IRCProtocolLimits.lineTerminatorLength
		)
	}

	/// The socket starts on the RFC's 512 and takes the server's `LINELEN` from
	/// 005, and a reconnect goes back to the default because the next server has
	/// said nothing yet.
	@Test("The connection's line length follows ISUPPORT and resets with it")
	func connectionLineLengthFollowsISupport() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "user"])
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection

		#expect(connection.maximumLineLength == 512)

		let message = try #require(Message(line: ":irc.example.net 005 me LINELEN=1024 :are supported", on: client))
		client.receiveNumericReply(message)

		#expect(connection.maximumLineLength == 1024)

		connection.resetState()

		#expect(connection.maximumLineLength == 512)
	}

	/** The log is not where the user is looking. Text they typed is gone from
	 what the server saw, and only the unified log ever said so. */
	@Test("A cut line is reported where the user can see it")
	func aCutLineIsReportedInTheTranscript() {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "user"])
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection

		connection.sendLine("PRIVMSG #chan :" + String(repeating: "a", count: 600))

		let bodies = client.printedLines.compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains {
			$0 == ConnectionSafetyStrings.Wire.lineTruncated(
				sentByteCount: 615,
				limit: IRCProtocolLimits.maximumBodyLength
			)
		})
	}

	/// A line that fits says nothing at all: every line would otherwise be
	/// reported as having been trimmed to itself.
	@Test("A line that fits is not reported")
	func aLineThatFitsIsNotReported() {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "user"])
		let connection = Connection(config: IRCConnectionConfig(), onClient: client)
		client.socket = connection

		connection.sendLine("PRIVMSG #chan :hello")

		#expect(client.printedLines.count == 0)
	}

	@Test("A line that already fits is left alone")
	func linesWithinTheBudgetAreUnchanged() {
		let line = "PRIVMSG #chan :hello"

		#expect(IRCProtocolLimits.enforcedWireLine(line) == line)
	}

	/// The cut lands on a character boundary: half a UTF-8 sequence is not text
	/// on any server, and the encoder would refuse it or the peer would draw a
	/// replacement character.
	@Test("The cut never splits a character")
	func truncationLandsOnACharacterBoundary() {
		let line = "PRIVMSG #chan :" + String(repeating: "\u{1F4AC}", count: 200)
		let enforced = IRCProtocolLimits.enforcedWireLine(line)

		#expect(enforced.utf8.count <= IRCProtocolLimits.maximumBodyLength)
		#expect(enforced.utf8.count > IRCProtocolLimits.maximumBodyLength - 4)
		#expect(enforced.hasSuffix("\u{1F4AC}"))
	}

	/// IRCv3 budgets the tag section separately, so a tagged line gets its own
	/// 510 bytes for the command that follows the tags.
	@Test("Tags are budgeted apart from the body")
	func tagsAreBudgetedApartFromTheBody() {
		let tags = "@time=2026-08-26T12:00:00.000Z "
		let enforced = IRCProtocolLimits.enforcedWireLine(tags + String(repeating: "a", count: 600))

		#expect(enforced.hasPrefix(tags))
		#expect(enforced.utf8.count == tags.utf8.count + IRCProtocolLimits.maximumBodyLength)
	}

	/// Half a tag is not a tag, so an oversized tag section loses whole ones.
	@Test("An oversized tag section drops whole tags")
	func oversizedTagSectionsDropWholeTags() {
		let tags = (0 ..< 300).map { "t\($0)=" + String(repeating: "v", count: 20) }
		let enforced = IRCProtocolLimits.enforcedWireLine("@" + tags.joined(separator: ";") + " PING token")
		let tagSection = String(enforced.prefix(while: { $0 != " " }))

		#expect(enforced.hasSuffix(" PING token"))
		#expect(tagSection.utf8.count < IRCProtocolLimits.maximumClientTagLength)
		#expect(tagSection.hasPrefix("@t0=vvv"))
		#expect(tagSection.components(separatedBy: ";").allSatisfy { $0.hasSuffix("vvvvv") })
	}
}
