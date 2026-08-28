/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class LocalizationCatalogBoundaryTests: XCTestCase {
	func testServerChannelListCopyAndFormatting() {
		XCTAssertEqual(ServerChannelListStrings.heading(networkName: "Libera.Chat"), "Channel List for “Libera.Chat”")
		XCTAssertEqual(
			ServerChannelListStrings.windowTitle(publicChannelCount: 42),
			"Channel List — 42 Public Channels"
		)
	}

	func testChannelAccessListCopyAndFormatting() {
		XCTAssertEqual(
			ChannelAccessListStrings.heading(for: .ban, channelName: "#swift"),
			"Bans in #swift"
		)
		XCTAssertEqual(
			ChannelAccessListStrings.heading(for: .banException, channelName: "#swift"),
			"Ban Exceptions in #swift"
		)
		XCTAssertEqual(
			ChannelAccessListStrings.heading(for: .inviteException, channelName: "#swift"),
			"Invite Exceptions in #swift"
		)
		XCTAssertEqual(
			ChannelAccessListStrings.heading(for: .quiet, channelName: "#swift"),
			"Quiets in #swift"
		)
		XCTAssertEqual(ChannelAccessListStrings.entryCount(4, maximum: 0), "4 entries")
		XCTAssertEqual(ChannelAccessListStrings.entryCount(4, maximum: 100), "4 of 100 entries")
	}

	func testChannelSpotlightCopyAndFormatting() {
		XCTAssertEqual(ChannelSpotlightStrings.channelName("#swift"), "#swift")
		XCTAssertEqual(ChannelSpotlightStrings.networkSuffix("Libera.Chat"), " on Libera.Chat")
		XCTAssertEqual(ChannelSpotlightStrings.unreadMessages(1), "1 unread message")
		XCTAssertEqual(ChannelSpotlightStrings.unreadMessages(2), "2 unread messages")
		XCTAssertEqual(ChannelSpotlightStrings.highlights(1), "1 highlight")
		XCTAssertEqual(ChannelSpotlightStrings.highlights(2), "2 highlights")
		XCTAssertEqual(
			ChannelSpotlightStrings.combined("1 highlight", "2 unread messages"),
			"1 highlight, 2 unread messages"
		)
	}
}
