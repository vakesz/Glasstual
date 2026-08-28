/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
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

/* These were `@_cdecl` C entry points for the Objective-C half of the
 application, which no longer exists; `@_cdecl` is an unsupported underscored
 attribute and every caller is Swift. The date formatters also existed twice,
 once taking `AnyObject` and once `Any`; only the `Any` form is kept. */

private nonisolated let isoStandardDateFormatter: DateFormatter = {
	let dateFormatter = DateFormatter()
	dateFormatter.locale = Locale(identifier: "en_US_POSIX")
	dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
	dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
	return dateFormatter
}()

public nonisolated func formattedTimestamp(_ date: NSDate, _ format: NSString) -> NSString? {
	var global = time_t(date.timeIntervalSince1970)
	var localTime = tm()

	guard localtime_r(&global, &localTime) != nil else {
		return nil
	}

	var outputBuffer = [CChar](repeating: 0, count: 257)

	guard strftime(&outputBuffer, outputBuffer.count, format.utf8String, &localTime) > 0 else {
		return nil
	}

	let bytes = outputBuffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }

	guard let timestamp = String(bytes: bytes, encoding: .utf8) else {
		return nil
	}

	return NSString(string: timestamp)
}

public nonisolated func humanReadableTimeInterval(
	_ dateInterval: TimeInterval,
	_ shortValue: Bool,
	_ orderMatrix: UInt
) -> NSString? {
	PluginHost.humanReadableTimeInterval(
		dateInterval,
		shortValue: shortValue,
		units: NSCalendar.Unit(rawValue: orderMatrix)
	) as NSString
}

public nonisolated func formatDateLongStyle(_ dateObject: Any, _ relativeOutput: Bool) -> String? {
	formatDateValue(dateObject, .long, .long, relativeOutput)
}

public nonisolated func formatDate(
	_ dateObject: Any,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> String? {
	formatDateValue(dateObject, dateStyle, timeStyle, relativeOutput)
}

private nonisolated func formatDateValue(
	_ dateObject: Any,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> String? {
	let dateFormatter = DateFormatter()
	dateFormatter.doesRelativeDateFormatting = relativeOutput
	dateFormatter.isLenient = true
	dateFormatter.dateStyle = dateStyle
	dateFormatter.timeStyle = timeStyle

	if let string = dateObject as? String {
		/* DateFormatter.string(for:) returns nil for anything that is not an
		 NSDate, so a string has to be parsed before it can be formatted. */
		guard let date = parseDateValue(string) else {
			return nil
		}

		return dateFormatter.string(from: date)
	}

	if let date = dateObject as? Date {
		return dateFormatter.string(from: date)
	}

	if let date = dateObject as? NSDate {
		return dateFormatter.string(from: date as Date)
	}

	return nil
}

/// Parses the date representations servers actually send: an ISO 8601
/// timestamp, or a Unix epoch in seconds. Anything else is left to the caller,
/// which normally falls back to showing the server's text verbatim.
private nonisolated func parseDateValue(_ string: String) -> Date? {
	let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)

	if let date = isoStandardDateFormatter.date(from: trimmed) {
		return date
	}

	if let seconds = TimeInterval(trimmed) {
		return Date(timeIntervalSince1970: seconds)
	}

	return nil
}

public nonisolated func sharedISOStandardDateFormatter() -> DateFormatter {
	isoStandardDateFormatter
}

public nonisolated func randomNumber(_ maximum: UInt32) -> UInt {
	UInt(UInt32.random(in: 0 ..< maximum))
}

public nonisolated func formattedNumber(_ number: Int) -> NSString {
	PluginHost.formattedNumber(number) as NSString
}
