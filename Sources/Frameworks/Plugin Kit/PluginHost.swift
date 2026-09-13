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

/// Constants and formatting shared between Glasstual and the plugins it
/// bundles.
///
/// The host injects everything else through `PluginHostContext`; nothing here
/// reaches into the application by name or selector.
public enum PluginHost {
	public static let zncPlaybackCapabilityRawValue: UInt = 1 << 27
	public static let defaultMaximumNicknameLength: UInt = 50

	public static func formattedNumber(_ number: Int) -> String {
		number.formatted(.number.locale(.autoupdatingCurrent))
	}

	public static func humanReadableTimeInterval(
		_ dateInterval: TimeInterval,
		shortValue: Bool,
		units orderMatrix: NSCalendar.Unit = []
	) -> String {
		let requested = orderMatrix.isEmpty ? measurableUnits : measurableUnits.filter {
			orderMatrix.contains($0.unit)
		}
		let calendar = Calendar.autoupdatingCurrent
		let startDate = Date()
		/* The interval can be server text a caller read as a `Double`, and
		 `Double("nan")` parses. Foundation clamps the resulting date rather
		 than trapping, which turns a NaN into a plausible-looking span in the
		 wrong direction; nothing to measure reads as nothing. */
		let endDate = startDate.addingTimeInterval(dateInterval.isFinite ? dateInterval : 0)
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

		let formatStyle = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: calendar,
			fields: fields.isEmpty ? [.second] : fields
		)

		return formatStyle.format(dateRange)
	}

	/** One unit the interval can be reported in, largest first.

	 Three spellings of the same unit meet here: `NSCalendar.Unit` is what a
	 caller asks in, `Calendar.Component` is what measures the span, and
	 `Date.ComponentsFormatStyle.Field` is what prints it. One row per unit keeps
	 them together instead of in three switches that have to agree. */
	private struct MeasurableUnit {
		let unit: NSCalendar.Unit
		let component: Calendar.Component
		let field: Date.ComponentsFormatStyle.Field
	}

	private static let measurableUnits = [
		MeasurableUnit(unit: .year, component: .year, field: .year),
		MeasurableUnit(unit: .month, component: .month, field: .month),
		MeasurableUnit(unit: .day, component: .day, field: .day),
		MeasurableUnit(unit: .hour, component: .hour, field: .hour),
		MeasurableUnit(unit: .minute, component: .minute, field: .minute),
		MeasurableUnit(unit: .second, component: .second, field: .second),
	]
}
