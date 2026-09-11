/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
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
import GlasstualPluginKit
import Testing

typealias SupportInfo = Glasstual.IRCISupportInfo

@MainActor
@Suite("ISUPPORT parsing")
struct IRCISupportInfoTests {
	@Test(
		"Parsed byte budgets reach AWAY, KICK and TOPIC consumers",
		arguments: [UInt(0), 3, UInt(Int.max), UInt(Int.max) + 1, UInt.max]
	)
	func lengthBudgetsReachCommandConsumers(_ limit: UInt) {
		CommandIndex.populateCommandIndex()
		let fixture = GLTClientEnvironmentFixture(preferences: ClientPreferences())
		let awayClient = fixture.world.createClient(with: IRCClientConfig())
		awayClient.isLoggedIn = true
		awayClient.supportInfo.processConfigurationData("AWAYLEN=\(limit)")
		awayClient.sendCommand("AWAY \u{e9}\u{e9}ab", completeTarget: false, target: nil)
		let expected = limit == 3 ? "\u{e9}" : "\u{e9}\u{e9}ab"
		#expect(awayClient.lastAwayMessage == expected)

		let client = GLTTestClient()
		client.isConnected = true
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("KICKLEN=\(limit) TOPICLEN=\(limit)")
		client.sendCommand("KICK #test nick \u{e9}\u{e9}ab", completeTarget: false, target: nil)
		client.sendCommand("TOPIC #test \u{e9}\u{e9}ab", completeTarget: false, target: nil)
		#expect(client.sentLines.compactMap { $0 as? String } == [
			"KICK #test nick :\(expected)",
			"TOPIC #test :\(expected)",
		])
	}

	@Test(
		"Parsed NICKLEN bounds names and sender prefixes without narrowing UInt early",
		arguments: [UInt(3), 8, UInt(Int.max), UInt(Int.max) + 1, UInt.max]
	)
	func nicknameLimitsReachNameConsumers(_ limit: UInt) throws {
		let client = GLTTestClient()
		client.supportInfo.processConfigurationData("NICKLEN=\(limit)")
		#expect(client.stringIsNickname("alice") == (limit >= 5))
		#expect(("alice!u@host" as NSString).hostmask(on: client)?.nickname == (limit >= 5 ? "alice" : nil))
		let message = try #require(Message(line: ":alice!u@host PRIVMSG #test :hello", on: client))
		#expect(message.senderIsServer == (limit < 5))
		#expect(("alice" as NSString).padNickname(
			withCharacter: 95,
			maximumLength: client.supportInfo.maximumNicknameLength
		)
			== (limit == 3 ? "al_" : "alice_"))
	}

	@Test(
		"Server target counts are bounded before conversion and slicing",
		arguments: [UInt(0), 1, 2, UInt(Int.max), UInt(Int.max) + 1, UInt.max]
	)
	func targetCountsReachTheChunkingConsumer(_ limit: UInt) {
		let info = supportInfoWithConfiguration("TARGMAX=PRIVMSG:\(limit)")
		let targets = ["a", "b", "c", "d", "e"]
		let expected = limit <= 1 ? targets.map { [$0] }
			: limit == 2 ? [["a", "b"], ["c", "d"], ["e"]] : [targets]

		#expect(info.maximumTargets(forCommand: "PRIVMSG") == limit)
		#expect(SupportInfo.chunkTargets(targets, limit: info.maximumTargets(forCommand: "PRIVMSG")) == expected)
		#expect(SupportInfo.chunkTargets([], limit: info.maximumTargets(forCommand: "PRIVMSG")).isEmpty)
	}

	@Test("A server that says nothing about case mapping gets RFC 1459")
	func defaultCaseMappingIsRFC1459() {
		let supportInfo = supportInfoWithConfiguration("NETWORK=Example")

		#expect(supportInfo.caseMapping == IRCISupportInfoCaseMapping.rfc1459)
		#expect(supportInfo.casefoldString("Nick[]\\~") == "nick{}|^")
	}

	@Test("Parsing a mode string consumes a parameter for each mode that takes one")
	func parseModesUsesChannelModeClasses() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("+nt-k+l secret 10")

		#expect(modes.count == 4)

		#expect(modes[0].modeSymbol == "n")

		#expect(modes[0].modeIsSet)

		#expect(modes[2].modeSymbol == "k")

		#expect(modes[2].modeIsSet == false)

		#expect(modes[2].modeParameter == "secret")
		#expect(modes[3].modeSymbol == "l")
		#expect(modes[3].modeParameter == "10")
	}

	@Test("Unsetting a mode that needs no parameter leaves the next word for the next mode")
	func parseModesDoesNotConsumeParameterWhenUnsetModeDoesNotRequireOne() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("-l leftover +t")

		#expect(modes.count == 2)

		#expect(modes[0].modeSymbol == "l")

		#expect(modes[0].modeIsSet == false)

		#expect(modes[0].modeParameter == nil)

		#expect(modes[1].modeSymbol == "t")

		#expect(modes[1].modeIsSet)
	}

	@Test("A mode whose parameter never arrived is still reported")
	func parseModesAllowsMissingRequiredParameter() {
		let supportInfo = supportInfoWithConfiguration("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let modes = supportInfo.parseModes("+k")

		#expect(modes.count == 1)

		#expect(modes[0].modeSymbol == "k")

		#expect(modes[0].modeIsSet)

		#expect(modes[0].modeParameter == nil)
	}

	@Test("The limit tokens set the channel, target and list ceilings, and chunking respects them")
	func limitTokensAndTargetChunking() {
		let supportInfo =
			supportInfoWithConfiguration("CHANLIMIT=#&:50,+: TARGMAX=privmsg:4,JOIN: MAXTARGETS=3 MAXLIST=beI:60")

		#expect(supportInfo.channelLimit(forChannelNamed: "#chat") == 50)
		#expect(supportInfo.channelLimit(forChannelNamed: "&local") == 50)
		#expect(supportInfo.channelLimit(forChannelNamed: "+modeless") == 0)
		#expect(supportInfo.maximumTargets(forCommand: "PRIVMSG") == 4)
		#expect(supportInfo.maximumTargets(forCommand: "notice") == 3)
		#expect(supportInfo.maximumTargets(forCommand: "join") == 0)
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("b")) == 60)
		#expect(supportInfo.maximumListEntries(forModeSymbol: ChannelModeSymbol("I")) == 60)

		let targets = ["a", "b", "c", "d", "e"]

		#expect(SupportInfo.chunkTargets(targets, limit: 2) == [["a", "b"], ["c", "d"], ["e"]])

		let conservativeChunks = SupportInfo.chunkTargets(["a", "b"], limit: 0)

		#expect(conservativeChunks == [["a"], ["b"]])
	}

	@Test("A wildcard client tag denial can still name its exceptions")
	func clientTagDenyAllowsExceptionsToWildcard() {
		let supportInfo = supportInfoWithConfiguration("CLIENTTAGDENY=*,-draft/typing,-example/allowed")

		#expect(supportInfo.isClientTagDenied("example/other"))
		#expect(supportInfo.isClientTagDenied("DRAFT/TYPING") == false)
		#expect(supportInfo.isClientTagDenied("example/allowed") == false)
	}

	@Test("EXTBAN splits into its prefix and the types the server offers")
	func extendedBanTokenSeparatesPrefixAndTypes() {
		let supportInfo = supportInfoWithConfiguration("EXTBAN=$,ac")

		#expect(supportInfo.extendedBanPrefix == "$")
		#expect(supportInfo.extendedBanTypes == ["a", "c"])

		#expect(supportInfo.descriptionForExtendedBanMask("$a:account") != nil)

		#expect(supportInfo.descriptionForExtendedBanMask("$q:quiet") == nil)
	}

	@Test("Resetting SILENCE clears both the support flag and the limit")
	func resettingSilenceClearsSupportAndLimitTogether() {
		let supportInfo = supportInfoWithConfiguration("SILENCE=25")

		#expect(supportInfo.silenceSupported)
		#expect(supportInfo.maximumSilenceEntries == 25)

		supportInfo.resetSetting("silence")

		#expect(supportInfo.silenceSupported == false)
		#expect(supportInfo.maximumSilenceEntries == 0)
	}

	/// `MONITOR=5` says both that the server takes the command and how many
	/// names it will hold. Only the first half was read, so the client kept
	/// adding names the server answered with ERR_MONLISTFULL.
	@Test("MONITOR and WATCH keep the list size they advertise")
	func presenceListCeilingsAreParsed() {
		let supportInfo = supportInfoWithConfiguration("MONITOR=5 WATCH=128")

		#expect(supportInfo.maximumMonitorEntries == 5)
		#expect(supportInfo.maximumWatchEntries == 128)

		supportInfo.processConfigurationData("-MONITOR -WATCH")

		#expect(supportInfo.maximumMonitorEntries == 0)
		#expect(supportInfo.maximumWatchEntries == 0)
	}

	@Test("A bare MONITOR token is support without a ceiling")
	func presenceListCeilingIsZeroWithoutAValue() {
		let supportInfo = supportInfoWithConfiguration("MONITOR WATCH")

		#expect(supportInfo.maximumMonitorEntries == 0)
		#expect(supportInfo.maximumWatchEntries == 0)
	}

	/** `IRCClient.supportInfo` is `lazy`, so the table is built the first time
	 anything reads it — and that can be long after the client recorded the
	 capability facts `WATCH` and `MONITOR` stand in for. Construction used to
	 run the reconnect reset, which withdraws those facts, so the first read of
	 the table turned `WATCH` back off: `enableCapability(.watchCommand)` reads
	 the ceiling on its way to asking about the tracked peers and undid itself,
	 and nothing was ever sent. */
	@Test("Building the table withdraws no capability the client already recorded")
	func aFreshTableWithdrawsNothing() {
		let client = GLTTestClient()
		client.markAsLoggedIn()

		client.enableCapability(.watchCommand)

		#expect(client.isCapabilityEnabled(.watchCommand))
		/* The first read of the lazy table, which is what used to withdraw it. */
		#expect(client.supportInfo.maximumWatchEntries == 0)
		#expect(client.isCapabilityEnabled(.watchCommand))
	}

	/// A reconnect really has lost what the old server advertised, so the reset
	/// that follows one still withdraws the facts those tokens stood in for.
	@Test("Resetting the table after a reconnect withdraws them")
	func aResetWithdrawsTheFacts() {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("WATCH=128")

		#expect(client.isCapabilityEnabled(.watchCommand))

		client.supportInfo.reset()

		#expect(client.isCapabilityEnabled(.watchCommand) == false)
		#expect(client.supportInfo.maximumWatchEntries == 0)
	}

	private func supportInfoWithConfiguration(_ configuration: String) -> SupportInfo {
		let client = GLTTestClient()
		let supportInfo = SupportInfo(client: client)

		supportInfo.processConfigurationData(configuration)

		return supportInfo
	}
}
