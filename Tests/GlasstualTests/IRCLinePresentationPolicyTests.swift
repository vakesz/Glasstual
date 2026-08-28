/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

@testable import Glasstual
import XCTest

@MainActor
final class IRCLinePresentationPolicyTests: XCTestCase {
	func testNoHighlightTypesNormalizeAfterSkippingKeywordMatching() {
		XCTAssertFalse(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .actionNoHighlight,
			memberType: .normal
		))
		XCTAssertEqual(IRCLinePresentationPolicy.normalized(.actionNoHighlight), .action)
		XCTAssertEqual(IRCLinePresentationPolicy.normalized(.privateMessageNoHighlight), .privateMessage)
	}

	func testHighlightMatchingRequiresARegularRemoteMessage() {
		XCTAssertTrue(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .normal
		))
		XCTAssertFalse(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .localUser
		))
	}

	func testScrollbackMarkRequiresAnUnreadEligibleLineOutsideTheActiveView() {
		XCTAssertTrue(IRCLinePresentationPolicy.needsScrollbackMark(
			autoMark: true,
			itemIsVisible: false,
			windowIsMain: true,
			channelIsUnread: false,
			lineType: .notice
		))
		XCTAssertFalse(IRCLinePresentationPolicy.needsScrollbackMark(
			autoMark: true,
			itemIsVisible: true,
			windowIsMain: true,
			channelIsUnread: false,
			lineType: .notice
		))
	}

	func testFirstLineForDayUsesCalendarBoundaries() {
		let calendar = Calendar(identifier: .gregorian)
		let first = calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 23))
		let second = calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 1))
		XCTAssertNotNil(first)
		XCTAssertNotNil(second)
		if let first, let second {
			XCTAssertTrue(IRCLinePresentationPolicy.isFirstForDay(receivedAt: second, previousDate: first))
			XCTAssertFalse(IRCLinePresentationPolicy.isFirstForDay(receivedAt: first, previousDate: first))
		}
	}
}
