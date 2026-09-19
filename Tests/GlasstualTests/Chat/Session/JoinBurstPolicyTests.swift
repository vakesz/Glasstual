// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Playback classification")
struct JoinBurstPolicyTests {
	@Test("Only explicit history is excluded on ordinary servers", arguments: [0.0, 1.0, 10.0, 60.0])
	func ordinaryServerPlayback(_ elapsed: TimeInterval) {
		let joined = Date(timeIntervalSince1970: 1_700_000_000)
		for hasTime in [false, true] {
			for replayed in [false, true] {
				#expect(JoinBurstPolicy.isJoinBurstLine(
					joinedAt: joined, now: joined.addingTimeInterval(elapsed), isReplayed: replayed,
					hasServerTime: hasTime, receivedAt: joined.addingTimeInterval(-300)
				) == replayed)
			}
		}
	}

	@Test("History does not need a JOIN timestamp")
	func historyWithoutJoin() {
		#expect(JoinBurstPolicy.isJoinBurstLine(joinedAt: nil, now: Date(), isReplayed: true,
		                                        hasServerTime: false, receivedAt: Date()))
	}

	@Test("Legacy ZNC replay requires a timestamp")
	func legacyBouncerRequiresTimestamp() {
		let joined = Date()
		for hasTime in [false, true] {
			#expect(JoinBurstPolicy.isJoinBurstLine(
				joinedAt: joined, now: joined.addingTimeInterval(1), isReplayed: false,
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
struct ConversationReadMarkerTests {
	private let marker = Date(timeIntervalSince1970: 1_700_000_000)

	/// Asks a session whether a line stamped `receivedAt` arrives already seen,
	/// with `marker` standing for what the server last reported as read.
	private func lineIsRead(receivedAt: Date, marker: Date?, hasServerTime: Bool = true) throws -> Bool {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		let channel = try #require(session.findConversationOrCreate("#channel"))

		if let marker {
			session.readMarkers.sentDates[channel.uniqueIdentifier] = marker
		}

		var message = try #require(Message(line: ":a!u@h PRIVMSG #channel :hello", on: session))

		message.receivedAt = receivedAt
		message.hasServerTime = hasServerTime

		return session.lineArrivedAlreadySeen(message, in: channel)
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

	/// A line without server time is stamped by the local clock, which cannot
	/// be compared with a server timestamp: a clock running behind read every
	/// live line as older than the marker.
	@Test("A line without server time is never read by the marker")
	func linesWithoutServerTimeAreUnread() throws {
		try #expect(lineIsRead(receivedAt: marker.addingTimeInterval(-60), marker: marker, hasServerTime: false) == false)
	}

	/// The marker is sent at a line's time, so only a line the server stamped
	/// may place it.
	@Test("Only a conversation line the server delivered places the read marker", arguments: [
		(lineType: ChatLineKind.privateMessage, messageIdentifier: "abc" as String?, marks: true),
		(lineType: ChatLineKind.privateMessage, messageIdentifier: nil as String?, marks: false),
		(lineType: ChatLineKind.join, messageIdentifier: "abc" as String?, marks: false),
	])
	func onlyServerStampedConversationLinesPlaceTheMarker(
		lineType: ChatLineKind,
		messageIdentifier: String?,
		marks: Bool
	) {
		#expect(ChatHistoryPolicy.marksReadPosition(lineType: lineType, messageIdentifier: messageIdentifier) == marks)
	}
}
