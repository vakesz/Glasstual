/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** Reading a line before anything has told the client what the server is like:
 how many parameters a line may carry, what a CTCP verb is compared as, which
 channel modes take a parameter before 005 arrives, and how two members order
 against each other when their prefix tables disagree. */
@MainActor
@Suite("Inbound wire parsing")
struct InboundWireParsingTests {
	private func client(nickname: String = "me") -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": nickname, "username": nickname])
	}

	// MARK: - Parameter count

	/** The inbound cap is deliberately looser than the fifteen parameters
	 RFC 1459 4.1 allows a command: what the client sends has to be a line every
	 server accepts, but what it reads only has to be bounded, and a server that
	 counts differently would otherwise lose the tail of a reply. A line of
	 single-character parameters was read as an array element per two bytes
	 received, so a megabyte of them allocated half a million strings before any
	 handler could look at the command. */
	@Test("A line's parameters are capped and the rest goes to the last one")
	func parameterCountIsCapped() throws {
		let parameters = (0 ..< 400).map { _ in "a" }.joined(separator: " ")
		let parsed = try #require(LineParser.parsedLine(fromLine: "PRIVMSG \(parameters)"))

		#expect(parsed.parameters.count == IRCProtocolLimits.maximumInboundParameterCount)
		#expect(parsed.parameters.dropLast().allSatisfy { $0 == "a" })

		/* Nothing is thrown away: the overflow arrives as one trailing value. */
		let tail = try #require(parsed.parameters.last)

		#expect(tail.hasPrefix("a a "))
		#expect(tail.split(separator: " ").count == 400 - (IRCProtocolLimits.maximumInboundParameterCount - 1))
	}

	@Test("A line inside the cap is unchanged")
	func shortLinesKeepEveryParameter() throws {
		let parsed = try #require(
			LineParser.parsedLine(fromLine: ":irc.example.net 005 me PREFIX=(ov)@+ :are supported")
		)

		#expect(parsed.parameters == ["me", "PREFIX=(ov)@+", "are supported"])
	}

	// MARK: - CTCP ACTION

	/** A CTCP verb is an ASCII token and folds as one. Folding the whole
	 payload with `lowercased()` folded the message too — Unicode rules, on text
	 the client then took seven characters off *unfolded* — and cost an
	 allocation the length of every CTCP that arrives. */
	@Test("ACTION is recognised however it is cased")
	func actionIsRecognisedInAnyAsciiCasing() {
		for verb in ["ACTION", "action", "AcTiOn"] {
			let classification = IRCInboundTextPolicy.classify(
				command: "PRIVMSG",
				payload: "\u{1}\(verb) waves\u{1}"
			)

			#expect(classification.lineType == .action)
			#expect(classification.text == "waves")
		}
	}

	@Test("A verb that only starts like ACTION is not one")
	func actionPrefixIsNotMatchedLoosely() {
		let plural = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "\u{1}ACTIONS are loud\u{1}")

		#expect(plural.lineType == .ctcpQuery)
		#expect(plural.text == "ACTIONS are loud")

		/* A verb that only folds to ACTION under Unicode rules is not one
		 either, and the payload reaches the handler byte for byte. */
		let turkish = IRCInboundTextPolicy.classify(command: "PRIVMSG", payload: "\u{1}ACT\u{130}ON hi\u{1}")

		#expect(turkish.lineType == .ctcpQuery)
		#expect(turkish.text == "ACT\u{130}ON hi")
	}

	@Test("An emote keeps its text exactly as it was sent")
	func actionTextSurvivesUnchanged() {
		let classification = IRCInboundTextPolicy.classify(
			command: "PRIVMSG",
			payload: "\u{1}ACTION \u{130}stanbul \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{1}"
		)

		#expect(classification.lineType == .action)
		#expect(classification.text == "\u{130}stanbul \u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}")
	}

	@Test("A NOTICE is never an emote")
	func noticeIsNeverAnEmote() {
		let classification = IRCInboundTextPolicy.classify(command: "NOTICE", payload: "\u{1}ACTION waves\u{1}")

		#expect(classification.lineType == .ctcpReply)
	}

	// MARK: - Channel modes before ISUPPORT

	/** `CHANMODES` arrives in 005, and a `MODE` or an `RPL_CHANNELMODEIS` can
	 arrive before it does — or a server may never send one. With no table every
	 letter parsed as a plain flag, so a ban recorded no mask and a key and a
	 limit were both lost. */
	@Test("A ban carries its mask before any 005 has arrived")
	func banCarriesItsMaskBeforeISupport() throws {
		let client = client()

		#expect(client.supportInfo.configurationReceived == false)

		let modes = client.supportInfo.parseModes("+b nick!*@*")
		let ban = try #require(modes.first)

		#expect(modes.count == 1)
		#expect(ban.modeSymbol == "b")
		#expect(ban.modeParameter == "nick!*@*")
	}

	@Test("A key and a limit carry their parameters before any 005 has arrived")
	func keyAndLimitCarryTheirParametersBeforeISupport() throws {
		let client = client()
		let channel = try #require(client.findChannelOrCreate("#chan"))
		channel.activate()

		let message = try #require(
			Message(line: ":irc.example.net 324 me #chan +kl secret 50", on: client)
		)
		client.receiveNumericReply(message)

		let modeInfo = try #require(channel.modeInfo)

		#expect(modeInfo.modeInfo(for: "k")?.modeParameter == "secret")
		#expect(modeInfo.modeInfo(for: "l")?.modeParameter == "50")
	}

	/// What the server says stands, even where it is narrower than the RFC's.
	@Test("An advertised CHANMODES overrides the defaults")
	func advertisedChannelModesWin() throws {
		let client = client()
		let message = try #require(
			Message(line: ":irc.example.net 005 me CHANMODES=b,k,l,imnpstL :are supported", on: client)
		)
		client.receiveNumericReply(message)

		let modes = client.supportInfo.parseModes("+L #other")
		let forward = try #require(modes.first)

		#expect(forward.modeSymbol == "L")
		#expect(forward.modeParameter == nil)
	}

	// MARK: - Member ordering

	/** A member carries the prefix table it was stamped with, and one stamped
	 before a `CASEMAPPING` change carries the old mapping. Folding each side
	 with the receiver's own table made the comparator answer "a before b" and
	 "b before a" for the same pair, which is not the strict weak ordering
	 `sort` requires. */
	@Test("A member comparison folds both nicknames under one table")
	func memberComparisonFoldsBothSidesWithOneTable() {
		let rfc1459 = IRCUserPrefixTable(
			modeSymbols: ["o", "v"], prefixCharacters: ["@", "+"], caseMapping: .rfc1459
		)
		let ascii = IRCUserPrefixTable(
			modeSymbols: ["o", "v"], prefixCharacters: ["@", "+"], caseMapping: .ascii
		)
		let bracket = ChannelUser(user: User(nickname: "nick[home]"), prefixes: rfc1459)
		let brace = ChannelUser(user: User(nickname: "nick{home}"), prefixes: ascii)

		/* Under RFC 1459 casing the two spell one nickname. */
		#expect(bracket.compareRank(to: brace, favoringServerStaff: false, casefoldingWith: rfc1459) == .orderedSame)
		#expect(brace.compareRank(to: bracket, favoringServerStaff: false, casefoldingWith: rfc1459) == .orderedSame)

		/* Under ASCII casing they are two, and the order is symmetric. */
		#expect(
			bracket.compareRank(to: brace, favoringServerStaff: false, casefoldingWith: ascii) == .orderedAscending
		)
		#expect(
			brace.compareRank(to: bracket, favoringServerStaff: false, casefoldingWith: ascii) == .orderedDescending
		)
	}

	/// The one weight-ordered sort, which reads the preference once for the
	/// whole ordering rather than once per comparison.
	@Test("Conversation weight orders the heaviest speaker first")
	func conversationWeightOrdersTheHeaviestFirst() {
		let table = IRCUserPrefixTable()
		var heavy = ChannelUser(user: User(nickname: "zoe"), prefixes: table)
		heavy.incomingConversation()
		let light = ChannelUser(user: User(nickname: "alice"), prefixes: table)

		let sorted = ChannelUser.sortedByConversationWeight([light, heavy])

		#expect(sorted.map(\.user.nickname) == ["zoe", "alice"])
	}
}
