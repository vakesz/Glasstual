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
import CocoaExtensions

/// Told when a validated control's text changed. `sender` is the control, so
/// one observer can serve several fields and tell them apart by identity.
@MainActor
public protocol ValidatedControlChangeObserver: AnyObject {
	func validatedTextFieldTextDidChange(_ sender: NSControl)
}

@objc(TVCValidatedTextField)
public final class ValidatedTextField: NSTextField {
	public var validationBlock: ((String) -> String?)?
	public var stringValueUsesOnlyFirstToken = false
	public var stringValueIsTrimmed = false
	public var stringValueIsInvalidOnEmpty = false
	public var performValidationWhenEmpty = false
	public weak var textDidChangeCallback: (any ValidatedControlChangeObserver)?
	public var defaultValue: String?

	private var cachedValidValue = false
	private var validationPerformed = false
	public private(set) var lastValidationErrorDescription: String?

	public var value: String {
		var processedValue = super.stringValue

		if stringValueUsesOnlyFirstToken {
			processedValue = processedValue.firstToken
		} else if stringValueIsTrimmed {
			processedValue = processedValue.trimmingCharacters(in: .whitespacesAndNewlines)
		}

		if processedValue.isEmpty {
			if let defaultValue, stringValueIsInvalidOnEmpty == false {
				return defaultValue
			}
		}

		return processedValue
	}

	public var lowercaseValue: String {
		value.lowercased()
	}

	public var uppercaseValue: String {
		value.uppercased()
	}

	public var valueIsEmpty: Bool {
		stringValue.isEmpty
	}

	public var valueIsValid: Bool {
		cachedValidValue
	}

	/** Isolated so the popover teardown runs on the main actor whichever thread
	 drops the last reference. */
	isolated deinit {
		closeValidationErrorPopover()
	}

	override public var stringValue: String {
		get {
			super.stringValue
		}
		set {
			super.stringValue = newValue
			valueChangedAction()
		}
	}

	override public func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)
		valueChangedAction()
	}

	override public func viewWillMove(toWindow newWindow: NSWindow?) {
		super.viewWillMove(toWindow: newWindow)

		if newWindow == nil {
			closeValidationErrorPopover()
		}
	}

	override public var integerValue: Int {
		get {
			Int(value) ?? 0
		}
		set {
			stringValue = "\(newValue)"
		}
	}

	public func performValidation() {
		let stringToValidate = stringValue
		var errorDescription: String?

		if stringToValidate.isEmpty == false {
			errorDescription = validationBlock?(stringToValidate)
		} else if performValidationWhenEmpty {
			errorDescription = validationBlock?(stringToValidate)
		} else if stringValueIsInvalidOnEmpty {
			errorDescription = ApplicationStrings.requiredField
		}

		validationPerformed = true
		lastValidationErrorDescription = errorDescription
		cachedValidValue = errorDescription == nil
		updateBackgroundForValidity()
	}

	@discardableResult
	public func showValidationErrorPopover() -> Bool {
		if validationPerformed == false {
			performValidation()
		}

		guard let errorDescription = lastValidationErrorDescription else {
			return false
		}

		guard window != nil else {
			return false
		}

		ErrorMessagePopoverController.sharedController().showMessage(errorDescription, for: self)
		return true
	}

	public func closeValidationErrorPopover() {
		ErrorMessagePopoverController.sharedController().closeMessage(for: self)
	}

	private func valueChangedAction() {
		performValidation()
		closeValidationErrorPopover()
		informCallbackTextDidChange()
	}

	private func updateBackgroundForValidity() {
		if cachedValidValue || validationPerformed == false {
			drawsBackground = false
			backgroundColor = .textBackgroundColor
			setAccessibilityHelp(nil)
		} else {
			drawsBackground = true
			backgroundColor = NSColor.systemRed.withAlphaComponent(0.08)
			setAccessibilityHelp(lastValidationErrorDescription)
		}
	}

	private func informCallbackTextDidChange() {
		textDidChangeCallback?.validatedTextFieldTextDidChange(self)
	}
}

@objc(TVCValidatedTextFieldCell)
public final class ValidatedTextFieldCell: NSTextFieldCell {}
