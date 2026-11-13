// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Which lines begin a day, and what the marker above them says.

 A line begins a day when the line drawn directly above it fell on another
 day, or when nothing is drawn above it. That is a fact about two neighbours,
 so it is worked out where lines become neighbours, in the transcript, and
 worked out again whenever a line gets a new one: appended, put in above, or
 recovered into a gap. The flag a line was printed with only says what came
 before it at the time.

 The day is the calendar's, and so the reader's time zone's. */
nonisolated struct TranscriptDayMarkers: Equatable, Sendable {
	var calendar = Calendar.autoupdatingCurrent

	/// Whether a line received at `date` begins a day below one received at
	/// `previous`. The first line drawn always does.
	func beginsDay(_ date: Date, after previous: Date?) -> Bool {
		guard let previous else { return true }
		return calendar.isDate(date, inSameDayAs: previous) == false
	}

	/// The marker's text for the day `date` falls on.
	func caption(for date: Date) -> String {
		DateFormatting.dayHeading(date, calendar: calendar)
	}

	/// The marker a line received at `date` carries below one received at
	/// `previous`, or `nil` where it continues that line's day.
	func caption(for date: Date, after previous: Date?) -> String? {
		beginsDay(date, after: previous) ? caption(for: date) : nil
	}

	/** `rows` as they are drawn below a line received at `previous`: each one
	 that begins a day carries that day's marker, and no other carries one.
	 Without a policy -- the reader turned date changes off -- none does. */
	static func marking(_ rows: [TranscriptRow], after previous: Date?, using policy: Self?) -> [TranscriptRow] {
		var previous = previous
		return rows.map { row in
			var row = row
			row.setDateMarker(policy?.caption(for: row.receivedAt, after: previous))
			previous = row.receivedAt
			return row
		}
	}
}
