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

/// One entry from the numerics registry.
nonisolated struct IRCSpecNumericCase: CustomTestStringConvertible {
	let name: String
	let value: UInt
	let numeric: IRCNumeric

	var testDescription: String {
		"\(value) \(name)"
	}
}

/// The numerics table, against RFC 2812 §5 and the numerics list in
/// modern.ircdocs.horse. A numeric read at the wrong value routes a reply to
/// the wrong handler, which is the kind of mistake nothing else catches.
@Suite("Numeric replies")
@MainActor
struct IRCSpecNumericsTests {
	/// RFC 2812 §5.1 and §5.2, plus the modern additions the client handles.
	nonisolated static let registry: [IRCSpecNumericCase] = [
		IRCSpecNumericCase(name: "RPL_WELCOME", value: 1, numeric: .welcome),
		IRCSpecNumericCase(name: "RPL_YOURHOST", value: 2, numeric: .yourhost),
		IRCSpecNumericCase(name: "RPL_CREATED", value: 3, numeric: .created),
		IRCSpecNumericCase(name: "RPL_MYINFO", value: 4, numeric: .myinfo),
		IRCSpecNumericCase(name: "RPL_ISUPPORT", value: 5, numeric: .isupport),
		IRCSpecNumericCase(name: "RPL_UMODEIS", value: 221, numeric: .umodeis),
		IRCSpecNumericCase(name: "RPL_LUSERCLIENT", value: 251, numeric: .luserclient),
		IRCSpecNumericCase(name: "RPL_LUSEROP", value: 252, numeric: .luserhop),
		IRCSpecNumericCase(name: "RPL_LUSERUNKNOWN", value: 253, numeric: .luserunknown),
		IRCSpecNumericCase(name: "RPL_LUSERCHANNELS", value: 254, numeric: .luserchannels),
		IRCSpecNumericCase(name: "RPL_LUSERME", value: 255, numeric: .luserme),
		IRCSpecNumericCase(name: "RPL_LOCALUSERS", value: 265, numeric: .localusers),
		IRCSpecNumericCase(name: "RPL_GLOBALUSERS", value: 266, numeric: .globalusers),
		IRCSpecNumericCase(name: "RPL_AWAY", value: 301, numeric: .away),
		IRCSpecNumericCase(name: "RPL_ISON", value: 303, numeric: .ison),
		IRCSpecNumericCase(name: "RPL_UNAWAY", value: 305, numeric: .unaway),
		IRCSpecNumericCase(name: "RPL_NOWAWAY", value: 306, numeric: .nowaway),
		IRCSpecNumericCase(name: "RPL_WHOISUSER", value: 311, numeric: .whoisuser),
		IRCSpecNumericCase(name: "RPL_WHOISSERVER", value: 312, numeric: .whoisserver),
		IRCSpecNumericCase(name: "RPL_WHOISOPERATOR", value: 313, numeric: .whoisoperator),
		IRCSpecNumericCase(name: "RPL_WHOWASUSER", value: 314, numeric: .whowasuser),
		IRCSpecNumericCase(name: "RPL_ENDOFWHO", value: 315, numeric: .endofwho),
		IRCSpecNumericCase(name: "RPL_WHOISIDLE", value: 317, numeric: .whoisidle),
		IRCSpecNumericCase(name: "RPL_ENDOFWHOIS", value: 318, numeric: .endofwhois),
		IRCSpecNumericCase(name: "RPL_WHOISCHANNELS", value: 319, numeric: .whoischannels),
		IRCSpecNumericCase(name: "RPL_LISTSTART", value: 321, numeric: .liststart),
		IRCSpecNumericCase(name: "RPL_LIST", value: 322, numeric: .list),
		IRCSpecNumericCase(name: "RPL_LISTEND", value: 323, numeric: .listend),
		IRCSpecNumericCase(name: "RPL_CHANNELMODEIS", value: 324, numeric: .channelmodeis),
		IRCSpecNumericCase(name: "RPL_CREATIONTIME", value: 329, numeric: .creationtime),
		IRCSpecNumericCase(name: "RPL_WHOISACCOUNT", value: 330, numeric: .whoisaccount),
		IRCSpecNumericCase(name: "RPL_TOPIC", value: 332, numeric: .topic),
		IRCSpecNumericCase(name: "RPL_TOPICWHOTIME", value: 333, numeric: .topicwhotime),
		IRCSpecNumericCase(name: "RPL_INVITING", value: 341, numeric: .inviting),
		IRCSpecNumericCase(name: "RPL_INVITELIST", value: 346, numeric: .invitelist),
		IRCSpecNumericCase(name: "RPL_ENDOFINVITELIST", value: 347, numeric: .endofinvitelist),
		IRCSpecNumericCase(name: "RPL_EXCEPTLIST", value: 348, numeric: .exceptlist),
		IRCSpecNumericCase(name: "RPL_ENDOFEXCEPTLIST", value: 349, numeric: .endofexceptlist),
		IRCSpecNumericCase(name: "RPL_WHOREPLY", value: 352, numeric: .whoreply),
		IRCSpecNumericCase(name: "RPL_NAMREPLY", value: 353, numeric: .namereply),
		IRCSpecNumericCase(name: "RPL_WHOSPCRPL", value: 354, numeric: .whospcrpl),
		IRCSpecNumericCase(name: "RPL_ENDOFNAMES", value: 366, numeric: .endofnames),
		IRCSpecNumericCase(name: "RPL_BANLIST", value: 367, numeric: .banlist),
		IRCSpecNumericCase(name: "RPL_ENDOFBANLIST", value: 368, numeric: .endofbanlist),
		IRCSpecNumericCase(name: "RPL_ENDOFWHOWAS", value: 369, numeric: .endofwhowas),
		IRCSpecNumericCase(name: "RPL_MOTD", value: 372, numeric: .motd),
		IRCSpecNumericCase(name: "RPL_MOTDSTART", value: 375, numeric: .motdstart),
		IRCSpecNumericCase(name: "RPL_ENDOFMOTD", value: 376, numeric: .endofmotd),
		IRCSpecNumericCase(name: "RPL_YOUREOPER", value: 381, numeric: .youreoper),
		IRCSpecNumericCase(name: "ERR_NOSUCHNICK", value: 401, numeric: .nosuchnick),
		IRCSpecNumericCase(name: "ERR_NOSUCHSERVER", value: 402, numeric: .nosuchserver),
		IRCSpecNumericCase(name: "ERR_NOSUCHCHANNEL", value: 403, numeric: .nosuchchannel),
		IRCSpecNumericCase(name: "ERR_CANNOTSENDTOCHAN", value: 404, numeric: .cannotsendtochan),
		IRCSpecNumericCase(name: "ERR_TOOMANYCHANNELS", value: 405, numeric: .toomanychannels),
		IRCSpecNumericCase(name: "ERR_UNKNOWNCOMMAND", value: 421, numeric: .unknowncommand),
		IRCSpecNumericCase(name: "ERR_NOMOTD", value: 422, numeric: .nomotd),
		IRCSpecNumericCase(name: "ERR_ERRONEUSNICKNAME", value: 432, numeric: .erroneusnickname),
		IRCSpecNumericCase(name: "ERR_NICKNAMEINUSE", value: 433, numeric: .nicknameinuse),
		IRCSpecNumericCase(name: "ERR_UNAVAILRESOURCE", value: 437, numeric: .unavailresource),
		IRCSpecNumericCase(name: "ERR_NEEDMOREPARAMS", value: 461, numeric: .needmoreparams),
		IRCSpecNumericCase(name: "ERR_CHANNELISFULL", value: 471, numeric: .channelisfull),
		IRCSpecNumericCase(name: "ERR_INVITEONLYCHAN", value: 473, numeric: .inviteonlychan),
		IRCSpecNumericCase(name: "ERR_BANNEDFROMCHAN", value: 474, numeric: .bannedfromchan),
		IRCSpecNumericCase(name: "ERR_BADCHANNELKEY", value: 475, numeric: .badchannelkey),
		IRCSpecNumericCase(name: "ERR_BADCHANMASK", value: 476, numeric: .badchanmask),
		IRCSpecNumericCase(name: "RPL_MONONLINE", value: 730, numeric: .mononline),
		IRCSpecNumericCase(name: "RPL_MONOFFLINE", value: 731, numeric: .monoffline),
		IRCSpecNumericCase(name: "RPL_MONLIST", value: 732, numeric: .monlist),
		IRCSpecNumericCase(name: "RPL_ENDOFMONLIST", value: 733, numeric: .endofmonlist),
		IRCSpecNumericCase(name: "ERR_MONLISTFULL", value: 734, numeric: .monlistfull),
	]

