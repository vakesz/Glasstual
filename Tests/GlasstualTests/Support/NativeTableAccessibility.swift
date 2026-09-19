// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Read the hierarchy AppKit exports, including its proxy rows and cells.
/// Looking at NSTableRowView directly bypasses those exported objects.
@MainActor
enum NativeTableAccessibility {
	static func rows(in table: NSTableView) -> [Any] {
		// The table's narrower NSAccessibilityTable overload bridges to
		// NSAccessibilityRow, which macOS 27's NSTableRow proxies do not adopt.
		(table as any NSAccessibilityProtocol).accessibilityRows() ?? []
	}

	static func descendants(of element: Any) -> [any NSAccessibilityProtocol] {
		let current = element as? any NSAccessibilityProtocol
		let children = current?.accessibilityChildren() ?? legacyAttribute(.children, of: element) as? [Any] ?? []
		return (current.map { [$0] } ?? []) + children.flatMap { descendants(of: $0) }
	}

	static func isSelected(_ element: Any) -> Bool {
		if let element = element as? any NSAccessibilityProtocol {
			return element.isAccessibilitySelected()
		}
		return (legacyAttribute(.selected, of: element) as? NSNumber)?.boolValue == true
	}

	private static func legacyAttribute(_ attribute: NSAccessibility.Attribute, of element: Any) -> Any? {
		// AppKit's proxy objects implement the Objective-C accessibility
		// boundary without adopting the modern NSAccessibility protocol.
		guard let object = element as? NSObject else { return nil }
		let getter = NSSelectorFromString("accessibilityAttributeValue:")
		guard object.responds(to: getter) else { return nil }
		return object.perform(getter, with: attribute.rawValue)?.takeUnretainedValue()
	}
}
