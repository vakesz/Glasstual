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

import AppKit

@objc(TPI_ChatFilterValidatedTextField)
final class ChatFilterValidatedTextField: NSTextField {
	var validationBlock: ((String) -> String?)?
	var performValidationWhenEmpty = false
	var stringValueIsInvalidOnEmpty = false
	var stringValueUsesOnlyFirstToken = false
	var stringValueIsTrimmed = false
	var valueDidChange: ((ChatFilterValidatedTextField) -> Void)?

	private var validationPopover: NSPopover?
	private(set) var lastValidationErrorDescription: String?

	var value: String {
		var result = stringValue
		if stringValueUsesOnlyFirstToken {
			result = result.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? ""
		} else if stringValueIsTrimmed {
			result = result.trimmingCharacters(in: .whitespacesAndNewlines)
		}
		return result
	}

	var valueIsValid: Bool {
		performValidation()
		return lastValidationErrorDescription == nil
	}

	override var stringValue: String {
		get { super.stringValue }
		set {
			super.stringValue = newValue
			valueChanged()
		}
	}

	override func textDidChange(_: Notification) {
		valueChanged()
	}

	func performValidation() {
		let currentValue = value
		if currentValue.isEmpty, performValidationWhenEmpty == false {
			lastValidationErrorDescription = stringValueIsInvalidOnEmpty ? "A value is required." : nil
		} else {
			lastValidationErrorDescription = validationBlock?(currentValue)
		}
		drawsBackground = lastValidationErrorDescription != nil
		backgroundColor = lastValidationErrorDescription == nil
			? .textBackgroundColor
			: .systemRed.withAlphaComponent(0.08)
		setAccessibilityHelp(lastValidationErrorDescription)
	}

	func showValidationErrorPopover() {
		performValidation()
		guard let message = lastValidationErrorDescription, window != nil else { return }
		validationPopover?.close()

		let label = NSTextField(wrappingLabelWithString: message)
		label.maximumNumberOfLines = 0
		label.preferredMaxLayoutWidth = 280
		let insetView = NSView()
		label.translatesAutoresizingMaskIntoConstraints = false
		insetView.addSubview(label)
		NSLayoutConstraint.activate([
			label.leadingAnchor.constraint(equalTo: insetView.leadingAnchor, constant: 12),
			label.trailingAnchor.constraint(equalTo: insetView.trailingAnchor, constant: -12),
			label.topAnchor.constraint(equalTo: insetView.topAnchor, constant: 10),
			label.bottomAnchor.constraint(equalTo: insetView.bottomAnchor, constant: -10),
		])

		let controller = NSViewController()
		controller.view = insetView
		let popover = NSPopover()
		popover.behavior = .transient
		popover.contentViewController = controller
		popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
		validationPopover = popover
	}

	private func valueChanged() {
		performValidation()
		validationPopover?.close()
		valueDidChange?(self)
	}
}

@objc(TPI_ChatFilterValidatedTextFieldCell)
final class ChatFilterValidatedTextFieldCell: NSTextFieldCell {}
