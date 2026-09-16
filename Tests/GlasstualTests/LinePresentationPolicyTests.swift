/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Line presentation policy")
struct LinePresentationPolicyTests {
	@Test("A no-highlight type skips keyword matching and then normalizes to its plain type")
	func noHighlightTypesNormalizeAfterSkippingKeywordMatching() {
		#expect(LinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
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
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .normal
		))
		#expect(LinePresentationPolicy.allowsHighlightMatching(
			channelExists: true,
			ignoresHighlights: false,
			lineType: .privateMessage,
			memberType: .localUser
		) == false)
	}

	@Test("The scrollback mark is placed only for an unread line outside the visible view")
	func scrollbackMarkRequiresAnUnreadEligibleLineOutsideTheActiveView() {
		#expect(LinePresentationPolicy.needsScrollbackMark(
			autoMark: true,
			itemIsVisible: false,
			windowIsMain: true,
			channelIsUnread: false,
			lineType: .notice
		))
		#expect(LinePresentationPolicy.needsScrollbackMark(
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

		#expect(LinePresentationPolicy.isFirstForDay(receivedAt: second, previousDate: first))
		#expect(LinePresentationPolicy.isFirstForDay(receivedAt: first, previousDate: first) == false)
	}

	@Test(
		"Removing incoming formatting strips everyone's lines but the local user's",
		arguments: [
			(LogLineMemberType.normal, true, "bold"),
			(LogLineMemberType.localUser, true, "\u{2}bold\u{2}"),
			(LogLineMemberType.normal, false, "\u{2}bold\u{2}"),
		]
	)
	func incomingFormattingIsStrippedAtPrintTime(
		_ memberType: LogLineMemberType,
		_ removesFormatting: Bool,
		_ expected: String
	) {
		#expect(LinePresentationPolicy.messageBody(
			"\u{2}bold\u{2}",
			memberType: memberType,
			removesIncomingFormatting: removesFormatting
		) == expected)
	}

	/// The preference is about what the transcript shows. Applied to the raw
	/// line it took control codes out of channel names and CTCP arguments,
	/// which then named things the server never sent.
	@Test("Removing incoming formatting leaves the parsed line as it arrived")
	func removingFormattingDoesNotRewriteTheWireLine() throws {
		var preferences = ClientPreferences()
		preferences.removeAllFormatting = true
		let client = TestClient(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ClientEnvironmentFixture(preferences: preferences)
		)
		client.isConnected = true
		client.socket = Connection(config: ConnectionConfig(), onClient: client)
		let socket = try #require(client.socket)
		let channel = try #require(client.findChannelOrCreate("#\u{2}chan"))

		client.ircConnection(socket, didReceiveData: ":alice!a@host PRIVMSG #\u{2}chan :\u{3}4red")

		let printed = try #require(client.printedLines.lastObject as? [String: Any])
		#expect(printed["channel"] as? Channel === channel)
		#expect(printed["messageBody"] as? String == "\u{3}4red")
	}
}
