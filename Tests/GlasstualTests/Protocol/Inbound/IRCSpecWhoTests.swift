// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// RFC 2812 §3.6 and §5.1: the WHO and WHOIS replies, and the WHOX extension
/// modern.ircdocs.horse documents as `RPL_WHOSPCRPL` (354).
@Suite("WHO and WHOIS replies")
@MainActor
struct IRCSpecWhoTests {
	@Test("One wire NAMES numeric publishes one member snapshot")
	func namesPublishesOncePerNumeric() throws {
		let session = session()
		let channel = try joinedChannel("#names", on: session)
		let list = MemberList()
		list.assign(to: channel)
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		session.setConnectionTransportForTesting(.connected)
		let revision = list.presentationRevision
		let names = (0 ..< 256).map { "member\($0)" }.joined(separator: " ")
		session.connectionDidReceive(":server 353 me = #names :\(names)")
		#expect(channel.numberOfMembers == 256)
		#expect(channel.findMember("member255") != nil)
		#expect(list.presentationRevision == revision + 1)
		#expect(list.groups.flatMap(\.members).count == 256)
		list.assign(to: nil)
	}

	@Test("A pending read keeps member lookups current before publishing ordered rows")
	func pendingReadKeepsMembershipCurrent() throws {
		let session = session()
		let channel = try joinedChannel("#names", on: session)
		let list = MemberList()
		list.assign(to: channel)
		defer { list.assign(to: nil) }
		session.setConnectionTransportForTesting(.connected)
		let revision = list.presentationRevision

		session.beginInboundMemberPresentationUpdates()
		session.connectionDidReceive(":server 353 me = #names :alice bob")
		#expect(channel.findMember("bob") != nil)
		#expect(channel.numberOfMembers == 2)
		#expect(list.presentationRevision == revision)
		session.connectionDidReceive(":server 353 me = #names :@alice carol")
		#expect(channel.findMember("alice")?.modes.letters == "o")
		#expect(channel.findMember("carol") != nil)
		#expect(list.presentationRevision == revision)
		session.finishInboundMemberPresentationUpdates()

		#expect(list.presentationRevision == revision + 1)
		#expect(list.groups.flatMap(\.members).map(\.user.nickname) == ["alice", "bob", "carol"])
	}

	@Test("WHO and WHOX publish each related list once and preserve selection", arguments: [false, true])
	func whoBatchesRelatedPresentations(_ whox: Bool) throws {
		let session = session()
		session.enableCapability(.awayNotify)
		let first = try joinedChannel("#first", on: session)
		let second = try joinedChannel("#second", on: session)
		let user = session.findUserOrCreate("alice")
		for channel in [first, second] {
			channel.addMember(Member(user: user, prefixes: session.currentUserPrefixes))
		}
		let firstList = MemberList()
		let secondList = MemberList()
		firstList.assign(to: first)
		secondList.assign(to: second)
		firstList.selectedMemberIDs = [user.id]
		secondList.selectedMemberIDs = [user.id]
		let revisions = [firstList.presentationRevision, secondList.presentationRevision]
		let connection = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = connection
		session.setConnectionTransportForTesting(.connected)
		let line = whox
			? ":server 354 me \(ServerQuirks.whoxToken) #first ali example.org alice G* account :Alice Example"
			: ":server 352 me #first ali example.org server alice G* :0 Alice Example"
		session.connectionDidReceive(line)
		for (index, list) in [firstList, secondList].enumerated() {
			#expect(list.presentationRevision == revisions[index] + 1)
			#expect(list.selectedMemberIDs == [user.id])
			let shown = try #require(list.groups.flatMap(\.members).first?.user)
			#expect(shown.isAway)
			#expect(shown.isIRCop)
			#expect(shown.realName == "Alice Example")
		}
		session.connectionDidReceive(line)
		#expect(firstList.presentationRevision == revisions[0] + 1)
		#expect(secondList.presentationRevision == revisions[1] + 1)
		firstList.assign(to: nil)
		secondList.assign(to: nil)
	}

	private func session() -> TestServerSession {
		TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
	}

	private func joinedChannel(_ name: String, on session: TestServerSession) throws -> Conversation {
		let channel = try #require(session.findConversationOrCreate(name))

		channel.activate()

		return channel
	}

	private func receive(_ line: String, on session: TestServerSession) throws {
		let message = try #require(Message(line: line, on: session))

		session.receiveNumericReply(message)
	}

