/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import ObjectiveC.runtime

public struct PluginApplicationSnapshot: Equatable, Sendable {
	public let timeIntervalSinceLaunch: TimeInterval
	public let timeIntervalSinceInstall: TimeInterval
	public let runCount: UInt
	public let birthday: TimeInterval

	public init(
		timeIntervalSinceLaunch: TimeInterval,
		timeIntervalSinceInstall: TimeInterval,
		runCount: UInt,
		birthday: TimeInterval
	) {
		self.timeIntervalSinceLaunch = timeIntervalSinceLaunch
		self.timeIntervalSinceInstall = timeIntervalSinceInstall
		self.runCount = runCount
		self.birthday = birthday
	}
}

public enum PluginThemeStorageLocation: UInt, Sendable {
	case unknown = 0
	case bundled = 1
	case custom = 2
}

public enum PluginThemeAppearance: UInt, Sendable {
	case system = 0
	case dark = 1
	case light = 2
}

public struct PluginThemeSnapshot: Equatable, Sendable {
	public let name: String
	public let storageLocation: PluginThemeStorageLocation
	public let resolvedAppearance: PluginThemeAppearance

	public init(
		name: String,
		storageLocation: PluginThemeStorageLocation,
		resolvedAppearance: PluginThemeAppearance
	) {
		self.name = name
		self.storageLocation = storageLocation
		self.resolvedAppearance = resolvedAppearance
	}
}

public extension PluginHost {
	static func applicationSnapshot() -> PluginApplicationSnapshot? {
		guard let timeIntervalSinceLaunch = HostRuntime.classTimeInterval(
			classNamed: "TPCApplicationInfo",
			selectorNamed: "timeIntervalSinceApplicationLaunch"
		), let timeIntervalSinceInstall = HostRuntime.classTimeInterval(
			classNamed: "TPCApplicationInfo",
			selectorNamed: "timeIntervalSinceApplicationInstall"
		), let runCount = HostRuntime.classUInt(
			classNamed: "TPCApplicationInfo",
			selectorNamed: "applicationRunCount"
		), let birthday = HostRuntime.classTimeInterval(
			classNamed: "TPCApplicationInfo",
			selectorNamed: "applicationBirthday"
		)
		else {
			return nil
		}

		return PluginApplicationSnapshot(
			timeIntervalSinceLaunch: timeIntervalSinceLaunch,
			timeIntervalSinceInstall: timeIntervalSinceInstall,
			runCount: runCount,
			birthday: birthday
		)
	}

	static func themeSnapshot() -> PluginThemeSnapshot? {
		guard let controller = HostRuntime.classObject(
			classNamed: "TXSharedApplication",
			selectorNamed: "sharedThemeController"
		), let name = HostRuntime.object(controller, selectorNamed: "name") as? String,
		let storageRawValue = HostRuntime.uint(controller, selectorNamed: "storageLocation"),
		let storageLocation = PluginThemeStorageLocation(rawValue: storageRawValue),
		let theme = HostRuntime.object(controller, selectorNamed: "theme"),
		let appearanceRawValue = HostRuntime.uint(theme, selectorNamed: "appearance"),
		let appearance = PluginThemeAppearance(rawValue: appearanceRawValue)
		else {
			return nil
		}

		let resolvedAppearance: PluginThemeAppearance
		if appearance == .system {
			guard let hostAppearance = HostRuntime.classObject(
				classNamed: "TXSharedApplication",
				selectorNamed: "sharedAppearance"
			), let properties = HostRuntime.object(hostAppearance, selectorNamed: "properties"),
			let isDark = HostRuntime.bool(properties, selectorNamed: "isDarkAppearance")
			else {
				return nil
			}
			resolvedAppearance = isDark ? .dark : .light
		} else {
			resolvedAppearance = appearance
		}

		return PluginThemeSnapshot(
			name: name,
			storageLocation: storageLocation,
			resolvedAppearance: resolvedAppearance
		)
	}

	static func formattedNumber(_ number: Int) -> String {
		number.formatted(.number.locale(.autoupdatingCurrent))
	}

