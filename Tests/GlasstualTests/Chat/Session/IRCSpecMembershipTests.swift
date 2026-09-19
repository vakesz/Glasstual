// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
	private func session(nickname: String = "me") -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": nickname, "username": nickname])
	}

	private func joinedChannel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))

		channel.activate()

		return channel
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))

		if message.commandNumeric > 0 {
			session.receiveNumericReply(message)
		} else {
			session.forwardsProcessedMessages = true
			session.processIncomingMessage(message)
		}
	}

	private func member(_ nickname: String, in channel: Conversation) -> Member? {
		channel.findMember(nickname)
	}

	// MARK: - JOIN

	/// RFC 2812 §3.2.1: a JOIN from another user adds them to the channel, and
	/// the prefix carries their user and host.
	@Test("JOIN adds the sender to the member list")
	func joinAddsAMember() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan", on: session)

		let alice = try #require(member("alice", in: channel))

		#expect(channel.memberExists("alice"))
		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
		#expect(alice.modes.letters.isEmpty)
	}

	/// A JOIN naming a channel the session is not in says nothing about any
	/// member list it holds.
	@Test("JOIN for an unknown channel changes nothing")
	func joinForAnUnknownChannelIsIgnored() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #other", on: session)

		#expect(channel.numberOfMembers == 0)
	}

	/// IRCv3 `extended-join`: `JOIN <channel> <account> :<realname>`. The
	/// account is `*` when the user is not identified.
	@Test("extended-join carries the account and real name")
	func extendedJoinCarriesAccountAndRealName() throws {
		let session = session()

		session.enableCapability(.extendedJoin)

		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan aliceacct :Alice Example", on: session)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.user.account == "aliceacct")
		#expect(alice.user.realName == "Alice Example")
	}

	/// `extended-join`: "If the user is not authenticated, the account name is
	/// the literal `*`", which is an absence, not an account called `*`.
	@Test("extended-join reads * as no account")
	func extendedJoinReadsStarAsNoAccount() throws {
		let session = session()

		session.enableCapability(.extendedJoin)

		let channel = try joinedChannel("#chan", on: session)

		try receive(":bob!b@example.org JOIN #chan * :Bob Example", on: session)

		let bob = try #require(member("bob", in: channel))

		#expect(bob.user.account == nil)
		#expect(bob.user.realName == "Bob Example")
	}

	/// Without the capability negotiated the extra parameters are not there to
	/// be read, so a server sending them anyway must not be believed.
	@Test("extended-join parameters are ignored without the capability")
	func extendedJoinIsIgnoredWithoutTheCapability() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan aliceacct :Alice Example", on: session)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.user.account == nil)
	}

	// MARK: - PART, KICK, QUIT

	/// RFC 2812 §3.2.2: a PART removes the sender from that channel only.
	@Test("PART removes the sender from that channel alone")
	func partRemovesTheSender() throws {
		let session = session()
		let first = try joinedChannel("#one", on: session)
		let second = try joinedChannel("#two", on: session)

		try receive(":alice!ali@example.org JOIN #one", on: session)
		try receive(":alice!ali@example.org JOIN #two", on: session)
		try receive(":alice!ali@example.org PART #one :bye", on: session)

		#expect(first.memberExists("alice") == false)
		#expect(second.memberExists("alice"))
	}

	/// RFC 2812 §3.2.8: a KICK removes the *target*, who is the second
	/// parameter, not the operator who sent it.
	@Test("KICK removes the target, not the sender")
	func kickRemovesTheTarget() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan", on: session)
		try receive(":op!o@example.org JOIN #chan", on: session)
		try receive(":op!o@example.org KICK #chan alice :go away", on: session)

		#expect(channel.memberExists("alice") == false)
		#expect(channel.memberExists("op"))
	}

	/// RFC 2812 §3.1.7: a QUIT removes the user from every channel at once —
	/// the server sends it only to the channels that share the user, and never
	/// repeats it per channel.
	@Test("QUIT removes the user from every channel")
	func quitRemovesFromEveryChannel() throws {
		let session = session()
		let first = try joinedChannel("#one", on: session)
		let second = try joinedChannel("#two", on: session)

		try receive(":alice!ali@example.org JOIN #one", on: session)
		try receive(":alice!ali@example.org JOIN #two", on: session)

		#expect(first.memberExists("alice"))
		#expect(second.memberExists("alice"))

		try receive(":alice!ali@example.org QUIT :Client Quit", on: session)

		#expect(first.memberExists("alice") == false)
		#expect(second.memberExists("alice") == false)
	}

	// MARK: - NICK

	/// RFC 2812 §3.1.2: a NICK renames the user everywhere, keeping whatever
	/// channel privileges they held.
	@Test("NICK renames the member and keeps its channel modes")
	func nickRenamesAndKeepsModes() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan", on: session)
		try receive(":op!o@example.org MODE #chan +o alice", on: session)

		#expect(try #require(member("alice", in: channel)).modes.letters == "o")

		try receive(":alice!ali@example.org NICK :alice2", on: session)

		#expect(channel.memberExists("alice") == false)

		let renamed = try #require(member("alice2", in: channel))

		#expect(renamed.modes.letters == "o")
	}

	// MARK: - MODE against the member list

	/// RFC 2811 §4.1: a prefix mode change moves the member's mark, and the
	/// mark comes from ISUPPORT `PREFIX`.
	@Test("A prefix MODE change updates the member's mark")
	func prefixModeChangeUpdatesTheMark() throws {
		let session = session()

		session.supportInfo.processConfigurationData("PREFIX=(ohv)@%+ CHANMODES=b,k,l,imnpst")

		let channel = try joinedChannel("#chan", on: session)

		try receive(":alice!ali@example.org JOIN #chan", on: session)
		try receive(":op!o@example.org MODE #chan +v alice", on: session)

		#expect(try #require(member("alice", in: channel)).mark == "+")

		try receive(":op!o@example.org MODE #chan +o alice", on: session)

		let alice = try #require(member("alice", in: channel))

		#expect(alice.mark == "@")
		#expect(alice.modes.letters == "ov")

		try receive(":op!o@example.org MODE #chan -o alice", on: session)

		#expect(try #require(member("alice", in: channel)).mark == "+")
	}

	// MARK: - invite-notify

	/// IRCv3 `invite-notify`: the server tells channel operators about an
	/// invitation naming somebody else, `INVITE <nick> <channel>`. It belongs
	/// in that channel's view, and it is not an invitation to us.
	@Test("invite-notify: an INVITE for another user is reported in the channel")
	func inviteForAnotherUserIsReportedInTheChannel() throws {
		let session = session(nickname: "me")

		session.enableCapability(.inviteNotify)

		let channel = try joinedChannel("#chan", on: session)

		try receive(":op!o@example.org INVITE alice #chan", on: session)

		let printed = session.printedLines.compactMap { $0 as? [String: Any] }
		let destinations = printed.compactMap { ($0["channel"] as? Conversation)?.name }

		#expect(destinations == ["#chan"])
		#expect(channel.memberExists("alice") == false)
	}

	/// An `INVITE` naming a channel the session is not in has nowhere to go and
	/// must not open one.
	@Test("invite-notify: an INVITE for an unknown channel is not reported")
	func inviteForAnUnknownChannelIsNotReported() throws {
		let session = session(nickname: "me")

		session.enableCapability(.inviteNotify)

		_ = try joinedChannel("#chan", on: session)

		try receive(":op!o@example.org INVITE alice #other", on: session)

		#expect(session.printedLines.count == 0)
		#expect(session.findConversation("#other") == nil)
	}

	/// An invitation addressed to us is a different thing: it cannot be filed
	/// in the invited channel, because we are not in it.
	@Test("An INVITE addressed to us is reported outside the invited channel")
	func inviteAddressedToUsIsReportedElsewhere() throws {
		let session = session(nickname: "me")

		try receive(":op!o@example.org INVITE me #elsewhere", on: session)

		let printed = session.printedLines.compactMap { $0 as? [String: Any] }
		let destinations = printed.compactMap { ($0["channel"] as? Conversation)?.name }

		#expect(printed.isEmpty == false)
		#expect(destinations.contains("#elsewhere") == false)
	}

	// MARK: - NAMES

	/// RFC 2812 §5.2 RPL_NAMREPLY: `<session> <symbol> <channel> :[prefix]<nick>{ [prefix]<nick>}`.
	@Test("RPL_NAMREPLY adds every name in the list")
	func namesReplyAddsEveryName() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :alice @bob +carol", on: session)

		#expect(channel.numberOfMembers == 3)
		#expect(try #require(member("alice", in: channel)).modes.letters.isEmpty)
		#expect(try #require(member("bob", in: channel)).modes.letters == "o")
		#expect(try #require(member("carol", in: channel)).modes.letters == "v")
	}

	/// IRCv3 `multi-prefix`: every prefix the member holds is listed, highest
	/// first, and all of them have to be read rather than only the first.
	@Test("multi-prefix: every prefix in a NAMES entry is read")
	func multiPrefixNamesEntriesAreRead() throws {
		let session = session()

		session.supportInfo.processConfigurationData("PREFIX=(qaohv)~&@%+")
		session.enableCapability(.multiPrefix)

		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :@+alice ~&@bob %carol", on: session)

		#expect(try #require(member("alice", in: channel)).modes.letters == "ov")
		#expect(try #require(member("bob", in: channel)).modes.letters == "qao")
		#expect(try #require(member("bob", in: channel)).mark == "~")
		#expect(try #require(member("carol", in: channel)).modes.letters == "h")
	}

	/// IRCv3 `userhost-in-names`: each entry is a full `nick!user@host`, and
	/// only the nickname names the member.
	@Test("userhost-in-names: a full hostmask entry still names one member")
	func userhostInNamesEntriesAreSplit() throws {
		let session = session()

		session.enableCapability(.userhostInNames)

		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :@alice!ali@example.org bob!b@example.net", on: session)

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
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :alice bob", on: session)
		try receive(":irc.example.net 353 me = #chan :carol", on: session)

		#expect(channel.channelNamesReceived == false)
		#expect(channel.numberOfMembers == 3)

		try receive(":irc.example.net 366 me #chan :End of /NAMES list", on: session)

		#expect(channel.channelNamesReceived)
	}

	/// Once the list is closed a further 353 belongs to a request the session
	/// did not make and must not silently re-populate the member list.
	@Test("A NAMES reply after RPL_ENDOFNAMES does not re-populate the list")
	func namesAfterEndOfNamesIsIgnored() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :alice", on: session)
		try receive(":irc.example.net 366 me #chan :End of /NAMES list", on: session)
		try receive(":irc.example.net 353 me = #chan :bob", on: session)

		#expect(channel.memberExists("bob") == false)
	}

	/// RFC 1459 §2.3: the names are separated by one or more spaces, and a
	/// trailing space is not an extra, empty member.
	@Test("RFC 1459 §2.3: extra spaces in a NAMES list are not members")
	func extraSpacesInNamesAreNotMembers() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me = #chan :alice  bob ", on: session)

		#expect(channel.numberOfMembers == 2)
	}

	/// The names numerics carry a fixed parameter count; a short reply is
	/// malformed and must not be read at an offset that would take a nickname
	/// from the wrong field.
	@Test("A short NAMES numeric is ignored")
	func shortNamesNumericsAreIgnored() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 353 me #chan :alice", on: session)

		#expect(channel.numberOfMembers == 0)
		#expect(channel.channelNamesReceived == false)
	}
}
