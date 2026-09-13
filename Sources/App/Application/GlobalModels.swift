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
import GlasstualPluginKit

/* The helpers below were `@_cdecl` C entry points for the Objective-C half of
 the application, which no longer exists. Every caller is Swift, so they are
 ordinary Swift functions, and no `@_cdecl` is left anywhere in the tree:
 `PluginManager` admits a bundle only when it ships inside the application or
 carries the application's own Team ID, so there is no foreign binary left to
 reach one by its C name. The date formatters also existed twice, once taking
 `AnyObject` and once `Any`; only the `Any` form is kept. */

/** The one ISO 8601 representation the protocol layer reads and writes.

 It used to be a process-global `DateFormatter` handed to every caller, so any
 one of them could set `dateFormat` on it and silently change how every other
 timestamp in the application parsed. A format style is a value: there is
 nothing shared left to reconfigure. */
public nonisolated struct ISOStandardDateFormatter: Sendable { // nonisolated: value
	private static let style = Date.ISO8601FormatStyle(
		includingFractionalSeconds: true,
		timeZone: TimeZone(identifier: "UTC") ?? .gmt
	)

	/** Half a millisecond, added before formatting so that the fraction rounds.

	 `Date.ISO8601FormatStyle` truncates the fractional seconds where the
	 `DateFormatter` this replaced rounded them, and a millisecond figure is
	 rarely exact in binary: the nearest `Double` to `…20.123` sits just below
	 it, so the stamp came out `…20.122`. A millisecond is a difference a server
	 acts on — MARKREAD and CHATHISTORY both compare these stamps, and a CTCP
	 TIME reply is read by whoever asked — so the truncation is turned back into
	 a round by nudging the moment first. */
	private static let millisecondRoundingBias: TimeInterval = 0.000_5

	public init() {}

	public func string(from date: Date) -> String {
		Self.style.format(date.addingTimeInterval(Self.millisecondRoundingBias))
	}

	public func date(from string: String) -> Date? {
		try? Self.style.parse(string)
	}
}

public nonisolated func formattedTimestamp(_ date: NSDate, _ format: NSString) -> String? { // nonisolated: pure
	/* The date can come off disk: a historic log row carries an archived
	 `NSDate`, and one that is not a moment `localtime_r` can name traps on the
	 narrowing rather than reporting it. Every caller already falls back to the
	 empty string, which is what an unformattable stamp means. */
	guard let epoch = Int64(exactly: date.timeIntervalSince1970.rounded()) else {
		return nil
	}

	var global = time_t(epoch)
	var localTime = tm()

	guard localtime_r(&global, &localTime) != nil else {
		return nil
	}

	var outputBuffer = [CChar](repeating: 0, count: 257)

	guard strftime(&outputBuffer, outputBuffer.count, format.utf8String, &localTime) > 0 else {
		return nil
	}

	let bytes = outputBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

	return String(bytes: bytes, encoding: .utf8)
}

public nonisolated func humanReadableTimeInterval( // nonisolated: pure
	_ dateInterval: TimeInterval,
	_ shortValue: Bool,
	_ orderMatrix: UInt
) -> String {
	PluginHost.humanReadableTimeInterval(
		dateInterval,
		shortValue: shortValue,
		units: NSCalendar.Unit(rawValue: orderMatrix)
	)
}

public nonisolated func formatDate( // nonisolated: pure
	_ dateObject: Any,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> String? {
	formatDateValue(dateObject, dateStyle, timeStyle, relativeOutput)
}

private nonisolated func formatDateValue( // nonisolated: pure
	_ dateObject: Any,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> String? {
	guard let date = dateValue(dateObject) else {
		return nil
	}

	guard relativeOutput else {
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
	 `Date.RelativeFormatStyle` says "3 days ago" instead of naming the day. */
	let dateFormatter = DateFormatter()
	dateFormatter.doesRelativeDateFormatting = true
	dateFormatter.dateStyle = dateStyle
	dateFormatter.timeStyle = timeStyle

	return dateFormatter.string(from: date)
}

/// The moment a caller handed over, as a `Date`. Strings arrive from servers
/// and have to be parsed before anything can format them.
private nonisolated func dateValue(_ dateObject: Any) -> Date? { // nonisolated: pure
	switch dateObject {
	case let string as String: parseDateValue(string)
	case let date as Date: date
	case let date as NSDate: date as Date
	default: nil
	}
}

private nonisolated func formatStyleDate( // nonisolated: pure
	for style: DateFormatter.Style
) -> Date.FormatStyle.DateStyle {
	switch style {
	case .none: .omitted
	case .short: .numeric
	case .medium: .abbreviated
	case .long: .long
	case .full: .complete
	@unknown default: .abbreviated
	}
}

private nonisolated func formatStyleTime( // nonisolated: pure
	for style: DateFormatter.Style
) -> Date.FormatStyle.TimeStyle {
	switch style {
	case .none: .omitted
	case .short: .shortened
	case .medium: .standard
	case .long, .full: .complete
	@unknown default: .shortened
	}
}

/// Parses the date representations servers actually send: an ISO 8601
/// timestamp, or a Unix epoch in seconds. Anything else is left to the caller,
/// which normally falls back to showing the server's text verbatim.
private nonisolated func parseDateValue(_ string: String) -> Date? { // nonisolated: pure
	let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

	if let date = ISOStandardDateFormatter().date(from: trimmed) {
		return date
	}

	/* `TimeInterval("inf")` and `TimeInterval("nan")` both parse, and neither
	 is a moment: the caller shows the server's own text instead. */
	if let seconds = TimeInterval(trimmed), seconds.isFinite {
		return Date(timeIntervalSince1970: seconds)
	}

	return nil
}

/** A number below `maximum`, drawn from `generator`, or zero when there is no
 such number.

 `inout`, the way the standard library takes a generator: a generator is state
 that advances, and taking it by value drew from a copy and left the caller's
 own generator where it was — so two draws in a row from the same generator
 answered the same number. */
public nonisolated func randomNumber( // nonisolated: pure
	_ maximum: UInt32,
	using generator: inout some RandomNumberGenerator
) -> UInt {
	guard maximum > 0 else { return 0 }

	return UInt(UInt32.random(in: 0 ..< maximum, using: &generator))
}

/// The same number from the system generator, for the callers that want one and
/// have no generator of their own. It holds no state of ours: every draw goes to
/// the operating system.
public nonisolated func randomNumber(_ maximum: UInt32) -> UInt { // nonisolated: pure
	var generator = SystemRandomNumberGenerator()

	return randomNumber(maximum, using: &generator)
}

public nonisolated func formattedNumber(_ number: Int) -> String { // nonisolated: pure
	PluginHost.formattedNumber(number)
}
