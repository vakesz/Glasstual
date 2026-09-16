/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC string catalog")
struct StringCatalogTests {
	@Test("Generated and legacy formatters place the same values in the same order")
	func generatedAndLegacyFormatterBoundariesPreservePlaceholders() {
		let topicTooLong = "You have exceeded the maximum topic length for Libera.Chat which is 390 characters. "
			+ "The end of your topic may have been cut off."

		#expect(CommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 390) == topicTooLong)
		#expect(
			ConnectionStrings.connecting(host: "irc.example", port: 6697)
				== "Connecting to [irc.example] on port 6697"
		)
		#expect(
			DCCFileTransferStrings.request(nickname: "Alice", filename: "archive.zip", byteCount: 1024)
				== "Received file transfer request from Alice, archive.zip (1 kB)"
		)
	}

	@Test("Typed selections pick the same entry the untyped lookups used to")
	func typedDynamicSelectionsPreserveBehavior() {
		#expect(TimerStrings.status(active: true) == "Active")
		#expect(TimerStrings.help(topic: .restart).contains("/timer restart <identifier>"))
		#expect(CTCPStrings.lagRating(.excellent) == "Yeah, okay…")
		#expect(CTCPStrings.lagRating(.verySlow) == "Very slow")
		#expect(
			ISupportStrings.extendedBanDescription(type: "a", argument: "staff")
				== "Users logged in to account “staff”"
		)
		#expect(
			ISupportStrings.extendedBanDescription(type: "?", argument: "mask")
				== "Extended ban of type “?”: mask"
		)
		#expect(
			ChannelAccessListStrings.entry(
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
			CommandStrings.setNameUnsupported
				== "This server does not support changing the real name (setname)"
		)
	}

	/** Every one of these used to read "1 characters", "1 users left" or
	 "1 seconds": the count was interpolated into a fixed English plural, so no
	 translation could agree with its own grammar either. */
	@Test("Every counted console line reads its singular and its plural")
	func countedConsoleLinesPluralizeTheirCounts() {
		#expect(
			ConnectionStrings.delayedAutoConnect(seconds: 1) == "Delaying auto connect for 1 second"
		)
		#expect(
			ConnectionStrings.delayedAutoConnect(seconds: 30) == "Delaying auto connect for 30 seconds"
		)

		#expect(
			CommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 1)
				.contains("which is 1 character.")
		)
		#expect(
			CommandStrings.kickMessageTooLong(networkName: "Libera.Chat", maximumLength: 1)
				.contains("which is 1 character.")
		)
		#expect(
			CommandStrings.awayMessageTooLong(networkName: "Libera.Chat", maximumLength: 300)
				.contains("which is 300 characters.")
		)

		#expect(
			ISupportStrings.channelNameTooLong(channelName: "#swift", maximumLength: 1)
				.hasSuffix("channel names of at most 1 character.")
		)
		#expect(
			ISupportStrings.channelLimitExceeded(channelName: "#swift", limit: 1, prefix: "#")
				.contains("the limit of 1 channel with")
		)
		#expect(
			ISupportStrings.presenceListIsFull(droppedCount: 2, ceiling: 1)
				.hasSuffix("keeps at most 1 presence entry.")
		)

		#expect(
			InboundStrings.History.netsplit(
				firstServer: "irc.hub",
				secondServer: "irc.leaf",
				userCount: 1,
				nicknames: "alice"
			).contains(": 1 user left (")
		)
		#expect(
			InboundStrings.History.netjoin(
				firstServer: "irc.hub",
				secondServer: "irc.leaf",
				userCount: 1,
				nicknames: "alice"
			).contains(": 1 user rejoined (")
		)
		#expect(InboundStrings.History.abbreviatedNicknames("alice", remaining: 1) == "alice, … and 1 more")
	}

	/// `Int32(numeric)` trapped on the error path for an oversized numeric.
	@Test("A malformed-message diagnostic survives an oversized numeric")
	func malformedMessageStringSurvivesAnOversizedNumeric() {
		#expect(DiagnosticStrings.malformedMessage(numeric: 99_999_999_999, sequence: "x").isEmpty == false)
		#expect(DiagnosticStrings.malformedMessage(numeric: UInt.max, sequence: "x").isEmpty == false)
	}
}