	static func humanReadableTimeInterval(
		_ dateInterval: TimeInterval,
		shortValue: Bool,
		units orderMatrix: NSCalendar.Unit = []
	) -> String {
		let selectedUnits: NSCalendar.Unit = orderMatrix.isEmpty
			? [.year, .month, .day, .hour, .minute, .second]
			: orderMatrix
		let selectedComponents = HostCalendarComponent.allCases.filter {
			selectedUnits.contains($0.calendarUnit)
		}
		let calendar = Calendar.autoupdatingCurrent
		let startDate = Date()
		let endDate = startDate.addingTimeInterval(dateInterval)
		let dateRange = min(startDate, endDate) ..< max(startDate, endDate)
		let formatComponents: Set<Date.ComponentsFormatStyle.Field>

		if shortValue {
			let values = calendar.dateComponents(
				Set(selectedComponents.map(\.calendarComponent)),
				from: dateRange.lowerBound,
				to: dateRange.upperBound
			)
			let largestNonzeroComponent = selectedComponents.first {
				values.value(for: $0.calendarComponent) != 0
			} ?? .second
			formatComponents = [largestNonzeroComponent.formatField]
		} else {
			formatComponents = Set(selectedComponents.map(\.formatField))
		}

		let formatStyle = Date.ComponentsFormatStyle(
			style: .wide,
			calendar: calendar,
			fields: formatComponents.isEmpty ? [.second] : formatComponents
		)

		return formatStyle.format(dateRange)
	}
}

enum HostRuntime {
	typealias ObjectMethod = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
	typealias TimeIntervalMethod = @convention(c) (AnyObject, Selector) -> TimeInterval
	typealias UIntMethod = @convention(c) (AnyObject, Selector) -> UInt
	typealias BoolMethod = @convention(c) (AnyObject, Selector) -> Bool

	static func classObject(classNamed className: String, selectorNamed selectorName: String) -> AnyObject? {
		guard let objectClass = NSClassFromString(className),
		      let implementation = classImplementation(objectClass, selectorNamed: selectorName)
		else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: ObjectMethod.self)
		return method(objectClass, selector)?.takeUnretainedValue()
	}

	static func classTimeInterval(classNamed className: String, selectorNamed selectorName: String) -> TimeInterval? {
		guard let objectClass = NSClassFromString(className),
		      let implementation = classImplementation(objectClass, selectorNamed: selectorName)
		else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: TimeIntervalMethod.self)
		return method(objectClass, selector)
	}

	static func classUInt(classNamed className: String, selectorNamed selectorName: String) -> UInt? {
		guard let objectClass = NSClassFromString(className),
		      let implementation = classImplementation(objectClass, selectorNamed: selectorName)
		else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: UIntMethod.self)
		return method(objectClass, selector)
	}

	static func object(_ object: AnyObject, selectorNamed selectorName: String) -> AnyObject? {
		guard let implementation = instanceImplementation(object, selectorNamed: selectorName) else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: ObjectMethod.self)
		return method(object, selector)?.takeUnretainedValue()
	}

	static func uint(_ object: AnyObject, selectorNamed selectorName: String) -> UInt? {
		guard let implementation = instanceImplementation(object, selectorNamed: selectorName) else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: UIntMethod.self)
		return method(object, selector)
	}

	static func bool(_ object: AnyObject, selectorNamed selectorName: String) -> Bool? {
		guard let implementation = instanceImplementation(object, selectorNamed: selectorName) else {
			return nil
		}

		let selector = NSSelectorFromString(selectorName)
		let method = unsafeBitCast(implementation, to: BoolMethod.self)
		return method(object, selector)
	}

	private static func classImplementation(_ objectClass: AnyClass, selectorNamed selectorName: String) -> IMP? {
		class_getClassMethod(objectClass, NSSelectorFromString(selectorName)).map(method_getImplementation)
	}

	private static func instanceImplementation(_ object: AnyObject, selectorNamed selectorName: String) -> IMP? {
		guard let objectClass = object_getClass(object) else {
			return nil
		}

		return class_getInstanceMethod(objectClass, NSSelectorFromString(selectorName)).map(method_getImplementation)
	}
}

private enum HostCalendarComponent: CaseIterable, Hashable {
	case year
	case month
	case day
	case hour
	case minute
	case second

	var calendarComponent: Calendar.Component {
		switch self {
		case .year: .year
		case .month: .month
		case .day: .day
		case .hour: .hour
		case .minute: .minute
		case .second: .second
		}
	}

	var calendarUnit: NSCalendar.Unit {
		switch self {
		case .year: .year
		case .month: .month
		case .day: .day
		case .hour: .hour
		case .minute: .minute
		case .second: .second
		}
	}

	var formatField: Date.ComponentsFormatStyle.Field {
		switch self {
		case .year: .year
		case .month: .month
		case .day: .day
		case .hour: .hour
		case .minute: .minute
		case .second: .second
		}
	}
}
