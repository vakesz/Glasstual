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
 *********************************************************************** */

import AppKit

@discardableResult
@MainActor
func updatePreferredMaxLayoutWidth(of field: NSTextField) -> Bool {
	guard field.cell?.wraps == true else {
		return false
	}

	let width = field.bounds.width

	guard width > 0, field.preferredMaxLayoutWidth != width else {
		return false
	}

	field.preferredMaxLayoutWidth = width
	field.invalidateIntrinsicContentSize()

	return true
}

public final class AutoExpandingTextField: NSTextField {
	override public func layout() {
		super.layout()

		updatePreferredMaxLayoutWidth(of: self)
	}

	override public func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)

		invalidateIntrinsicContentSize()
	}
}

@objc(TVCAutoExpandingTokenField)
public final class AutoExpandingTokenField: NSTokenField {
	override public func layout() {
		super.layout()

		updatePreferredMaxLayoutWidth(of: self)
	}

	override public func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)

		invalidateIntrinsicContentSize()
	}
}
