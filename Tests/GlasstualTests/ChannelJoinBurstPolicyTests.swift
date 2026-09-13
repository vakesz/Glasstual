/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("Playback classification")
struct ChannelJoinBurstPolicyTests {
	@Test("Only explicit history is excluded on ordinary servers", arguments: [0.0, 1.0, 10.0, 60.0])
	func ordinaryServerPlayback(_ elapsed: TimeInterval) {
		let joined = Date(timeIntervalSince1970: 1_700_000_000)
		for hasTime in [false, true] {
			for historic in [false, true] {
				#expect(ChannelJoinBurstPolicy.isJoinBurstLine(
					joinedAt: joined, now: joined.addingTimeInterval(elapsed), isHistoric: historic,
					hasServerTime: hasTime, receivedAt: joined.addingTimeInterval(-300)
				) == historic)
			}
		}
	}

	@Test("History does not need a JOIN timestamp")
	func historyWithoutJoin() {
		#expect(ChannelJoinBurstPolicy.isJoinBurstLine(joinedAt: nil, now: Date(), isHistoric: true,
		                                               hasServerTime: false, receivedAt: Date()))
	}

	@Test("Legacy ZNC replay requires a timestamp")
	func legacyBouncerRequiresTimestamp() {
		let joined = Date()
		for hasTime in [false, true] {
			#expect(ChannelJoinBurstPolicy.isJoinBurstLine(
				joinedAt: joined, now: joined.addingTimeInterval(1), isHistoric: false,
				hasServerTime: hasTime, receivedAt: joined.addingTimeInterval(-5), isKnownBouncer: true
			) == hasTime)
		}
	}
}

/** What the server says has been read is the only thing that survives the
 suppressed burst, so the comparison against the marker has to include the
 marker itself: a line at the marker is the last line the user read. */
@MainActor
@Suite("Read marker line policy")
struct ChannelReadMarkerTests {
	private let marker = Date(timeIntervalSince1970: 1_700_000_000)

	/// Asks a client whether a line stamped `receivedAt` arrives already seen,
	/// with `marker` standing for what the server last reported as read.
	private func lineIsRead(receivedAt: Date, marker: Date?) throws -> Bool {
		let client = TestClient(configDictionary: ["nickname": "me"])
		let channel = try #require(client.findChannelOrCreate("#channel"))

		if let marker {
			client.readMarkerSentDates[channel.uniqueIdentifier] = marker
		}

		let message = try #require(Message(line: ":a!u@h PRIVMSG #channel :hello", on: client))

		message.receivedAt = receivedAt

		return client.lineArrivedAlreadySeen(message, in: channel)
	}

	@Test("With no marker nothing is known to have been read")
	func nothingIsReadWithoutAMarker() throws {
		try #expect(lineIsRead(receivedAt: marker, marker: nil) == false)
	}

	@Test("A line before the marker is read")
	func linesBeforeTheMarkerAreRead() throws {
		try #expect(lineIsRead(receivedAt: marker.addingTimeInterval(-1), marker: marker))
	}

	@Test("A line at the marker is read")
	func linesAtTheMarkerAreRead() throws {
		try #expect(lineIsRead(receivedAt: marker, marker: marker))
	}

	@Test("A line after the marker is unread")
	func linesAfterTheMarkerAreUnread() throws {
		try #expect(lineIsRead(receivedAt: marker.addingTimeInterval(0.001), marker: marker) == false)
	}
}
