/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import XCTest

@MainActor
final class IRCStringCatalogMigrationTests: XCTestCase {
	func testGeneratedAndLegacyFormatterBoundariesPreservePlaceholders() {
		XCTAssertEqual(
			IRCCommandStrings.topicTooLong(networkName: "Libera.Chat", maximumLength: 390),
			"You have exceeded the maximum topic length for Libera.Chat which is 390 characters. "
				+ "The end of your topic may have been cut off."
		)
		XCTAssertEqual(
			IRCConnectionStrings.connecting(host: "irc.example", port: 6697),
			"Connecting to [irc.example] on port 6697"
		)
		XCTAssertEqual(
			IRCFileTransferStrings.request(nickname: "Alice", filename: "archive.zip", byteCount: 1024),
			"Received file transfer request from Alice, archive.zip (1 kB)"
		)
	}

	func testTypedDynamicSelectionsPreserveBehavior() {
		XCTAssertEqual(IRCTimerStrings.status(active: true), "Active")
		XCTAssertTrue(IRCTimerStrings.help(topic: .restart).contains("/timer restart <identifier>"))
		XCTAssertEqual(IRCCTCPStrings.lagRating(.excellent), "Yeah, okay…")
		XCTAssertEqual(IRCCTCPStrings.lagRating(.verySlow), "Very slow")
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "a", argument: "staff"),
			"Users logged in to account “staff”"
		)
		XCTAssertEqual(
			IRCISupportStrings.extendedBanDescription(type: "?", argument: "mask"),
			"Extended ban of type “?”: mask"
		)
		XCTAssertEqual(
			IRCChannelAccessListStrings.entry(
				kind: .ban,
				channelName: "#swift",
				mask: "*!*@example",
				setBy: "Alice",
				date: "26 Aug 2026"
			),
			"Ban in #swift: *!*@example set by Alice on 26 Aug 2026"
		)
	}

	func testSetNameUsesRetainedCatalogEntry() {
		XCTAssertEqual(
			IRCCommandStrings.setNameUnsupported,
			"This server does not support changing the real name (setname)"
		)
	}
}
