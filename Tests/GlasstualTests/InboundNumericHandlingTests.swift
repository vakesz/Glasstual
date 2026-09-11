/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** What the numeric handlers make of replies whose shape the specifications
 leave open: a NAMES token that is only prefixes, a quiet list with an extra
 field, a timestamp the server made up, and the four-parameter spelling of
 RPL_WHOISACTUALLY that half the ircds send. */
@MainActor
@Suite("Inbound numeric handling")
struct InboundNumericHandlingTests {
	private func client(nickname: String = "me") -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": nickname, "username": nickname])
	}

	private func joinedChannel(_ name: String, on client: GLTTestClient) throws -> Channel {
		let channel = try #require(client.findChannelOrCreate(name))

		channel.activate()

		return channel
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		if message.commandNumeric > 0 {
			client.receiveNumericReply(message)
		} else {
			client.forwardsProcessedMessages = true
			client.processIncomingMessage(message)
		}
	}

	private func printedBodies(on client: GLTTestClient, forCommand command: String) -> [String] {
		(client.printedLines as NSArray).compactMap { line in
			guard let line = line as? [String: Any], line["command"] as? String == command else {
				return nil
			}

			return line["messageBody"] as? String
		}
	}

	// MARK: - RPL_NAMREPLY

	/// `353 me = #chan :@ alice` — the prefix and the nickname arrived as two
	/// tokens. The first names nobody, and taking it anyway put a member and a
	/// directory user under the empty nickname.
	@Test("A NAMES token of nothing but prefixes is dropped")
	func namesTokenOfOnlyPrefixesIsDropped() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :@ alice", on: client)

		#expect(channel.numberOfMembers == 1)
		#expect(channel.memberExists("alice"))
		#expect(client.userExists("") == false)
		#expect(client.numberOfUsers == 1)
	}

	/// The NAMES reply is the server's own list, so it is the truth about
	/// everyone in it — including the member a JOIN already created.
	@Test("A NAMES entry sets the prefixes of a member that already exists")
	func namesUpdatesTheModesOfAnExistingMember() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)

		#expect(try #require(channel.findMember("alice")).modes.letters.isEmpty)

		try receive(":irc.example.net 353 me = #chan :@alice", on: client)

		#expect(try #require(channel.findMember("alice")).modes.letters == "o")
		#expect(try #require(channel.findMember("alice")).mark == "@")
	}

	/// RFC 1459 6.2's WHO flag field carries the person's channel status, and
	/// it used to reach a member only on the way in: an op the client had
	/// already seen join kept no mark at all.
	@Test("A WHO reply sets the prefixes of a member that already exists")
	func whoReplyUpdatesTheModesOfAnExistingMember() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)
		try receive(
			":irc.example.net 352 me #chan ali example.org irc.example.net alice H@ :0 Alice",
			on: client
		)

		#expect(try #require(channel.findMember("alice")).modes.letters == "o")
	}

	/// Without `multi-prefix` the flag field carries only the highest prefix,
	/// so it may add to what the member holds but never take the rest away.
	@Test("A WHO reply without multi-prefix does not drop the modes it omits")
	func whoReplyKeepsModesItCannotReport() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :@+alice", on: client)
		try receive(
			":irc.example.net 352 me #chan ali example.org irc.example.net alice H@ :0 Alice",
			on: client
		)

		#expect(try #require(channel.findMember("alice")).modes.letters == "ov")
	}

	// MARK: - Mode lists

	/// RPL_QUIETLIST writes the mode letter between the channel and the mask,
	/// and nothing else does. Counting parameters to find it only ever worked
	/// for the six-parameter shape.
	@Test("A quiet list reads its mask from the reply's shape, not its length")
	func quietListReadsTheMaskWhateverTheParameterCount() throws {
		let client = client()
		client.recordedOutput.showsAccessListSheet = true

		try receive(":irc.example.net 728 me #chan q short!*@* alice 1700000000", on: client)
		try receive(":irc.example.net 728 me #chan q bare!*@*", on: client)
		try receive(":irc.example.net 728 me #chan q long!*@* alice 1700000000 extra", on: client)

		let masks = client.recordedOutput.accessListEntries.map(\.mask)

		#expect(masks == ["short!*@*", "bare!*@*", "long!*@*"])
	}

	/** The entry used to reach the window carrying nothing but the mask, so
	 whichever access list happened to be current took it: a window open on one
	 channel's bans filled with another channel's. The channel and the mode
	 letter travel with it now. */
	@Test("A list entry names the channel and the mode it belongs to")
	func listEntriesNameTheirChannelAndMode() throws {
		let client = client()
		client.recordedOutput.showsAccessListSheet = true
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e INVEX=I")

		try receive(":irc.example.net 367 me #bans *!*@one.example alice 1700000000", on: client)
		try receive(":irc.example.net 348 me #excepts *!*@two.example bob 1700000000", on: client)
		try receive(":irc.example.net 346 me #invites *!*@three.example carol 1700000000", on: client)
		try receive(":irc.example.net 728 me #quiets q *!*@four.example dave 1700000000", on: client)

		let routes = client.recordedOutput.accessListEntries.map { "\($0.channelName) +\($0.modeSymbol)" }

		#expect(routes == ["#bans +b", "#excepts +e", "#invites +I", "#quiets +q"])
	}

	/// The end of a list names the same channel and mode its entries did, so a
	/// window that took none of them does not take the end of it either.
	@Test("The end of a list names the channel and the mode too")
	func endOfListNamesItsChannelAndMode() throws {
		let client = client()
		client.recordedOutput.showsAccessListSheet = true
		client.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+ EXCEPTS=e")

		try receive(":irc.example.net 368 me #bans :End of channel ban list", on: client)
		try receive(":irc.example.net 349 me #excepts :End of channel exception list", on: client)
		try receive(":irc.example.net 729 me #quiets q :End of channel quiet list", on: client)

		#expect(client.recordedOutput.accessListFinishes == ["#bans +b", "#excepts +e", "#quiets +q"])
	}

	/// Every trailing timestamp on the wire is server-supplied text, and
	/// `TimeInterval(param) ?? 0` read an unparsable one as 1970 and a
	/// forty-digit one as a date past the year 3000.
	@Test("An unreadable list timestamp leaves the entry undated")
	func unreadableListTimestampLeavesTheEntryUndated() throws {
		let client = client()
		client.recordedOutput.showsAccessListSheet = true

		try receive(
			":irc.example.net 367 me #chan bad!*@* alice 99999999999999999999999999",
			on: client
		)
		try receive(":irc.example.net 367 me #chan worse!*@* alice notatimestamp", on: client)

		#expect(client.recordedOutput.accessListEntries.count == 2)
		#expect(client.recordedOutput.accessListEntries.allSatisfy { $0.date == nil })
	}

	@Test("An unreadable topic timestamp is left out rather than printed as 1970")
	func unreadableTopicTimestampIsLeftOut() throws {
		let client = client()
		_ = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 333 me #chan alice!ali@example.org notatimestamp", on: client)

		let bodies = printedBodies(on: client, forCommand: "333")

		#expect(bodies.isEmpty == false)
		#expect(bodies.allSatisfy { $0.contains("1970") == false })
	}

	@Test("An unreadable sign-on timestamp is left out of the WHOIS line")
	func unreadableSignOnTimestampIsLeftOut() throws {
		let client = client()

		try receive(":irc.example.net 317 me alice 300 notatimestamp :seconds idle", on: client)

		let bodies = printedBodies(on: client, forCommand: "317")

		#expect(bodies.isEmpty == false)
		#expect(bodies.allSatisfy { $0.contains("1970") == false })
	}

	// MARK: - RPL_WHOISACTUALLY

	/** InspIRCd and Charybdis send `338 <me> <nick> <ip> :is actually using
	 host`, one parameter shorter than the ircu spelling the handler knew. It
	 answered "handled" and printed nothing, so the reply vanished. */
	@Test("A four-parameter RPL_WHOISACTUALLY still reaches the transcript")
	func fourParameterWhoisActuallyIsPrinted() throws {
		let client = client()

		try receive(":irc.example.net 338 me alice 192.0.2.1 :is actually using host", on: client)

		#expect(printedBodies(on: client, forCommand: "338").isEmpty == false)
	}

	// MARK: - Plugin subscription

	/** A plugin subscribes to the wire token, which is always three digits.
	 `String(commandNumeric)` drops the leading zeros, so nothing a plugin
	 subscribed to below 100 could ever match what the client compared. */
	@Test("A numeric keeps the leading zeros a plugin subscribed to")
	func numericKeepsItsLeadingZeros() throws {
		let client = client()
		let message = try #require(Message(line: ":irc.example.net 001 me :Welcome", on: client))

		#expect(message.command == "001")
		#expect(message.commandNumeric == 1)
		#expect(String(message.commandNumeric) != message.command)
	}

	// MARK: - ISUPPORT

	/** A member carries the prefix table it was stamped with. A second 005 —
	 which a bouncer sends on attach — changes how everyone already in a
	 channel ranks, and only a preferences reload ever re-stamped them. */
	@Test("A PREFIX change re-stamps and re-sorts the members already in a channel")
	func prefixChangeRestampsAndResortsMembers() throws {
		let client = client()

		try receive(":irc.example.net 005 me PREFIX=(ov)@+ :are supported by this server", on: client)

		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :@alice +bob carol", on: client)

		let memberInfo = try #require(channel.memberInfo)

		#expect(memberInfo.memberList.map(\.user.nickname) == ["alice", "bob", "carol"])

		/* The same two modes, ranked the other way round. */
		try receive(":irc.example.net 005 me PREFIX=(vo)+@ :are supported by this server", on: client)

		#expect(memberInfo.memberList.map(\.user.nickname) == ["bob", "alice", "carol"])
		#expect(try #require(channel.findMember("bob")).mark == "+")
		#expect(try #require(channel.findMember("alice")).mark == "@")
	}
}
