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

/// Channel membership bookkeeping: RFC 2812 §3.2 (JOIN, PART, KICK), §3.1.7
/// (QUIT), §3.1.2 (NICK) and §5.2 (RPL_NAMREPLY / RPL_ENDOFNAMES), plus the
/// IRCv3 `multi-prefix`, `userhost-in-names` and `extended-join` extensions
/// that change what those messages carry.
@Suite("Channel membership")
@MainActor
struct IRCSpecMembershipTests {
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

	private func member(_ nickname: String, in channel: Channel) -> ChannelUser? {
		channel.findMember(nickname)
	}

	// MARK: - JOIN

	/// RFC 2812 §3.2.1: a JOIN from another user adds them to the channel, and
	/// the prefix carries their user and host.
	@Test("JOIN adds the sender to the member list")
	func joinAddsAMember() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)

		let alice = try #require(member("alice", in: channel))

		#expect(channel.memberExists("alice"))
		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
		#expect(alice.modes.letters.isEmpty)
	}

	/// A JOIN naming a channel the client is not in says nothing about any
	/// member list it holds.
	@Test("JOIN for an unknown channel changes nothing")
	func joinForAnUnknownChannelIsIgnored() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #other", on: client)

		#expect(channel.numberOfMembers == 0)
	}

	/// IRCv3 `extended-join`: `JOIN <channel> <account> :<realname>`. The
	/// account is `*` when the user is not identified.
	@Test("extended-join carries the account and real name")
	func extendedJoinCarriesAccountAndRealName() throws {
		let client = client()

		client.enableCapability(.extendedJoin)

		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan aliceacct :Alice Example", on: client)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.user.account == "aliceacct")
		#expect(alice.user.realName == "Alice Example")
	}

	/// `extended-join`: "If the user is not authenticated, the account name is
	/// the literal `*`", which is an absence, not an account called `*`.
	@Test("extended-join reads * as no account")
	func extendedJoinReadsStarAsNoAccount() throws {
		let client = client()

		client.enableCapability(.extendedJoin)

		let channel = try joinedChannel("#chan", on: client)

		try receive(":bob!b@example.org JOIN #chan * :Bob Example", on: client)

		let bob = try #require(member("bob", in: channel))

		#expect(bob.user.account == nil)
		#expect(bob.user.realName == "Bob Example")
	}

	/// Without the capability negotiated the extra parameters are not there to
	/// be read, so a server sending them anyway must not be believed.
	@Test("extended-join parameters are ignored without the capability")
	func extendedJoinIsIgnoredWithoutTheCapability() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan aliceacct :Alice Example", on: client)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.user.account == nil)
	}

	// MARK: - PART, KICK, QUIT

	/// RFC 2812 §3.2.2: a PART removes the sender from that channel only.
	@Test("PART removes the sender from that channel alone")
	func partRemovesTheSender() throws {
		let client = client()
		let first = try joinedChannel("#one", on: client)
		let second = try joinedChannel("#two", on: client)

		try receive(":alice!ali@example.org JOIN #one", on: client)
		try receive(":alice!ali@example.org JOIN #two", on: client)
		try receive(":alice!ali@example.org PART #one :bye", on: client)

		#expect(first.memberExists("alice") == false)
		#expect(second.memberExists("alice"))
	}

	/// RFC 2812 §3.2.8: a KICK removes the *target*, who is the second
	/// parameter, not the operator who sent it.
	@Test("KICK removes the target, not the sender")
	func kickRemovesTheTarget() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)
		try receive(":op!o@example.org JOIN #chan", on: client)
		try receive(":op!o@example.org KICK #chan alice :go away", on: client)

		#expect(channel.memberExists("alice") == false)
		#expect(channel.memberExists("op"))
	}

	/// RFC 2812 §3.1.7: a QUIT removes the user from every channel at once —
	/// the server sends it only to the channels that share the user, and never
	/// repeats it per channel.
	@Test("QUIT removes the user from every channel")
	func quitRemovesFromEveryChannel() throws {
		let client = client()
		let first = try joinedChannel("#one", on: client)
		let second = try joinedChannel("#two", on: client)

		try receive(":alice!ali@example.org JOIN #one", on: client)
		try receive(":alice!ali@example.org JOIN #two", on: client)

		#expect(first.memberExists("alice"))
		#expect(second.memberExists("alice"))

		try receive(":alice!ali@example.org QUIT :Client Quit", on: client)

		#expect(first.memberExists("alice") == false)
		#expect(second.memberExists("alice") == false)
	}

	// MARK: - NICK

	/// RFC 2812 §3.1.2: a NICK renames the user everywhere, keeping whatever
	/// channel privileges they held.
	@Test("NICK renames the member and keeps its channel modes")
	func nickRenamesAndKeepsModes() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)
		try receive(":op!o@example.org MODE #chan +o alice", on: client)

		#expect(try #require(member("alice", in: channel)).modes.letters == "o")

		try receive(":alice!ali@example.org NICK :alice2", on: client)

		#expect(channel.memberExists("alice") == false)

		let renamed = try #require(member("alice2", in: channel))

		#expect(renamed.modes.letters == "o")
	}

	// MARK: - MODE against the member list

	/// RFC 2811 §4.1: a prefix mode change moves the member's mark, and the
	/// mark comes from ISUPPORT `PREFIX`.
	@Test("A prefix MODE change updates the member's mark")
	func prefixModeChangeUpdatesTheMark() throws {
		let client = client()

		client.supportInfo.processConfigurationData("PREFIX=(ohv)@%+ CHANMODES=b,k,l,imnpst")

		let channel = try joinedChannel("#chan", on: client)

		try receive(":alice!ali@example.org JOIN #chan", on: client)
		try receive(":op!o@example.org MODE #chan +v alice", on: client)

		#expect(try #require(member("alice", in: channel)).mark == "+")

		try receive(":op!o@example.org MODE #chan +o alice", on: client)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.mark == "@")
		#expect(alice.modes.letters == "ov")

		try receive(":op!o@example.org MODE #chan -o alice", on: client)

		#expect(try #require(member("alice", in: channel)).mark == "+")
	}

	// MARK: - NAMES

	/// RFC 2812 §5.2 RPL_NAMREPLY: `<client> <symbol> <channel> :[prefix]<nick>{ [prefix]<nick>}`.
	@Test("RPL_NAMREPLY adds every name in the list")
	func namesReplyAddsEveryName() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :alice @bob +carol", on: client)

		#expect(channel.numberOfMembers == 3)
		#expect(try #require(member("alice", in: channel)).modes.letters.isEmpty)
		#expect(try #require(member("bob", in: channel)).modes.letters == "o")
		#expect(try #require(member("carol", in: channel)).modes.letters == "v")
	}

	/// IRCv3 `multi-prefix`: every prefix the member holds is listed, highest
	/// first, and all of them have to be read rather than only the first.
	@Test("multi-prefix: every prefix in a NAMES entry is read")
	func multiPrefixNamesEntriesAreRead() throws {
		let client = client()

		client.supportInfo.processConfigurationData("PREFIX=(qaohv)~&@%+")
		client.enableCapability(.multiPrefix)

		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :@+alice ~&@bob %carol", on: client)

		#expect(try #require(member("alice", in: channel)).modes.letters == "ov")
		#expect(try #require(member("bob", in: channel)).modes.letters == "qao")
		#expect(try #require(member("bob", in: channel)).mark == "~")
		#expect(try #require(member("carol", in: channel)).modes.letters == "h")
	}

	/// IRCv3 `userhost-in-names`: each entry is a full `nick!user@host`, and
	/// only the nickname names the member.
	@Test("userhost-in-names: a full hostmask entry still names one member")
	func userhostInNamesEntriesAreSplit() throws {
		let client = client()

		client.enableCapability(.userhostInNames)

		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :@alice!ali@example.org bob!b@example.net", on: client)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.modes.letters == "o")
		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")

		let bob = try #require(member("bob", in: channel))

		#expect(bob.user.username == "b")
		#expect(bob.user.address == "example.net")
	}

	/// A names list may be split over several 353s; RPL_ENDOFNAMES (366) is
	/// what says the list is complete.
	@Test("RPL_ENDOFNAMES closes a list split over several replies")
	func endOfNamesClosesTheList() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :alice bob", on: client)
		try receive(":irc.example.net 353 me = #chan :carol", on: client)

		#expect(channel.channelNamesReceived == false)
		#expect(channel.numberOfMembers == 3)

		try receive(":irc.example.net 366 me #chan :End of /NAMES list", on: client)

		#expect(channel.channelNamesReceived)
	}

	/// Once the list is closed a further 353 belongs to a request the client
	/// did not make and must not silently re-populate the member list.
	@Test("A NAMES reply after RPL_ENDOFNAMES does not re-populate the list")
	func namesAfterEndOfNamesIsIgnored() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :alice", on: client)
		try receive(":irc.example.net 366 me #chan :End of /NAMES list", on: client)
		try receive(":irc.example.net 353 me = #chan :bob", on: client)

		#expect(channel.memberExists("bob") == false)
	}

	/// RFC 1459 §2.3: the names are separated by one or more spaces, and a
	/// trailing space is not an extra, empty member.
	@Test("RFC 1459 §2.3: extra spaces in a NAMES list are not members")
	func extraSpacesInNamesAreNotMembers() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me = #chan :alice  bob ", on: client)

		#expect(channel.numberOfMembers == 2)
	}

	/// The names numerics carry a fixed parameter count; a short reply is
	/// malformed and must not be read at an offset that would take a nickname
	/// from the wrong field.
	@Test("A short NAMES numeric is ignored")
	func shortNamesNumericsAreIgnored() throws {
		let client = client()
		let channel = try joinedChannel("#chan", on: client)

		try receive(":irc.example.net 353 me #chan :alice", on: client)

		#expect(channel.numberOfMembers == 0)
		#expect(channel.channelNamesReceived == false)
	}
}
