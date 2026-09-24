// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Outbound session policies")
struct ServerSessionOutboundPolicyTests {
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
			OutboundMessageOptions(command: .smsg, silentlyConnecting: false)
		)
		#expect(secretMessage.remoteCommand == .privmsg)
		#expect(secretMessage.isSecretMessage)
		#expect(secretMessage.isOperatorMessage == false)

		let operatorNotice = try #require(
			OutboundMessageOptions(command: .onotice, silentlyConnecting: false)
		)
		#expect(operatorNotice.remoteCommand == .notice)
		#expect(operatorNotice.isSecretMessage == false)
		#expect(operatorNotice.isOperatorMessage)
	}

	@Test("Connecting silently makes a message secret but leaves an action alone")
	func silentConnectOnlyMakesMessageAliasesSecret() throws {
		let message = try #require(
			OutboundMessageOptions(command: .msg, silentlyConnecting: true)
		)
		let action = try #require(
			OutboundMessageOptions(command: .me, silentlyConnecting: true)
		)

		#expect(message.isSecretMessage)
		#expect(action.isSecretMessage == false)
	}

	/// The modifier used to carry its own leading space and `SendingMessage`
	/// added the separator on top, so the line went out `WATCH  +alice +bob`.
	@Test("WATCH separates its nicknames with a single space")
	func watchListLinesCarryOneSpaceBetweenNicknames() {
		let session = TestServerSession()
		session.markAsLoggedIn()
		session.enableCapability(.watchCommand)

		session.modifyWatchList(byAdding: true, nicknames: ["alice", "bob"])

		#expect(session.sentLines.contains("WATCH +alice +bob"))

		session.modifyWatchList(byAdding: false, nicknames: ["alice"])

		#expect(session.sentLines.contains("WATCH -alice"))
	}

	// MARK: - One parameter per wire token

	/* Every case below sends a command whose parameters used to be joined with
	 spaces into one. The server reads such a parameter as a single token — one
	 nickname called "alice bob carol", one channel called "#one #two" — so the
	 assertions are on the exact line, not on its parts. */

	@Test("The op family sends the mode string and each nickname as its own parameter")
	func userPrivilegeCommandSendsOneParameterPerNickname() throws {
		let session = loggedInSession()
		_ = try #require(session.findConversationOrCreate("#chat"))

		session.sendCommand("op alice bob carol", completeTarget: true, target: "#chat")

		#expect(sentLines(of: session) == ["MODE #chat +ooo alice bob carol"])
	}

	@Test("The server's MODES limit splits one op command into several")
	func userPrivilegeCommandHonoursTheAdvertisedModeCount() throws {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("MODES=2")
		_ = try #require(session.findConversationOrCreate("#chat"))

		session.sendCommand("op alice bob carol", completeTarget: true, target: "#chat")

		#expect(sentLines(of: session) == ["MODE #chat +oo alice bob", "MODE #chat +o carol"])
	}

	@Test("A mode command keeps its mask a parameter of its own")
	func modeCommandSeparatesTheMaskFromTheModeString() {
		let session = loggedInSession()

		session.sendCommand("mode #chat +b nick!*@*", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["MODE #chat +b nick!*@*"])
	}

	@Test("A user mode command sends each mode string as its own parameter")
	func userModeCommandSendsEachModeStringSeparately() {
		let session = loggedInSession()

		session.sendCommand("umode +s +cfk", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["MODE tester +s", "MODE tester +cfk"])
	}

	/// The channel-properties sheet and the ban sheet both hand `sendModes`
	/// parameters smuggled inside the mode string.
	@Test("Parameters written into the mode string are split back out")
	func sendModesSplitsParametersWrittenIntoTheSymbols() throws {
		let session = loggedInSession()
		let channel = try #require(session.findConversationOrCreate("#chat"))

		session.sendModes("-k+l hunter2 50", withParametersString: nil, inChannelNamed: channel.name)
		session.sendModes("+k secret", withParametersString: nil, inChannelNamed: channel.name)
		session.sendModes("-bbb m1 m2 m3", withParametersString: nil, inChannelNamed: channel.name)
		session.requestModes(inChannelNamed: channel.name)

		#expect(sentLines(of: session) == [
			"MODE #chat -k+l hunter2 50",
			"MODE #chat +k secret",
			"MODE #chat -bbb m1 m2 m3",
			"MODE #chat",
		])
	}

	@Test("A mode parameter that starts with a sign is paired with its mode, not read as a mode string")
	func signedModeParameterIsNotReadAsModeString() throws {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("CHANMODES=beI,k,l,imnpst PREFIX=(ov)@+")
		let channel = try #require(session.findConversationOrCreate("#chat"))

		session.sendModes("+k +secret", withParametersString: nil, inChannelNamed: channel.name)
		session.sendModes("+b -bad!*@* +m", withParametersString: nil, inChannelNamed: channel.name)
		session.sendModes("-l +i", withParametersString: nil, inChannelNamed: channel.name)

		#expect(sentLines(of: session) == [
			"MODE #chat +k +secret",
			"MODE #chat +b -bad!*@*",
			"MODE #chat +m",
			"MODE #chat -l",
			"MODE #chat +i",
		])
	}

	@Test("WHO and NAMES send each of their arguments as a parameter")
	func whoAndNamesTokenizeTheirArguments() {
		let session = loggedInSession()

		session.sendCommand("who #chat o", completeTarget: false, target: nil)
		session.sendCommand("names #one #two", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["WHO #chat o", "NAMES #one #two"])
	}

	@Test("ISON sends one nickname per parameter")
	func isonCommandSendsOneNicknamePerParameter() {
		let session = loggedInSession()

		session.sendCommand("ison alice bob", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["ISON alice bob"])
	}

	/// Fifteen is all RFC 1459 gives a command; a sixteenth nickname would be
	/// folded into the fifteenth and asked about as one name.
	@Test("A long ISON list is split at the protocol's parameter count")
	func isonListIsSplitAtFifteenParameters() {
		let session = loggedInSession()
		let nicknames = (1 ... 17).map { "nick\($0)" }

		session.sendIson(forNicknames: nicknames, hideResponse: true)

		#expect(sentLines(of: session) == [
			"ISON " + nicknames.prefix(15).joined(separator: " "),
			"ISON " + nicknames.suffix(2).joined(separator: " "),
		])
	}

	@Test("MONITOR and SILENCE send their subcommand and list as separate parameters")
	func monitorAndSilenceSendArgumentArrays() {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("SILENCE=15")

		session.sendCommand("monitor L", completeTarget: false, target: nil)
		session.sendCommand("silence +nick!*@*", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["MONITOR L", "SILENCE +nick!*@*"])
	}

	// MARK: - Absent parameters

	@Test("An operator ban with no reason sends no trailing parameter")
	func operatorBansOmitAnAbsentReason() {
		let session = loggedInSession()

		session.sendCommand("gline nick 30d", completeTarget: false, target: nil)
		session.sendCommand("zline nick 30d being rude", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["GLINE nick 30d", "ZLINE nick 30d :being rude"])
	}

	// MARK: - JOIN

	@Test("Keys are comma-separated so that each one pairs with its channel")
	func joinPairsKeysWithChannelsByComma() {
		let session = loggedInSession()

		session.sendCommand("join #a,#b k1 k2", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["JOIN #a,#b k1,k2"])
	}

	/// `/join a,b,c` went out as one line however long the list, and none of
	/// the channels already in the sidebar showed that it was being joined.
	@Test("A typed channel list is batched to the line budget and listed channels show they are joining")
	func typedJoinListIsBatchedAndMarksChannelsJoining() throws {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("TARGMAX=JOIN:2")
		let listed = try #require(session.findConversationOrCreate("#b"))

		session.sendCommand("join #a,#b,#c", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["JOIN #a,#b", "JOIN #c"])
		#expect(listed.status == .joining)
	}

	@Test("Keys stay with their channels when a channel before them is refused")
	func typedJoinKeysPairWithTheirOwnChannels() {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("CHANNELLEN=6")

		session.sendCommand("join #toolong,#ok,#free first second", completeTarget: false, target: nil)

		#expect(sentLines(of: session) == ["JOIN #free", "JOIN #ok second"])
	}

	@Test("A key with a comma in it is not sent, since the server would read two keys")
	func keyWithACommaIsRefused() {
		#expect(OutboundJoinPolicy.sanitizedKey("a,b", maximumLength: 0) == nil)
		#expect(OutboundJoinPolicy.sanitizedKey("ab", maximumLength: 0) == "ab")
	}

	/// A key with a space in it has no wire spelling at all: as the trailing
	/// parameter it swallows whatever follows it.
	@Test("A key is cut at its first space and at KEYLEN")
	func joinKeysAreSingleTokensWithinKeyLength() {
		let session = loggedInSession()

		session.forceJoinChannel("#chat", password: "hunter2 extra")
		session.supportInfo.processConfigurationData("KEYLEN=4")
		session.forceJoinChannel("#other", password: "hunter2")

		#expect(sentLines(of: session) == ["JOIN #chat hunter2", "JOIN #other hunt"])
	}

	/// Truncating the name would join a different channel, so an over-long one
	/// is not sent at all.
	@Test("A channel name past CHANNELLEN is refused rather than cut")
	func joinRefusesChannelNamesOverTheServerLimit() {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("CHANNELLEN=6")

		session.forceJoinChannel("#toolongname", password: nil)
		session.forceJoinChannel("#short", password: nil)

		#expect(sentLines(of: session) == ["JOIN #short"])
	}

	// MARK: - Byte budgets on the non-command paths

	@Test("The menu's kick, topic and away paths measure the same budgets the commands do")
	func nonCommandPathsApplyTheServerByteBudgets() throws {
		var settings = ChatSettings()
		settings.defaultKickMessage = "Goodbye everyone"
		let session = TestServerSession(
			configDictionary: ["nickname": "tester"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("KICKLEN=7 TOPICLEN=3 AWAYLEN=3 NICKLEN=4")
		let channel = try #require(session.findConversationOrCreate("#chat"))
		channel.activate()

		session.kick("alice", in: channel)
		session.sendTopic(to: "\u{e9}\u{e9}ab", in: channel)
		session.toggleAwayStatus(true, withComment: "\u{e9}\u{e9}ab")
		session.changeNickname("alexander")

		#expect(sentLines(of: session) == [
			"KICK #chat alice :Goodbye",
			"TOPIC #chat :\u{e9}",
			"AWAY :\u{e9}",
			"NICK alex",
		])
	}

	// MARK: - Presence list ceilings

	@Test("The presence list stops at the size the server advertised")
	func watchListStopsAtTheServerCeiling() {
		let session = loggedInSession()
		session.enableCapability(.watchCommand)
		session.supportInfo.processConfigurationData("WATCH=3")

		session.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c", "d", "e"])

		#expect(sentLines(of: session) == ["WATCH +a +b +c"])
	}

	@Test("The monitor list stops at the size the server advertised")
	func monitorListStopsAtTheServerCeiling() {
		let session = loggedInSession()
		session.enableCapability(.monitorCommand)
		session.supportInfo.processConfigurationData("MONITOR=2")

		session.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c"])

		#expect(sentLines(of: session) == ["MONITOR + a,b"])
	}

	/** The address book is where the user put these names, and nothing in the
	 interface would otherwise say why the last of them stop being tracked: the
	 drop was a line in the unified log and nowhere the user looks. */
	@Test("The presence-list ceiling is reported where the user can see it")
	func theWatchCeilingIsReportedInTheTranscript() {
		let session = loggedInSession()
		session.enableCapability(.watchCommand)
		session.supportInfo.processConfigurationData("WATCH=3")

		session.modifyWatchList(byAdding: true, nicknames: ["a", "b", "c", "d", "e"])

		expectPrintedLineContaining(
			String(localized: .IRC.presenceListIsFull(2, arg2: Int(clamping: 3))),
			on: session
		)
	}

	/** `CHANNELLEN` was applied silently: the join was dropped and the sidebar
	 kept the channel, so the user was left with a row that never connected and
	 no reason given. */
	@Test("A channel name the server would refuse is reported by name")
	func anOverLongChannelNameIsReported() {
		let session = loggedInSession()
		session.supportInfo.processConfigurationData("CHANTYPES=# CHANNELLEN=8")

		session.joinUnlistedChannel("#waytoolongforthisserver")

		#expect(sentLines(of: session).isEmpty)
		expectPrintedLineContaining(
			String(localized: .IRC.joinRefusedNameTooLong("#waytoolongforthisserver", arg2: Int(clamping: 8))),
			on: session
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
		var settings = ChatSettings()
		settings.replyToCTCPRequests = true
		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()

		for _ in 0 ..< 20 {
			let message = try #require(
				Message(line: ":alice!u@h PRIVMSG me :\u{01}VERSION\u{01}", on: session)
			)
			session.receivePrivmsgAndNotice(message)
		}

		#expect(sentLines(of: session).count == CTCPReplyThrottle.perSenderLimit)
	}

	@Test("A CTCP PING echo that is not a timestamp is reported without a lag")
	func ctcpPingReplyWithoutATimestampIsNotTimed() throws {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		let message = try #require(
			Message(line: ":alice!u@h NOTICE me :\u{01}PING not-a-number\u{01}", on: session)
		)

		session.receivePrivmsgAndNotice(message)

		/* Read as zero, the echo dated the ping to 1970 and the session reported
		 a lag of fifty-six years; the untimed form is the honest one. */
		let printed = session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
		#expect(printed.contains(String(localized: .IRC.ctcp("alice", "PING", "not-a-number"))))
	}

	// MARK: - Helpers

	private func loggedInSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "tester"])

		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()

		return session
	}

	private func sentLines(of session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	private func expectPrintedLineContaining(_ text: String, on session: TestServerSession) {
		let bodies = session.printedLines.compactMap {
			($0 as? [String: Any])?["messageBody"] as? String
		}

		#expect(bodies.contains { $0.contains(text) })
	}
}
