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

		#expect(String(localized: .IRC.youHaveExceededTheMaximumTopic("Libera.Chat", arg2: 390)) == topicTooLong)
		#expect(
			String(localized: .IRC.connectingToOnPort("irc.example", String(6697)))
				== "Connecting to [irc.example] on port 6697"
		)
		#expect(
			String(
				localized: .IRC.receivedFileTransferRequest(
					"Alice",
					"archive.zip",
					LocalizedByteCount.formatted(1024)
				)
			) == "Received file transfer request from Alice, archive.zip (1 kB)"
		)
	}

	@Test("Typed selections pick the same entry the untyped lookups used to")
	func typedDynamicSelectionsPreserveBehavior() {
		#expect(String(localized: .IRC.timerCommandActive) == "Active")
		#expect(TimerHelpTopic.helpText(for: .restart).contains("/timer restart <identifier>"))
		#expect(CTCPLagRating.excellent.ratingText == "Yeah, okay…")
		#expect(CTCPLagRating.verySlow.ratingText == "Very slow")
		#expect(
			ExtendedBanKind.describing(type: "a", argument: "staff")
				== "Users logged in to account “staff”"
		)
		#expect(
			ExtendedBanKind.describing(type: "?", argument: "mask")
				== "Extended ban of type “?”: mask"
		)
		#expect(
			ChannelBanListKind.ban.entryText(
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
			String(localized: .IRC.thisServerDoesNotSupportChanging)
				== "This server does not support changing the real name (setname)"
		)
	}

	/** Every one of these used to read "1 characters", "1 users left" or
	 "1 seconds": the count was interpolated into a fixed English plural, so no
	 translation could agree with its own grammar either. */
	@Test("Every counted console line reads its singular and its plural")
	func countedConsoleLinesPluralizeTheirCounts() {
		#expect(
			String(localized: .IRC.delayingAutoConnectForSeconds(arg1: UInt(1))) == "Delaying auto connect for 1 second"
		)
		#expect(
			String(localized: .IRC.delayingAutoConnectForSeconds(arg1: UInt(30))) == "Delaying auto connect for 30 seconds"
		)

		#expect(
			String(localized: .IRC.youHaveExceededTheMaximumTopic("Libera.Chat", arg2: 1))
				.contains("which is 1 character.")
		)
		#expect(
			String(localized: .IRC.youHaveExceededTheMaximumKick("Libera.Chat", arg2: 1))
				.contains("which is 1 character.")
		)
		#expect(
			String(localized: .IRC.youHaveExceededTheMaximumAway("Libera.Chat", arg2: 300))
				.contains("which is 300 characters.")
		)

		#expect(
			String(localized: .IRC.joinRefusedNameTooLong("#swift", arg2: 1))
				.hasSuffix("channel names of at most 1 character.")
		)
		#expect(
			String(localized: .IRC.joiningWouldExceedTheLimit("#swift", arg2: UInt(1), "#"))
				.contains("the limit of 1 channel with")
		)
		#expect(
			String(localized: .IRC.presenceListIsFull(2, arg2: 1))
				.hasSuffix("keeps at most 1 presence entry.")
		)

		#expect(
			String(localized: .IRC.netsplitBetweenAndUsersLeft("irc.hub", "irc.leaf", arg3: UInt(1), "alice"))
				.contains(": 1 user left (")
		)
		#expect(
			String(localized: .IRC.netjoinBetweenAndUsersRejoined("irc.hub", "irc.leaf", arg3: UInt(1), "alice"))
				.contains(": 1 user rejoined (")
		)
		#expect(String(localized: .IRC.netsplitAndNetjoinSummariesMore("alice", arg2: UInt(1))) == "alice, … and 1 more")
	}

	/// `Int32(numeric)` trapped on the error path for an oversized numeric.
	@Test("A malformed-message diagnostic survives an oversized numeric")
	func malformedMessageStringSurvivesAnOversizedNumeric() {
		#expect(String(localized: .IRC.miscellaneousMessagesRelatedMessage(Int32(exactly: UInt(99_999_999_999)) ?? 0, "x"))
			.isEmpty == false)
		#expect(String(localized: .IRC.miscellaneousMessagesRelatedMessage(Int32(exactly: UInt.max) ?? 0, "x")).isEmpty == false)
	}
}
