/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

final class LocalizationCatalogBoundaryTests: XCTestCase {
	func testAddressBookAndServerEndpointValidationCopy() {
		XCTAssertEqual(
			AddressBookStrings.invalidIgnoreMask,
			"Please enter a properly formatted ignore mask."
		)
		XCTAssertEqual(
			ServerEndpointStrings.invalidAddressDescription,
			"The value you entered is not a properly formatted server address"
		)
		XCTAssertEqual(ServerEndpointStrings.invalidAddressRecoverySuggestion, "")
		XCTAssertEqual(
			ServerEndpointStrings.invalidPortDescription,
			"The value you entered is not a properly formatted server port"
		)
		XCTAssertEqual(
			ServerEndpointStrings.invalidPortRecoverySuggestion,
			"Enter a whole number between 1 and 65,535."
		)
	}

	func testUserStyleDefaultRulesPreserveFormatting() {
		let expectedRules = [
			"/*",
			"",
			"!!! WARNING: THIS IS DESIGNED FOR ADVANCED USERS. !!!",
			"",
			"Styles are written in HTML which means custom rules should be",
			"written in CSS: https://developer.mozilla.org/en-US/docs/Web/CSS",
			"",
			"- Example: ",
			"",
			"#topicBar {",
			"\tdisplay: none;",
			"}",
			"",
			"Glasstual does not perform sanitation in any form on your rules",
			"which means you could possibly abuse this feature by escaping",
			"from the style element and inserting JavaScript or other code.",
			"",
			"*/",
		].joined(separator: "\n")

		XCTAssertEqual(UserStyleStrings.defaultRules, expectedRules)
	}

	func testServerChannelListCopyAndFormatting() {
		XCTAssertEqual(ServerChannelListStrings.heading(networkName: "Libera.Chat"), "Channel List for “Libera.Chat”")
		XCTAssertEqual(ServerChannelListStrings.minimumUserCountLabel, "Minimum users:")
		XCTAssertEqual(
			ServerChannelListStrings.minimumUserCountHint,
			"Only list channels with at least this many members. The server applies this filter (ELIST)."
		)
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

	func testMessageMenuCopy() {
		XCTAssertEqual(MessageMenuStrings.share, "Share…")
		XCTAssertEqual(MessageMenuStrings.reply, "Reply")
		XCTAssertEqual(MessageMenuStrings.react, "React")
		XCTAssertEqual(MessageMenuStrings.otherReaction, "Other…")
		XCTAssertEqual(MessageMenuStrings.sendReaction, "Send")
		XCTAssertEqual(MessageMenuStrings.emojiPlaceholder, "Emoji")
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
		XCTAssertEqual(ChannelSpotlightStrings.noResults, "No Results")
	}
}
