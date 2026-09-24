// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Line presentation policy")
struct LinePresentationPolicyTests {
	@Test("A no-highlight type skips keyword matching and then normalizes to its plain type")
	func noHighlightTypesNormalizeAfterSkippingKeywordMatching() {
		#expect(LinePresentationPolicy.allowsHighlightMatching(
			conversationExists: true,
			ignoresHighlights: false,
			lineType: .actionNoHighlight,
			memberType: .normal
		) == false)
		#expect(LinePresentationPolicy.normalized(.actionNoHighlight) == .action)
		#expect(LinePresentationPolicy.normalized(.privateMessageNoHighlight) == .privateMessage)
	}

	@Test("Only a regular message from someone else is matched against the keywords")
	func highlightMatchingRequiresARegularRemoteMessage() {
		#expect(LinePresentationPolicy.allowsHighlightMatching(
			conversationExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .normal
		))
		#expect(LinePresentationPolicy.allowsHighlightMatching(
			conversationExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .localUser
		) == false)
	}

	@Test("The scrollback mark is placed only for an unread line outside the visible view")
	func unreadMarkerRequiresAnUnreadEligibleLineOutsideTheActiveView() {
		#expect(LinePresentationPolicy.needsUnreadMarker(
			autoMark: true,
			itemIsVisible: false,
			windowIsMain: true,
			conversationIsUnread: false,
			lineType: .notice
		))
		#expect(LinePresentationPolicy.needsUnreadMarker(
			autoMark: true,
			itemIsVisible: true,
			windowIsMain: true,
			conversationIsUnread: false,
			lineType: .notice
		) == false)
	}

	@Test("The first line of a day is decided by the calendar day, not by elapsed time")
	func firstLineForDayUsesCalendarBoundaries() throws {
		let calendar = Calendar(identifier: .gregorian)
		let first = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 26, hour: 23)))
		let second = try #require(calendar.date(from: DateComponents(year: 2026, month: 8, day: 27, hour: 1)))

		#expect(LinePresentationPolicy.isFirstForDay(receivedAt: second, previousDate: first))
		#expect(LinePresentationPolicy.isFirstForDay(receivedAt: first, previousDate: first) == false)
	}

	@Test(
		"Removing incoming formatting strips everyone's lines but the local user's",
		arguments: [
			(ChatLineMemberKind.normal, true, "bold"),
			(ChatLineMemberKind.localUser, true, "\u{2}bold\u{2}"),
			(ChatLineMemberKind.normal, false, "\u{2}bold\u{2}"),
		]
	)
	func incomingFormattingIsStrippedAtPrintTime(
		_ memberType: ChatLineMemberKind,
		_ removesFormatting: Bool,
		_ expected: String
	) {
		#expect(LinePresentationPolicy.messageBody(
			"\u{2}bold\u{2}",
			memberType: memberType,
			removesIncomingFormatting: removesFormatting
		) == expected)
	}

	/// The setting is about what the transcript shows. Applied to the raw
	/// line it took control codes out of channel names and CTCP arguments,
	/// which then named things the server never sent.
	@Test("Removing incoming formatting leaves the parsed line as it arrived")
	func removingFormattingDoesNotRewriteTheWireLine() throws {
		var settings = ChatSettings()
		settings.removeAllFormatting = true
		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.setConnectionTransportForTesting(.connected)
		session.socket = Connection(config: ConnectionConfig(), onSession: session)
		_ = try #require(session.socket)
		let channel = try #require(session.findConversationOrCreate("#\u{2}chan"))

		session.connectionDidReceive(":alice!a@host PRIVMSG #\u{2}chan :\u{3}4red")

		let printed = try #require(session.printedLines.lastObject as? [String: Any])
		#expect(printed["channel"] as? Conversation === channel)
		#expect(printed["messageBody"] as? String == "\u{3}4red")
	}
}