	@Test("The numerics table matches the registry", arguments: registry)
	func numericsMatchTheRegistry(_ testCase: IRCSpecNumericCase) {
		#expect(testCase.numeric.rawValue == testCase.value)
	}

	/// Two names for one number would let a reply reach a handler written for
	/// something else.
	@Test("No two numerics share a value")
	func numericValuesAreUnique() {
		let values = IRCNumeric.allCases.map(\.rawValue)

		#expect(Set(values).count == values.count)
	}

	/// RFC 2812 §5.2: "Error replies are found in the range from 400 to 599."
	/// The client narrows the top of that band to 596 because 597 upwards is
	/// the WATCH range that several servers use for ordinary replies.
	@Test(
		"Numerics in the error band route to the error path",
		arguments: [
			(UInt(399), false), (UInt(400), false), (UInt(401), true), (UInt(433), true),
			(UInt(596), true), (UInt(597), false), (UInt(600), false), (UInt(904), false),
		]
	)
	func errorBandIsClassified(_ testCase: (numeric: UInt, isError: Bool)) {
		#expect(IRCNumeric.isErrorReply(testCase.numeric) == testCase.isError)
	}

	/// A server may send an error numeric this table has no name for, and it
	/// still has to reach the error path rather than being printed as a reply.
	@Test("An unnamed numeric in the error band is still an error")
	func unnamedErrorNumericsAreStillErrors() {
		#expect(IRCNumeric(rawValue: 483) == nil)
		#expect(IRCNumeric.isErrorReply(483))
	}

