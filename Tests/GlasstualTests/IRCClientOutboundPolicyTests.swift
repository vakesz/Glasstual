/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Outbound client policies")
struct IRCClientOutboundPolicyTests {
	@Test("Typing finishes for an empty line, a command, and a network that does not want notifications")
	func typingFinishesForEmptyCommandsAndDisabledNotifications() {
		#expect(OutboundTypingPolicy.shouldFinish(text: "", notificationsEnabled: true))
		#expect(OutboundTypingPolicy.shouldFinish(text: "/join #glasstual", notificationsEnabled: true))
		#expect(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: false))
		#expect(OutboundTypingPolicy.shouldFinish(text: "hello", notificationsEnabled: true) == false)
	}

	@Test("The active notification is resent only once the interval has fully elapsed")
	func typingActiveNotificationIsRateLimitedAtBoundary() {
		let now = Date(timeIntervalSince1970: 100)

		#expect(OutboundTypingPolicy.shouldSendActive(previousState: nil, lastSentAt: nil, now: now))
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-(OutboundTypingPolicy.activeInterval - 0.01)),
			now: now
		) == false)
		#expect(OutboundTypingPolicy.shouldSendActive(
			previousState: .active,
			lastSentAt: now.addingTimeInterval(-OutboundTypingPolicy.activeInterval),
			now: now
		))
	}

	@Test("A CTCP payload is framed and its line breaks flattened")
	func ctcpPayloadFramesAndSanitizesUserText() {
		#expect(
			CTCPPayload.framed(command: "VERSION", text: nil, sanitizingLineBreaks: true) ==
				"\u{01}VERSION\u{01}"
		)
		#expect(
			CTCPPayload.framed(command: "ACTION", text: "first\r\nsecond", sanitizingLineBreaks: true) ==
				"\u{01}ACTION first  second\u{01}"
		)
	}

	@Test("Removing the command from a typed line leaves the attributed arguments intact")
	func commandParserPreservesAttributedArgumentsAfterRemovingCommand() throws {
		let input = NSMutableAttributedString(string: "/MSG nickname hello")
		input.addAttribute(.init("OutboundPolicyTest"), value: true, range: NSRange(location: 14, length: 5))

		let parsed = try #require(ParsedUserCommand(input))

		#expect(parsed.command == "MSG")
		#expect(parsed.arguments.rest == "nickname hello")
		#expect(
			parsed.arguments.attributedRest
				.attribute(.init("OutboundPolicyTest"), at: 9, effectiveRange: nil) as? Bool == true
		)
	}

	@Test("The secret and operator aliases keep the remote command they stand for")
	func messageCommandPolicyPreservesSecretAndOperatorAliases() throws {
		let secretMessage = try #require(
			OutboundMessageCommandPolicy(command: .smsg, silentlyConnecting: false)
		)
		#expect(secretMessage.remoteCommand == .privmsg)
		#expect(secretMessage.isSecretMessage)
		#expect(secretMessage.isOperatorMessage == false)

		let operatorNotice = try #require(
			OutboundMessageCommandPolicy(command: .onotice, silentlyConnecting: false)
		)
		#expect(operatorNotice.remoteCommand == .notice)
		#expect(operatorNotice.isSecretMessage == false)
		#expect(operatorNotice.isOperatorMessage)
	}

	@Test("Connecting silently makes a message secret but leaves an action alone")
	func silentConnectOnlyMakesMessageAliasesSecret() throws {
		let message = try #require(
			OutboundMessageCommandPolicy(command: .msg, silentlyConnecting: true)
		)
		let action = try #require(
			OutboundMessageCommandPolicy(command: .me, silentlyConnecting: true)
		)

		#expect(message.isSecretMessage)
		#expect(action.isSecretMessage == false)
	}

	/// The modifier used to carry its own leading space and `SendingMessage`
	/// added the separator on top, so the line went out `WATCH  +alice +bob`.
	@Test("WATCH separates its nicknames with a single space")
	func watchListLinesCarryOneSpaceBetweenNicknames() {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		client.enableCapability(.watchCommand)

		client.modifyWatchList(byAdding: true, nicknames: ["alice", "bob"])

		#expect(client.sentLines.contains("WATCH +alice +bob"))

		client.modifyWatchList(byAdding: false, nicknames: ["alice"])

		#expect(client.sentLines.contains("WATCH -alice"))
	}

	// MARK: - One parameter per wire token

	/* Every case below sends a command whose parameters used to be joined with
	 spaces into one. The server reads such a parameter as a single token — one
	 nickname called "alice bob carol", one channel called "#one #two" — so the
	 assertions are on the exact line, not on its parts. */

	@Test("The op family sends the mode string and each nickname as its own parameter")
	func userPrivilegeCommandSendsOneParameterPerNickname() throws {
		let client = loggedInClient()
		_ = try #require(client.findChannelOrCreate("#chat"))

		client.sendCommand("op alice bob carol", completeTarget: true, target: "#chat")

		#expect(sentLines(of: client) == ["MODE #chat +ooo alice bob carol"])
	}

	@Test("The server's MODES limit splits one op command into several")
	func userPrivilegeCommandHonoursTheAdvertisedModeCount() throws {
		let client = loggedInClient()
		client.supportInfo.processConfigurationData("MODES=2")
		_ = try #require(client.findChannelOrCreate("#chat"))

		client.sendCommand("op alice bob carol", completeTarget: true, target: "#chat")

		#expect(sentLines(of: client) == ["MODE #chat +oo alice bob", "MODE #chat +o carol"])
	}

	@Test("A mode command keeps its mask a parameter of its own")
	func modeCommandSeparatesTheMaskFromTheModeString() {
		let client = loggedInClient()

		client.sendCommand("mode #chat +b nick!*@*", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["MODE #chat +b nick!*@*"])
	}

	@Test("A user mode command sends each mode string as its own parameter")
	func userModeCommandSendsEachModeStringSeparately() {
		let client = loggedInClient()

		client.sendCommand("umode +s +cfk", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["MODE tester +s", "MODE tester +cfk"])
	}

	/// The channel-properties sheet and the ban sheet both hand `sendModes`
	/// parameters smuggled inside the mode string.
	@Test("Parameters written into the mode string are split back out")
	func sendModesSplitsParametersWrittenIntoTheSymbols() throws {
		let client = loggedInClient()
		let channel = try #require(client.findChannelOrCreate("#chat"))

		client.sendModes("-k+l hunter2 50", withParametersString: nil, in: channel)
		client.sendModes("+k secret", withParametersString: nil, in: channel)
		client.sendModes("-bbb m1 m2 m3", withParametersString: nil, in: channel)
		client.requestModes(for: channel)

		#expect(sentLines(of: client) == [
			"MODE #chat -k+l hunter2 50",
			"MODE #chat +k secret",
			"MODE #chat -bbb m1 m2 m3",
			"MODE #chat",
		])
	}

	@Test("WHO and NAMES send each of their arguments as a parameter")
	func whoAndNamesTokenizeTheirArguments() {
		let client = loggedInClient()

		client.sendCommand("who #chat o", completeTarget: false, target: nil)
		client.sendCommand("names #one #two", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["WHO #chat o", "NAMES #one #two"])
	}

	@Test("ISON sends one nickname per parameter")
	func isonCommandSendsOneNicknamePerParameter() {
		let client = loggedInClient()

		client.sendCommand("ison alice bob", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["ISON alice bob"])
	}

	/// Fifteen is all RFC 1459 gives a command; a sixteenth nickname would be
	/// folded into the fifteenth and asked about as one name.
	@Test("A long ISON list is split at the protocol's parameter count")
	func isonListIsSplitAtFifteenParameters() {
		let client = loggedInClient()
		let nicknames = (1 ... 17).map { "nick\($0)" }

		client.sendIson(forNicknames: nicknames, hideResponse: true)

		#expect(sentLines(of: client) == [
			"ISON " + nicknames.prefix(15).joined(separator: " "),
			"ISON " + nicknames.suffix(2).joined(separator: " "),
		])
	}

	@Test("MONITOR and SILENCE send their subcommand and list as separate parameters")
	func monitorAndSilenceSendArgumentArrays() {
		let client = loggedInClient()
		client.supportInfo.processConfigurationData("SILENCE=15")

		client.sendCommand("monitor L", completeTarget: false, target: nil)
		client.sendCommand("silence +nick!*@*", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["MONITOR L", "SILENCE +nick!*@*"])
	}

	// MARK: - Absent parameters

	@Test("An operator ban with no reason sends no trailing parameter")
	func operatorBansOmitAnAbsentReason() {
		let client = loggedInClient()

		client.sendCommand("gline nick 30d", completeTarget: false, target: nil)
		client.sendCommand("zline nick 30d being rude", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["GLINE nick 30d", "ZLINE nick 30d :being rude"])
	}

	// MARK: - JOIN

	@Test("Keys are comma-separated so that each one pairs with its channel")
	func joinPairsKeysWithChannelsByComma() {
		let client = loggedInClient()

		client.sendCommand("join #a,#b k1 k2", completeTarget: false, target: nil)

		#expect(sentLines(of: client) == ["JOIN #a,#b k1,k2"])
	}

	/// A key with a space in it has no wire spelling at all: as the trailing
	/// parameter it swallows whatever follows it.
	@Test("A key is cut at its first space and at KEYLEN")
	func joinKeysAreSingleTokensWithinKeyLength() {
		let client = loggedInClient()

		client.forceJoinChannel("#chat", password: "hunter2 extra")
		client.supportInfo.processConfigurationData("KEYLEN=4")
		client.forceJoinChannel("#other", password: "hunter2")

		#expect(sentLines(of: client) == ["JOIN #chat hunter2", "JOIN #other hunt"])
	}

	/// Truncating the name would join a different channel, so an over-long one
	/// is not sent at all.
	@Test("A channel name past CHANNELLEN is refused rather than cut")
	func joinRefusesChannelNamesOverTheServerLimit() {
		let client = loggedInClient()
		client.supportInfo.processConfigurationData("CHANNELLEN=6")

		client.forceJoinChannel("#toolongname", password: nil)
		client.forceJoinChannel("#short", password: nil)

		#expect(sentLines(of: client) == ["JOIN #short"])
	}

	// MARK: - Byte budgets on the non-command paths

	@Test("The menu's kick, topic and away paths measure the same budgets the commands do")
	func nonCommandPathsApplyTheServerByteBudgets() throws {
		var preferences = ClientPreferences()
		preferences.defaultKickMessage = "Goodbye everyone"
		let client = GLTTestClient(
			configDictionary: ["nickname": "tester"],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
		client.isConnected = true
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("KICKLEN=7 TOPICLEN=3 AWAYLEN=3 NICKLEN=4")
		let channel = try #require(client.findChannelOrCreate("#chat"))
		channel.activate()

		client.kick("alice", in: channel)
		client.sendTopic(to: "\u{e9}\u{e9}ab", in: channel)
		client.toggleAwayStatus(true, withComment: "\u{e9}\u{e9}ab")
		client.changeNickname("alexander")

		#expect(sentLines(of: client) == [
			"KICK #chat alice :Goodbye",
			"TOPIC #chat :\u{e9}",
			"AWAY :\u{e9}",
			"NICK alex",
		])
	}

	// MARK: - Presence list ceilings

	@Test("The presence list stops at the size the server advertised")
	func watchListStopsAtTheServerCeiling() {
		let client = loggedInClient()
		client.enableCapability(.watchCommand)
		client.supportInfo.processConfigurationData("WATCH=3")

		client.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c", "d", "e"])

		#expect(sentLines(of: client) == ["WATCH +a +b +c"])
	}

	@Test("The monitor list stops at the size the server advertised")
	func monitorListStopsAtTheServerCeiling() {
		let client = loggedInClient()
		client.enableCapability(.monitorCommand)
		client.supportInfo.processConfigurationData("MONITOR=2")

		client.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c"])

		#expect(sentLines(of: client) == ["MONITOR + a,b"])
	}

	/** The address book is where the user put these names, and nothing in the
	 interface would otherwise say why the last of them stop being tracked: the
	 drop was a line in the unified log and nowhere the user looks. */
	@Test("The presence-list ceiling is reported where the user can see it")
	func theWatchCeilingIsReportedInTheTranscript() {
		let client = loggedInClient()
		client.enableCapability(.watchCommand)
		client.supportInfo.processConfigurationData("WATCH=3")

		client.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c", "d", "e"])

		expectPrintedLineContaining(
			IRCISupportStrings.presenceListIsFull(droppedCount: 2, ceiling: 3),
			on: client
		)
	}

	/** `CHANNELLEN` was applied silently: the join was dropped and the sidebar
	 kept the channel, so the user was left with a row that never connected and
	 no reason given. */
	@Test("A channel name the server would refuse is reported by name")
	func anOverLongChannelNameIsReported() {
		let client = loggedInClient()
		client.supportInfo.processConfigurationData("CHANTYPES=# CHANNELLEN=8")

		client.joinUnlistedChannel("#waytoolongforthisserver")

		#expect(sentLines(of: client).isEmpty)
		expectPrintedLineContaining(
			IRCISupportStrings.channelNameTooLong(
				channelName: "#waytoolongforthisserver",
				maximumLength: 8
			),
			on: client
		)
	}

	// MARK: - CTCP replies

	@Test("One sender gets a bounded number of CTCP replies a minute")
	func ctcpRepliesAreThrottledPerSender() {
		var throttle = CTCPReplyThrottle()
		let start = Date(timeIntervalSince1970: 1000)
		let allowed = (0 ..< CTCPReplyThrottle.perSenderLimit + 2).map { _ in
			throttle.recordReply(to: "alice", at: start)
		}

		// Another sender is unaffected, and the window slides.
		let otherSender = throttle.recordReply(to: "bob", at: start)
		let afterTheWindow = throttle.recordReply(
			to: "alice",
			at: start.addingTimeInterval(CTCPReplyThrottle.window + 1)
		)

		#expect(allowed.filter(\.self).count == CTCPReplyThrottle.perSenderLimit)
		#expect(otherSender)
		#expect(afterTheWindow)
	}

	@Test("A CTCP flood from many senders stops at the overall ceiling")
	func ctcpRepliesAreThrottledOverall() {
		var throttle = CTCPReplyThrottle()
		let now = Date(timeIntervalSince1970: 1000)
		let allowed = (0 ..< 200).map { throttle.recordReply(to: "sender\($0)", at: now) }

		/* The ceiling holds for the rest of the window, including for a sender
		 who has not asked before, and lifts once the window has slid past it. */
		let latecomer = throttle.recordReply(to: "latecomer", at: now)
		let afterTheWindow = throttle.recordReply(
			to: "latecomer",
			at: now.addingTimeInterval(CTCPReplyThrottle.window + 1)
		)

		#expect(allowed.filter(\.self).count == CTCPReplyThrottle.overallLimit)
		#expect(latecomer == false)
		#expect(afterTheWindow)
	}

	@Test("A flood of CTCP queries does not queue one NOTICE per query")
	func ctcpQueryFloodSendsBoundedReplies() throws {
		var preferences = ClientPreferences()
		preferences.replyToCTCPRequests = true
		let client = GLTTestClient(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: GLTClientEnvironmentFixture(preferences: preferences)
		)
		client.isConnected = true
		client.markAsLoggedIn()

		for _ in 0 ..< 20 {
			let message = try #require(
				Message(line: ":alice!u@h PRIVMSG me :\u{01}VERSION\u{01}", on: client)
			)
			client.receivePrivmsgAndNotice(message)
		}

		#expect(sentLines(of: client).count == CTCPReplyThrottle.perSenderLimit)
	}

	@Test("A CTCP PING echo that is not a timestamp is reported without a lag")
	func ctcpPingReplyWithoutATimestampIsNotTimed() throws {
		let client = GLTTestClient(configDictionary: ["nickname": "me"])
		client.isConnected = true
		client.markAsLoggedIn()
		let message = try #require(
			Message(line: ":alice!u@h NOTICE me :\u{01}PING not-a-number\u{01}", on: client)
		)

		client.receivePrivmsgAndNotice(message)

		/* Read as zero, the echo dated the ping to 1970 and the client reported
		 a lag of fifty-six years; the untimed form is the honest one. */
		let printed = client.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(printed.contains(IRCCTCPStrings.reply(sender: "alice", command: "PING", arguments: "not-a-number")))
	}

	// MARK: - Helpers

	private func loggedInClient() -> GLTTestClient {
		CommandIndex.populateCommandIndex()

		let client = GLTTestClient(configDictionary: ["nickname": "tester"])

		client.isConnected = true
		client.markAsLoggedIn()

		return client
	}

	private func sentLines(of client: GLTTestClient) -> [String] {
		client.sentLines.compactMap { $0 as? String }
	}

	private func expectPrintedLineContaining(_ text: String, on client: GLTTestClient) {
		let bodies = client.printedLines.compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains(text) })
	}
}
