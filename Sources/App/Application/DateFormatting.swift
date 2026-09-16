/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import Foundation

/** Every date the application formats or parses, in one place.

 These were `@_cdecl` C entry points for the Objective-C half of the
 application, which no longer exists, so they took `NSDate` and `NSString` and
 came in `Any` and `AnyObject` pairs. Every caller is Swift now. */
nonisolated enum DateFormatting { // nonisolated: value
	// MARK: - ISO 8601

	/** The one ISO 8601 representation the protocol layer reads and writes.

	 It used to be a process-global `DateFormatter` handed to every caller, so any
	 one of them could set `dateFormat` on it and silently change how every other
	 timestamp in the application parsed. A format style is a value: there is
	 nothing shared left to reconfigure. */
	private static let iso8601 = Date.ISO8601FormatStyle(
		includingFractionalSeconds: true,
		timeZone: TimeZone(identifier: "UTC") ?? .gmt
	)

	/** Half a millisecond, added before formatting so that the fraction rounds.

	 `Date.ISO8601FormatStyle` truncates the fractional seconds where the
	 `DateFormatter` this replaced rounded them, and a millisecond figure is
	 rarely exact in binary: the nearest `Double` to `…20.123` sits just below
	 it, so the stamp came out `…20.122`. A millisecond is a difference a server
	 acts on -- MARKREAD and CHATHISTORY both compare these stamps, and a CTCP
	 TIME reply is read by whoever asked -- so the truncation is turned back into
	 a round by nudging the moment first. */
	private static let millisecondRoundingBias: TimeInterval = 0.000_5

	static func iso8601String(from date: Date) -> String {
		iso8601.format(date.addingTimeInterval(millisecondRoundingBias))
	}

	static func date(fromISO8601 string: String) -> Date? {
		try? iso8601.parse(string)
	}

	// MARK: - The transcript's timestamp pattern

	/// `date` written with the user's `strftime` pattern, or nil when either the
	/// moment or the pattern cannot produce one.
	static func timestamp(_ date: Date, format: String) -> String? {
		/* The date can come off disk: a scrollback row carries an archived date,
		 and one that is not a moment `localtime_r` can name traps on the
		 narrowing rather than reporting it. Every caller already falls back to
		 the empty string, which is what an unformattable stamp means. */
		guard let epoch = Int64(exactly: date.timeIntervalSince1970.rounded()) else {
			return nil
		}

		var global = time_t(epoch)
		var localTime = tm()

		guard localtime_r(&global, &localTime) != nil else {
			return nil
		}

		var outputBuffer = [CChar](repeating: 0, count: 257)

		guard strftime(&outputBuffer, outputBuffer.count, format, &localTime) > 0 else {
			return nil
		}

		let bytes = outputBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

		return String(bytes: bytes, encoding: .utf8)
	}

	// MARK: - Spans

	/** One unit a span can be reported in, largest first.

	 Two spellings of the same unit meet here: `Calendar.Component` measures the
	 span and `Date.ComponentsFormatStyle.Field` prints it. One row per unit keeps
	 them together instead of in two switches that have to agree. */
	private static let measurableUnits: [(
		component: Calendar.Component,
		field: Date.ComponentsFormatStyle.Field
	)] = [
		(.year, .year),
		(.month, .month),
		(.day, .day),
		(.hour, .hour),
		(.minute, .minute),
		(.second, .second),
	]

	/** `interval` written out in words, in the reader's locale.

	 `shortValue` reports only the largest unit the span actually fills; `fields`
	 narrows which units may be used at all, and an empty set means every one. */
	static func humanReadable(
		_ interval: TimeInterval,
		shortValue: Bool,
		fields requestedFields: Set<Date.ComponentsFormatStyle.Field> = []
	) -> String {
		let requested = requestedFields.isEmpty
			? measurableUnits
			: measurableUnits.filter { requestedFields.contains($0.field) }
		let calendar = Calendar.autoupdatingCurrent
		let startDate = Date()
		/* The interval can be server text a caller read as a `Double`, and
		 `Double("nan")` parses. Foundation clamps the resulting date rather than
		 trapping, which turns a NaN into a plausible-looking span in the wrong
		 direction; nothing to measure reads as nothing. */
		let endDate = startDate.addingTimeInterval(interval.isFinite ? interval : 0)
		let dateRange = min(startDate, endDate) ..< max(startDate, endDate)
		let fields: Set<Date.ComponentsFormatStyle.Field>

		if shortValue {
			let values = calendar.dateComponents(
				Set(requested.map(\.component)),
				from: dateRange.lowerBound,
				to: dateRange.upperBound
			)
			let largest = requested.first { values.value(for: $0.component) != 0 }
			fields = [largest?.field ?? .second]
		} else {
			fields = Set(requested.map(\.field))
		}

		return Date.ComponentsFormatStyle(
			style: .wide,
			calendar: calendar,
			fields: fields.isEmpty ? [.second] : fields
		).format(dateRange)
	}

	// MARK: - Display

	/// `date` in the reader's locale. `relative` names today and yesterday by
	/// name rather than by their date.
	static func formatted(
		_ date: Date,
		dateStyle: DateFormatter.Style,
		timeStyle: DateFormatter.Style,
		relative: Bool
	) -> String {
		guard relative else {
			/* A format style is a value Foundation resolves once per locale, where
			 the `DateFormatter` this replaced was built again on every line the
			 transcript drew a date separator for. */
			return date.formatted(Date.FormatStyle(
				date: formatStyleDate(for: dateStyle),
				time: formatStyleTime(for: timeStyle)
			))
		}

		/* "Today" and "Yesterday" are `DateFormatter.doesRelativeDateFormatting`
		 and nothing else: `Date.FormatStyle` has no equivalent, and
		 `Date.RelativeFormatStyle` says "3 days ago" instead of naming the day.
		 A `DateFormatter` is not `Sendable`, so this path builds one per call
		 rather than sharing one; nothing on the transcript's drawing path asks
		 for a relative date. */
		let dateFormatter = DateFormatter()
		dateFormatter.doesRelativeDateFormatting = true
		dateFormatter.dateStyle = dateStyle
		dateFormatter.timeStyle = timeStyle

		return dateFormatter.string(from: date)
	}

	/** The same, for the date representations servers actually send: an ISO 8601
	 timestamp, or a Unix epoch in seconds.

	 Anything else answers nil, and the caller normally falls back to showing the
	 server's text verbatim. */
	static func formatted(
		serverText: String,
		dateStyle: DateFormatter.Style,
		timeStyle: DateFormatter.Style,
		relative: Bool
	) -> String? {
		let trimmed = serverText.trimmingCharacters(in: .whitespacesAndNewlines)
		let date: Date

		if let parsed = self.date(fromISO8601: trimmed) {
			date = parsed
		} else if let seconds = TimeInterval(trimmed), seconds.isFinite {
			/* `TimeInterval("inf")` and `TimeInterval("nan")` both parse, and
			 neither is a moment. */
			date = Date(timeIntervalSince1970: seconds)
		} else {
			return nil
		}

		return formatted(date, dateStyle: dateStyle, timeStyle: timeStyle, relative: relative)
	}

	private static func formatStyleDate(for style: DateFormatter.Style) -> Date.FormatStyle.DateStyle {
		switch style {
		case .none: .omitted
		case .short: .numeric
		case .medium: .abbreviated
		case .long: .long
		case .full: .complete
		@unknown default: .abbreviated
		}
	}

	private static func formatStyleTime(for style: DateFormatter.Style) -> Date.FormatStyle.TimeStyle {
		switch style {
		case .none: .omitted
		case .short: .shortened
		case .medium: .standard
		case .long, .full: .complete
		@unknown default: .shortened
		}
	}
}
