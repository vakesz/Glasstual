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
 *********************************************************************** */

import Foundation

nonisolated struct LogRendererConfiguration: ExpressibleByDictionaryLiteral { // nonisolated: value
	private var values: [LogRendererConfigurationKey: Any] = [:]

	init() {}

	init(dictionaryLiteral elements: (LogRendererConfigurationKey, Any)...) {
		values = Dictionary(uniqueKeysWithValues: elements)
	}

	subscript(key: LogRendererConfigurationKey) -> Any? {
		get { values[key] }
		set { values[key] = newValue }
	}

	func value<Value>(for key: LogRendererConfigurationKey, as _: Value.Type = Value.self) -> Value? {
		values[key] as? Value
	}

	func bool(for key: LogRendererConfigurationKey) -> Bool {
		(values[key] as? NSNumber)?.boolValue ?? (values[key] as? Bool ?? false)
	}
}

nonisolated enum LogRendererConfigurationKey: Sendable { // nonisolated: value
	case renderLinks
	case lineType
	case memberType
	case highlightKeywords
	case excludedKeywords
	case preferredFont
	case preferredFontColor
}
