/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRC string catalog")
struct IRCStringCatalogMigrationTests {
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
}
