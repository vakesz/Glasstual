/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC string catalog")
struct IRCStringCatalogTests {
	@Test("Generated and legacy formatters place the same values in the same order")
	func generatedAndLegacyFormatterBoundariesPreservePlaceholders() {
		let topicTooLong = "You have exceeded the maximum topic length for Libera.Chat which is 390 characters. "
			+ "The end of your topic may have been cut off."

		#expect(IRCCommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 390) == topicTooLong)
		#expect(
			IRCConnectionStrings.connecting(host: "irc.example", port: 6697)
				== "Connecting to [irc.example] on port 6697"
		)
		#expect(
			IRCFileTransferStrings.request(nickname: "Alice", filename: "archive.zip", byteCount: 1024)
				== "Received file transfer request from Alice, archive.zip (1 kB)"
		)
	}

	@Test("Typed selections pick the same entry the untyped lookups used to")
	func typedDynamicSelectionsPreserveBehavior() {
		#expect(IRCTimerStrings.status(active: true) == "Active")
		#expect(IRCTimerStrings.help(topic: .restart).contains("/timer restart <identifier>"))
		#expect(IRCCTCPStrings.lagRating(.excellent) == "Yeah, okay…")
		#expect(IRCCTCPStrings.lagRating(.verySlow) == "Very slow")
		#expect(
			IRCISupportStrings.extendedBanDescription(type: "a", argument: "staff")
				== "Users logged in to account “staff”"
		)
		#expect(
			IRCISupportStrings.extendedBanDescription(type: "?", argument: "mask")
				== "Extended ban of type “?”: mask"
		)
		#expect(
			IRCChannelAccessListStrings.entry(
				kind: .ban,
				channelName: "#swift",
				mask: "*!*@example",
				setBy: "Alice",
				date: "26 Aug 2026"
			) == "Ban in #swift: *!*@example set by Alice on 26 Aug 2026"
		)
	}

	@Test("The retained setname entry still reads back")
	func setNameUsesRetainedCatalogEntry() {
		#expect(
			IRCCommandStrings.setNameUnsupported
				== "This server does not support changing the real name (setname)"
		)
	}

	/** Every one of these used to read "1 characters", "1 users left" or
	 "1 seconds": the count was interpolated into a fixed English plural, so no
	 translation could agree with its own grammar either. */
	@Test("Every counted console line reads its singular and its plural")
	func countedConsoleLinesPluralizeTheirCounts() {
		#expect(
			IRCConnectionStrings.delayedAutoConnect(seconds: 1) == "Delaying auto connect for 1 second"
		)
		#expect(
			IRCConnectionStrings.delayedAutoConnect(seconds: 30) == "Delaying auto connect for 30 seconds"
		)

		#expect(
			IRCCommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 1)
				.contains("which is 1 character.")
		)
		#expect(
			IRCCommandStrings.kickMessageTooLong(networkName: "Libera.Chat", maximumLength: 1)
				.contains("which is 1 character.")
		)
		#expect(
			IRCCommandStrings.awayMessageTooLong(networkName: "Libera.Chat", maximumLength: 300)
				.contains("which is 300 characters.")
		)

		#expect(
			IRCISupportStrings.channelNameTooLong(channelName: "#swift", maximumLength: 1)
				.hasSuffix("channel names of at most 1 character.")
		)
		#expect(
			IRCISupportStrings.channelLimitExceeded(channelName: "#swift", limit: 1, prefix: "#")
				.contains("the limit of 1 channel with")
		)
		#expect(
			IRCISupportStrings.presenceListIsFull(droppedCount: 2, ceiling: 1)
				.hasSuffix("keeps at most 1 presence entry.")
		)

		#expect(
			IRCInboundStrings.History.netsplit(
				firstServer: "irc.hub",
				secondServer: "irc.leaf",
				userCount: 1,
				nicknames: "alice"
			).contains(": 1 user left (")
		)
		#expect(
			IRCInboundStrings.History.netjoin(
				firstServer: "irc.hub",
				secondServer: "irc.leaf",
				userCount: 1,
				nicknames: "alice"
			).contains(": 1 user rejoined (")
		)
		#expect(IRCInboundStrings.History.abbreviatedNicknames("alice", remaining: 1) == "alice, … and 1 more")
	}
}
