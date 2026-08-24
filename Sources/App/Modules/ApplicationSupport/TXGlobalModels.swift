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
 *********************************************************************** */

import Foundation

private let isoStandardDateFormatter: DateFormatter = {
	let dateFormatter = DateFormatter()
	dateFormatter.locale = Locale(identifier: "en_US_POSIX")
	dateFormatter.timeZone = TimeZone(abbreviation: "UTC")
	dateFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
	return dateFormatter
}()

@_cdecl("TXFormattedTimestamp")
public func formattedTimestamp(_ date: NSDate, _ format: NSString) -> NSString? {
	var global = time_t(date.timeIntervalSince1970)
	var localTime = tm()

	guard localtime_r(&global, &localTime) != nil else {
		return nil
	}

	var outputBuffer = [CChar](repeating: 0, count: 257)

	guard strftime(&outputBuffer, outputBuffer.count, format.utf8String, &localTime) > 0 else {
		return nil
	}

	return NSString(string: String(cString: outputBuffer))
}

@_cdecl("TXHumanReadableTimeInterval")
public func humanReadableTimeInterval(
	_ dateInterval: TimeInterval,
	_ shortValue: Bool,
	_ orderMatrix: UInt
) -> NSString? {
	let units: NSCalendar.Unit = if orderMatrix == 0 {
		[.year, .month, .day, .hour, .minute, .second]
	} else {
		NSCalendar.Unit(rawValue: orderMatrix)
	}

	let unitList: [NSCalendar.Unit] = [.year, .month, .day, .hour, .minute, .second].filter {
		units.contains($0)
	}

	let systemCalendar = Calendar.current
	let date1 = Date()
	let date2 = Date(timeIntervalSinceNow: dateInterval)

	let unitComponents = Set(unitList.map { Calendar.Component($0) })
	let breakdownInfo = systemCalendar.dateComponents(unitComponents, from: date1, to: date2)

	var returnResult: NSMutableString?

	for (index, unit) in unitList.enumerated() {
		let calendarUnit = Calendar.Component(unit)
		var unitValue = breakdownInfo.value(for: calendarUnit) ?? 0

		if unitValue == 0 {
			continue
		}

		if unitValue < 0 {
			unitValue *= -1
		}

		let languageKey = if unitValue == 1 {
			"BasicLanguage[fko-64-\(unit.rawValue)]"
		} else {
			"BasicLanguage[eoq-pr-\(unit.rawValue)]"
		}

		let localizedUnit = LocalizedKey(languageKey)

		if shortValue {
			return NSString(format: "%ld %@", unitValue, localizedUnit)
		}

		if returnResult == nil {
			returnResult = NSMutableString()
		}

		if index == unitList.count - 1 {
			returnResult?.appendFormat("%ld %@", unitValue, localizedUnit)
		} else {
			returnResult?.appendFormat("%ld %@, ", unitValue, localizedUnit)
		}
	}

	if let returnResult, returnResult.length > 0 {
		return returnResult.copy() as? NSString
	}

	return NSString(format: "0 %@", LocalizedKey("BasicLanguage[eoq-pr-128]"))
}

@_cdecl("TXFormatDateLongStyle")
public func formatDateLongStyle(_ dateObject: AnyObject, _ relativeOutput: Bool) -> NSString? {
	formatDateValue(dateObject, .long, .long, relativeOutput) as NSString?
}

public func formatDateLongStyle(_ dateObject: Any, _ relativeOutput: Bool) -> String? {
	formatDateValue(dateObject, .long, .long, relativeOutput)
}

@_cdecl("TXFormatDate")
public func formatDate(
	_ dateObject: AnyObject,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> NSString? {
	formatDateValue(dateObject, dateStyle, timeStyle, relativeOutput) as NSString?
}

public func formatDate(
	_ dateObject: Any,
	_ dateStyle: DateFormatter.Style,
	_ timeStyle: DateFormatter.Style,
	_ relativeOutput: Bool
) -> String? {
	formatDateValue(dateObject, dateStyle, timeStyle, relativeOutput)
}

private func formatDateValue(
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
		return dateFormatter.string(for: string)
	}

	if let date = dateObject as? Date {
		return dateFormatter.string(from: date)
	}

	if let date = dateObject as? NSDate {
		return dateFormatter.string(from: date as Date)
	}

	return nil
}

@_cdecl("TXSharedISOStandardDateFormatter")
public func sharedISOStandardDateFormatter() -> DateFormatter {
	isoStandardDateFormatter
}

@_cdecl("TXRandomNumber")
public func randomNumber(_ maximum: UInt32) -> UInt {
	UInt(arc4random_uniform(maximum))
}

@_cdecl("TXFormattedNumber")
public func formattedNumber(_ number: Int) -> NSString {
	NumberFormatter.localizedString(from: NSNumber(value: number), number: .decimal) as NSString
}

private extension Calendar.Component {
	init(_ unit: NSCalendar.Unit) {
		switch unit {
		case .year:
			self = .year
		case .month:
			self = .month
		case .day:
			self = .day
		case .hour:
			self = .hour
		case .minute:
			self = .minute
		case .second:
			self = .second
		default:
			self = .second
		}
	}
}
