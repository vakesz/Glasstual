/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** The burst a bouncer replays right after a JOIN is the one thing that must
 not raise a badge or a notification: it is the conversation the user is about
 to read, not something addressed to them now. The three clauses stand for the
 three ways a replay reaches this client, and each is tested on its own because
 dropping any one of them silently re-admits that replay. */
@Suite("Post-join burst policy")
struct ChannelJoinBurstPolicyTests {
	private let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)

	private func isBurst(
		joinedAt: Date?,
		secondsSinceJoin: TimeInterval,
		isHistoric: Bool = false,
		hasServerTime: Bool = true,
		stampedSecondsFromJoin: TimeInterval = 1
	) -> Bool {
		ChannelJoinBurstPolicy.isJoinBurstLine(
			joinedAt: joinedAt,
			now: self.joinedAt.addingTimeInterval(secondsSinceJoin),
			isHistoric: isHistoric,
			hasServerTime: hasServerTime,
			receivedAt: self.joinedAt.addingTimeInterval(stampedSecondsFromJoin)
		)
	}

	@Test("The grace period is the ten seconds after the join")
	func gracePeriodIsTenSeconds() {
		#expect(ChannelJoinBurstPolicy.gracePeriod == 10)
	}

	@Test("A channel that was never joined has no burst to suppress")
	func aChannelWithNoJoinHasNoBurst() {
		#expect(isBurst(joinedAt: nil, secondsSinceJoin: 0, isHistoric: true) == false)
	}

	@Test("A batch or a far-behind stamp marks the line historic, and historic is a burst line")
	func historicLinesAreBurstLines() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 1, isHistoric: true))
	}

	@Test("A server with no server-time replays with no stamp, so every line in the window counts")
	func linesWithoutServerTimeAreBurstLines() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 1, hasServerTime: false))
	}

	@Test("A stamp from before the join is scrollback however it was delivered")
	func linesStampedBeforeTheJoinAreBurstLines() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 1, stampedSecondsFromJoin: -1))
	}

	@Test("A line stamped at the exact moment of the join is a burst line")
	func aLineStampedAtTheJoinIsABurstLine() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 1, stampedSecondsFromJoin: 0))
	}

	@Test("A live, stamped line said after the join is not a burst line")
	func liveLinesInsideTheWindowAreNotBurstLines() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 1, stampedSecondsFromJoin: 0.5) == false)
	}

	@Test("The window is closed at the ten-second boundary, not before it")
	func theWindowClosesAfterExactlyTenSeconds() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 10, hasServerTime: false))
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 10.001, hasServerTime: false) == false)
	}

	@Test("Outside the window not even a replayed line is suppressed")
	func nothingIsABurstLineOutsideTheWindow() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 30, isHistoric: true) == false)
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 30, hasServerTime: false) == false)
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: 30, stampedSecondsFromJoin: -300) == false)
	}

	@Test("A join stamped in the future keeps the window open")
	func aJoinStampedAheadOfTheClockKeepsTheWindowOpen() {
		#expect(isBurst(joinedAt: joinedAt, secondsSinceJoin: -5, hasServerTime: false))
	}
}

/** What the server says has been read is the only thing that survives the
 suppressed burst, so the comparison against the marker has to include the
 marker itself: a line at the marker is the last line the user read. */
@Suite("Read marker line policy")
struct ChannelReadMarkerPolicyTests {
	private let marker = Date(timeIntervalSince1970: 1_700_000_000)

	@Test("With no marker nothing is known to have been read")
	func nothingIsReadWithoutAMarker() {
		#expect(ChannelReadMarkerPolicy.lineIsRead(receivedAt: marker, marker: nil) == false)
	}

	@Test("A line before the marker is read")
	func linesBeforeTheMarkerAreRead() {
		#expect(ChannelReadMarkerPolicy.lineIsRead(
			receivedAt: marker.addingTimeInterval(-1),
			marker: marker
		))
	}

	@Test("A line at the marker is read")
	func linesAtTheMarkerAreRead() {
		#expect(ChannelReadMarkerPolicy.lineIsRead(receivedAt: marker, marker: marker))
	}

	@Test("A line after the marker is unread")
	func linesAfterTheMarkerAreUnread() {
		#expect(ChannelReadMarkerPolicy.lineIsRead(
			receivedAt: marker.addingTimeInterval(0.001),
			marker: marker
		) == false)
	}
}
