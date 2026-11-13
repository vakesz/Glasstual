// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Transcript day markers")
struct TranscriptDayMarkersTests {
	private func calendar(_ zone: String) throws -> Calendar {
		var calendar = Calendar(identifier: .gregorian)
		calendar.timeZone = try #require(TimeZone(identifier: zone))
		return calendar
	}

	private func utc(day: Int, hour: Int, minute: Int = 0) throws -> Date {
		try #require(calendar("UTC").date(from: DateComponents(
			year: 2026, month: 3, day: day, hour: hour, minute: minute
		)))
	}

	@Test("The first line drawn begins a day, and so does one on another day than the line above it")
	func neighboursDecide() throws {
		let markers = try TranscriptDayMarkers(calendar: calendar("UTC"))
		let evening = try utc(day: 10, hour: 23, minute: 59)
		let morning = try utc(day: 11, hour: 0)

		#expect(markers.beginsDay(evening, after: nil))
		#expect(markers.beginsDay(morning, after: evening))
		#expect(try markers.beginsDay(utc(day: 11, hour: 9), after: morning) == false)
		/* A line stamped by the local clock can sit above older server history. */
		#expect(markers.beginsDay(evening, after: morning))
	}

	@Test("Two moments either side of midnight in one zone are one day in another", arguments: [
		("Asia/Tokyo", true),
		("Europe/London", false),
		("America/Los_Angeles", false),
		("Pacific/Kiritimati", false),
	])
	func zoneDecidesTheBoundary(zone: String, crossesMidnight: Bool) throws {
		let markers = try TranscriptDayMarkers(calendar: calendar(zone))

		// 23:30 and 00:30 in Tokyo.
		#expect(try markers.beginsDay(utc(day: 10, hour: 15, minute: 30), after: utc(day: 10, hour: 14, minute: 30)) == crossesMidnight)
	}

	@Test("The marker names the day in the calendar's zone, not the machine's")
	func captionFollowsTheZone() throws {
		let moment = try utc(day: 10, hour: 15, minute: 30)
		let tokyo = try TranscriptDayMarkers(calendar: calendar("Asia/Tokyo"))
		let london = try TranscriptDayMarkers(calendar: calendar("Europe/London"))

		#expect(tokyo.caption(for: moment).contains("11"))
		#expect(london.caption(for: moment).contains("10"))
		#expect(tokyo.caption(for: moment) != london.caption(for: moment))
		#expect(try tokyo.caption(for: moment) == tokyo.caption(for: utc(day: 11, hour: 14)))
	}

	@Test("A day shortened by a clock change is still one day")
	func daylightChangeIsOneDay() throws {
		let markers = try TranscriptDayMarkers(calendar: calendar("Europe/London"))
		// The clocks go forward at 01:00 on 29 March 2026.
		let before = try utc(day: 29, hour: 0, minute: 30)
		let after = try utc(day: 29, hour: 22, minute: 30)

		#expect(markers.beginsDay(after, after: before) == false)
		#expect(try markers.beginsDay(utc(day: 29, hour: 23, minute: 30), after: after))
	}

	@Test("Rows are marked once per day, and a marker a row arrived with is not kept")
	func markingReplacesWhatRowsCarry() throws {
		let markers = try TranscriptDayMarkers(calendar: calendar("UTC"))
		var stale = try row("b", at: utc(day: 10, hour: 12))
		stale.markers = [.unread("Unread"), .date("printed with")]
		let rows = try [row("a", at: utc(day: 10, hour: 11)), stale, row("c", at: utc(day: 11, hour: 1))]

		let marked = TranscriptDayMarkers.marking(rows, after: nil, using: markers)
		let continued = try TranscriptDayMarkers.marking(rows, after: utc(day: 10, hour: 9), using: markers)
		let off = TranscriptDayMarkers.marking(rows, after: nil, using: nil)

		#expect(try marked.map(\.markers) == [
			[.date(markers.caption(for: utc(day: 10, hour: 0)))],
			[.unread("Unread")],
			[.date(markers.caption(for: utc(day: 11, hour: 0)))],
		])
		#expect(continued[0].markers.isEmpty)
		#expect(off.map(\.markers) == [[], [.unread("Unread")], []])
	}

	private func row(_ name: String, at date: Date) -> TranscriptRow {
		TranscriptRow(
			lineNumber: name, receivedAt: date, nickname: "alice", memberType: .normal,
			lineType: .privateMessage, command: "PRIVMSG", messageIdentifier: nil,
			replyToMessageIdentifier: nil, deliveryState: .none, deliveryFailureReason: nil,
			reactions: [:], markers: [], body: TranscriptBody(plainText: name)
		)
	}
}
