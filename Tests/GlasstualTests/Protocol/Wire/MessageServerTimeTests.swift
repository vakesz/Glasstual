// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// How a bouncer's or server's timestamp becomes a date, and when that date
/// makes a line replay.
struct MessageServerTimeTests {
	nonisolated static let rejectedStamps = ["", "abc", "nan", "inf", "-inf", "1e400", String(repeating: "9", count: 40)]

	@Test("A stamp that is not a usable time reads as no time", arguments: Self.rejectedStamps)
	func unusableStampIsNil(_ value: String) {
		#expect(ircWireTimestampDate(from: value) == nil)
	}

	@Test(
		"Whole and fractional Unix seconds are read",
		arguments: [("1700000000", 1_700_000_000.0), ("1700000000.5", 1_700_000_000.5), ("0", 0.0)]
	)
	func plausibleStampIsRead(_ value: String, _ seconds: TimeInterval) {
		#expect(ircWireTimestampDate(from: value)?.timeIntervalSince1970 == seconds)
	}

	@Test("The bound is inclusive at 1e11 and exclusive past it")
	func boundIsInclusive() {
		#expect(ircWireTimestampDate(from: "100000000000") != nil)
		#expect(ircWireTimestampDate(from: "100000000001") == nil)
		#expect(ircWireTimestampDate(from: "-100000000000") != nil)
		#expect(ircWireTimestampDate(from: "-100000000001") == nil)
	}

	@Test("The live tolerance is thirty seconds")
	func toleranceValue() {
		#expect(liveServerTimeTolerance == 30)
	}

	struct ReplayCase: Sendable {
		let age: TimeInterval
		let batch: Bool
		let bouncer: Bool
		let replayed: Bool
	}

	nonisolated static let replayCases: [ReplayCase] = [
		ReplayCase(age: 0, batch: true, bouncer: false, replayed: true),
		ReplayCase(age: 0, batch: true, bouncer: true, replayed: true),
		ReplayCase(age: 500, batch: false, bouncer: false, replayed: false),
		ReplayCase(age: 31, batch: false, bouncer: true, replayed: true),
		ReplayCase(age: 30, batch: false, bouncer: true, replayed: false),
		ReplayCase(age: 5, batch: false, bouncer: true, replayed: false),
		ReplayCase(age: -500, batch: false, bouncer: true, replayed: false),
	]

	@Test("Replay is a batch, or a stale stamp from a known bouncer", arguments: Self.replayCases)
	func replayDecision(_ testCase: ReplayCase) {
		let arrived = Date(timeIntervalSince1970: 1_700_000_000)

		#expect(
			messageIsReplayed(
				serverTime: arrived.addingTimeInterval(-testCase.age),
				arrivedAt: arrived,
				inReplayBatch: testCase.batch,
				isKnownBouncer: testCase.bouncer
			) == testCase.replayed
		)
	}

	private static let context = MessageParsingContext(serverTimeEnabled: true)

	@Test("An ISO stamp, with or without fractional seconds, dates the line")
	func isoStampDatesTheLine() throws {
		for stamp in ["2024-01-02T03:04:05Z", "2024-01-02T03:04:05.000Z"] {
			let message = try #require(Message(line: "@time=\(stamp) :n!u@h PRIVMSG #c :hi", context: Self.context))

			#expect(message.hasServerTime)
			#expect(message.receivedAt == Date(timeIntervalSince1970: 1_704_164_645))
		}
	}

	@Test("The bouncer t tag carries Unix seconds")
	func bouncerTagIsRead() throws {
		let message = try #require(Message(line: "@t=1700000000 :n!u@h PRIVMSG #c :hi", context: Self.context))

		#expect(message.hasServerTime)
		#expect(message.receivedAt == Date(timeIntervalSince1970: 1_700_000_000))
	}

	@Test("Without the capability the tag does not date the line")
	func tagIgnoredWithoutCapability() throws {
		let message = try #require(Message(line: "@time=2024-01-02T03:04:05Z :n!u@h PRIVMSG #c :hi"))

		#expect(message.hasServerTime == false)
		#expect(message.receivedAt != Date(timeIntervalSince1970: 1_704_164_645))
	}

	@Test("A garbage stamp leaves the arrival time alone", arguments: ["@time=yesterday", "@time=", "@t=1e400"])
	func garbageStampIsIgnored(_ tag: String) throws {
		let message = try #require(Message(line: "\(tag) :n!u@h PRIVMSG #c :hi", context: Self.context))

		#expect(message.hasServerTime == false)
		#expect(message.isReplayed == false)
	}

	@Test("An old stamp is replay only from a known bouncer")
	func staleStampNeedsABouncer() throws {
		let line = "@time=2001-01-01T00:00:00Z :n!u@h PRIVMSG #c :hi"
		let ordinary = try #require(Message(line: line, context: Self.context))
		var bouncerContext = Self.context
		bouncerContext.isKnownBouncer = true
		let bounced = try #require(Message(line: line, context: bouncerContext))

		#expect(ordinary.isReplayed == false)
		#expect(bounced.isReplayed)
	}
}