	/// RFC 2812 §5.1 RPL_WHOREPLY: `<session> <channel> <user> <host> <server>
	/// <nick> <flags> :<hopcount> <real name>`. Reading any field at the wrong
	/// index would attach another user's host to this one.
	@Test("352 is read at the field positions RFC 2812 defines")
	func whoReplyFieldsAreReadInOrder() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(
			":irc.example.net 352 me #chan ali example.org irc.example.net alice H :0 Alice Example",
			on: session
		)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.username == "ali")
		#expect(alice.user.address == "example.org")
		#expect(alice.user.realName == "Alice Example")
	}

	/// The last parameter is `<hopcount> <real name>`, so the hop count has to
	/// come off before the real name is kept.
	@Test("352: the hop count is not part of the real name")
	func hopCountIsNotPartOfTheRealName() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(
			":irc.example.net 352 me #chan b example.net irc.example.net bob H :3 Bob of Example",
			on: session
		)

		#expect(try #require(channel.findMember("bob")).user.realName == "Bob of Example")
	}

	/// RFC 2812 §5.1: the flags are `<H|G>[*][@|+]`. `G` is gone (away), `*`
	/// is an IRC operator, and the rest are channel prefixes.
	@Test("352: the flags field carries away, operator and prefix status")
	func whoFlagsAreParsed() {
		let modeForPrefix: (String) -> String? = { prefix in
			switch prefix {
			case "@": "o"
			case "+": "v"
			default: nil
			}
		}

		let away = WHOFlags.parse(
			"G@", monitorAwayStatus: true, botFlag: nil, modeForPrefix: modeForPrefix
		)

		#expect(away.isAway)
		#expect(away.userModes == "o")

		let here = WHOFlags.parse(
			"H+", monitorAwayStatus: true, botFlag: nil, modeForPrefix: modeForPrefix
		)

		#expect(here.isAway == false)
		#expect(here.userModes == "v")

		let operatorFlags = WHOFlags.parse(
			"H*@", monitorAwayStatus: true, botFlag: nil, modeForPrefix: modeForPrefix
		)

		#expect(operatorFlags.isIRCop)
		#expect(operatorFlags.userModes == "o")
	}

	/// A bot is flagged with the character the server named in `BOT=`, and
	/// with nothing on a server that named none.
	@Test("352: the bot flag is the character the ISUPPORT BOT token names")
	func botFlagIsTheISupportCharacter() {
		let supported = WHOFlags.parse(
			"HB", monitorAwayStatus: false, botFlag: "B", modeForPrefix: { _ in nil }
		)
		let unsupported = WHOFlags.parse(
			"HB", monitorAwayStatus: false, botFlag: nil, modeForPrefix: { _ in nil }
		)
		let otherCharacter = WHOFlags.parse(
			"Hb", monitorAwayStatus: false, botFlag: "b", modeForPrefix: { _ in nil }
		)
		let wrongCharacter = WHOFlags.parse(
			"HB", monitorAwayStatus: false, botFlag: "b", modeForPrefix: { _ in nil }
		)

		#expect(supported.isBot)
		#expect(unsupported.isBot == false)
		#expect(otherCharacter.isBot)
		#expect(wrongCharacter.isBot == false)
	}

	/// A short 352 cannot be read at the indices the reply defines, so it says
	/// nothing rather than something wrong.
	@Test("352: a short reply is ignored")
	func shortWhoRepliesAreIgnored() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(":irc.example.net 352 me #chan ali example.org irc.example.net alice", on: session)

		#expect(channel.numberOfMembers == 0)
	}

	/// modern.ircdocs.horse RPL_WHOSPCRPL: the reply carries back the token
	/// the session put in its `WHO ... %tcuhnfar,<token>` request, and only a
	/// reply carrying that token has the field layout the session asked for.
	@Test("354: a WHOX reply carries the session's own token and the account")
	func whoxRepliesCarryTheAccount() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)
		let token = ServerQuirks.whoxToken

		try receive(
			":irc.example.net 354 me \(token) #chan ali example.org alice H aliceacct :Alice Example",
			on: session
		)

		let alice = try #require(channel.findMember("alice"))

		#expect(alice.user.account == "aliceacct")
		#expect(alice.user.username == "ali")
		#expect(alice.user.realName == "Alice Example")
	}

	/// A 354 answering somebody else's request has a different field layout,
	/// so reading it would put the wrong values on the member.
	@Test("354: a reply with another token is not read as a member update")
	func whoxRepliesWithAnotherTokenAreNotRead() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)

		try receive(
			":irc.example.net 354 me 999 #chan ali example.org alice H aliceacct :Alice Example",
			on: session
		)

		#expect(channel.numberOfMembers == 0)
	}

	/// `account-tag` and WHOX agree on what "no account" looks like: the
	/// literal `0` in a WHOX reply, like `*` elsewhere.
	@Test("354: 0 means the user has no account")
	func whoxZeroMeansNoAccount() throws {
		let session = session()
		let channel = try joinedChannel("#chan", on: session)
		let token = ServerQuirks.whoxToken

		try receive(
			":irc.example.net 354 me \(token) #chan b example.net bob H 0 :Bob Example",
			on: session
		)

		#expect(try #require(channel.findMember("bob")).user.account == nil)
	}

	/// RFC 2812 §5.1 RPL_WHOISUSER: `<session> <nick> <user> <host> * :<real name>`.
	@Test("311 opens a WHOIS response")
	func whoisUserOpensTheResponse() throws {
		let session = session()

		try receive(":irc.example.net 311 me alice ali example.org * :Alice Example", on: session)

		#expect(session.inWhoisResponse)

		try receive(":irc.example.net 318 me alice :End of /WHOIS list", on: session)

		#expect(session.inWhoisResponse == false)
	}

	/// RFC 2812 §5.1 RPL_ENDOFWHO closes the WHO request the session opened, so
	/// the next reply is not mistaken for part of this one.
	@Test("315 closes the WHO request")
	func endOfWhoClosesTheRequest() throws {
		let session = session()

		session.requestedCommands.recordWhoRequestOpenedAsVisible()

		#expect(session.requestedCommands.visibleWhoRequest)

		try receive(":irc.example.net 315 me #chan :End of /WHO list", on: session)

		#expect(session.requestedCommands.visibleWhoRequest == false)
	}
}