	/// A parsed numeric command reaches the numeric path, and a word command
	/// does not.
	@Test("A three-digit command is dispatched as a numeric")
	func threeDigitCommandsAreNumerics() throws {
		let client = GLTTestClient()
		let numeric = try #require(Message(line: ":irc.example.net 433 * taken :Nickname is in use", on: client))
		let command = try #require(Message(line: ":irc.example.net NOTICE * :hello", on: client))

		#expect(numeric.commandNumeric == 433)
		#expect(command.commandNumeric == 0)
	}

	// MARK: - Routing

	private func client() -> GLTTestClient {
		GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])
	}

	private func receive(_ line: String, on client: GLTTestClient) throws {
		let message = try #require(Message(line: line, on: client))

		client.receiveNumericReply(message)
	}

	/// RFC 2812 §5.1 RPL_WELCOME: the first parameter is the nickname the
	/// server settled on, which may not be the one that was asked for.
	@Test("001 completes registration and adopts the server's nickname")
	func welcomeCompletesRegistration() throws {
		let client = client()

		try receive(":irc.example.net 001 me_ :Welcome to the Internet Relay Network", on: client)

		#expect(client.isLoggedIn)
		#expect(client.userNickname == "me_")
	}

	/// modern.ircdocs.horse RPL_ISUPPORT: `<client> <token>[ <token>]{15} :are
	/// supported by this server`. The first and last parameters are not
	/// tokens.
	@Test("005 feeds only the token parameters to ISUPPORT")
	func isupportFeedsOnlyTheTokens() throws {
		let client = client()

		try receive(
			":irc.example.net 005 me NICKLEN=16 CHANTYPES=#& :are supported by this server",
			on: client
		)

		#expect(client.supportInfo.maximumNicknameLength == 16)
		#expect(client.supportInfo.channelNamePrefixes == ["#", "&"])
		// "are" would otherwise be read as a token of its own.
		#expect(client.supportInfo.configurationReceived)
	}

	/// RFC 2812 §5.1 RPL_TOPIC: `<client> <channel> :<topic>`.
	@Test("332 sets the channel topic")
	func topicNumericSetsTheTopic() throws {
		let client = client()
		let channel = try #require(client.findChannelOrCreate("#chan"))

		channel.activate()

		try receive(":irc.example.net 332 me #chan :A topic worth reading", on: client)

		#expect(channel.topic == "A topic worth reading")
	}

	/// RFC 2812 §5.1 RPL_CHANNELMODEIS: `<client> <channel> <modestring>
	/// [modearguments...]`.
	@Test("324 records the channel's modes")
	func channelModeNumericRecordsTheModes() throws {
		let client = client()

		client.supportInfo.processConfigurationData("CHANMODES=b,k,l,imnpst")

		let channel = try #require(client.findChannelOrCreate("#chan"))

		channel.activate()

		try receive(":irc.example.net 324 me #chan +ntl 50", on: client)

		let modes = try #require(channel.modeInfo)

		#expect(modes.modeIsDefined("n"))
		#expect(modes.modeIsDefined("t"))
		#expect(modes.modeInfo(for: "l")?.modeParameter == "50")
	}

	/// A numeric whose parameters are shorter than its definition cannot be
	/// read at the offsets that definition names.
	@Test("A short numeric is ignored rather than read at the wrong offset")
	func shortNumericsAreIgnored() throws {
		let client = client()
		let channel = try #require(client.findChannelOrCreate("#chan"))

		channel.activate()

		try receive(":irc.example.net 332 me", on: client)

		#expect(channel.topic == nil)
	}
}
