/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Line presentation policy")
struct IRCLinePresentationPolicyTests {
	@Test("A no-highlight type skips keyword matching and then normalizes to its plain type")
	func noHighlightTypesNormalizeAfterSkippingKeywordMatching() {
		#expect(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .actionNoHighlight,
			memberType: .normal
		) == false)
		#expect(IRCLinePresentationPolicy.normalized(.actionNoHighlight) == .action)
		#expect(IRCLinePresentationPolicy.normalized(.privateMessageNoHighlight) == .privateMessage)
	}

	@Test("Only a regular message from someone else is matched against the keywords")
	func highlightMatchingRequiresARegularRemoteMessage() {
		#expect(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .normal
		))
		#expect(IRCLinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .localUser
		) == false)
	}

	@Test("The scrollback mark is placed only for an unread line outside the visible view")
	func scrollbackMarkRequiresAnUnreadEligibleLineOutsideTheActiveView() {
		#expect(IRCLinePresentationPolicy.needsScrollbackMark(
			autoMark: true,
			itemIsVisible: false,
			windowIsMain: true,
			channelIsUnread: false,
			lineType: .notice
		))
		#expect(IRCLinePresentationPolicy.needsScrollbackMark(
			autoMark: true,
			itemIsVisible: true,
			windowIsMain: true,
			channelIsUnread: false,
			lineType: .notice
		) == false)
	}

	@Test("The first line of a day is decided by the calendar day, not by elapsed time")
	func firstLineForDayUsesCalendarBoundaries() throws {
		let calendar = Calendar(identifier: .gregorian)
		let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 23)))
		let second = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 1)))

		#expect(IRCLinePresentationPolicy.isFirstForDay(receivedAt: second, previousDate: first))
		#expect(IRCLinePresentationPolicy.isFirstForDay(receivedAt: first, previousDate: first) == false)
	}
}
