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

import AppKit
import CocoaExtensions

@objc(TVCValidatedTextField)
public final class ValidatedTextField: NSTextField {
	@objc public var validationBlock: ((String) -> String?)?
	@objc public var stringValueUsesOnlyFirstToken = false
	@objc public var stringValueIsTrimmed = false
	@objc public var stringValueIsInvalidOnEmpty = false
	@objc public var performValidationWhenEmpty = false
	@objc public weak var textDidChangeCallback: AnyObject?
	@objc public var defaultValue: String?

	private var cachedValidValue = false
	private var validationPerformed = false
	@objc public private(set) var lastValidationErrorDescription: String?

	@objc public var value: String {
		var processedValue = super.stringValue

		if stringValueUsesOnlyFirstToken {
			processedValue = (processedValue as NSString).ceTrimAndGetFirstToken
		} else if stringValueIsTrimmed {
			processedValue = (processedValue as NSString).ceTrim as String
		}

		if processedValue.isEmpty {
			if let defaultValue, stringValueIsInvalidOnEmpty == false {
				return defaultValue
			}
		}

		return processedValue
	}

	@objc public var lowercaseValue: String {
		value.lowercased()
	}

	@objc public var uppercaseValue: String {
		value.uppercased()
	}

	@objc public var valueIsEmpty: Bool {
		stringValue.isEmpty
	}

	@objc public var valueIsValid: Bool {
		cachedValidValue
	}

	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()
		MainActor.assumeIsolated {
			cachedValidValue = false
		}
	}

	deinit {
		MainActor.assumeIsolated {
			closeValidationErrorPopover()
		}
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

	override public func textDidChange(_: Notification) {
		valueChangedAction()
	}

	override public func viewWillMove(toWindow newWindow: NSWindow?) {
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

	@objc public func performValidation() {
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

	@objc @discardableResult
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

	@objc public func closeValidationErrorPopover() {
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
		guard let textDidChangeCallback else {
			return
		}

		let selector = NSSelectorFromString("validatedTextFieldTextDidChange:")

		if textDidChangeCallback.responds(to: selector) {
			_ = textDidChangeCallback.perform(selector, with: self)
		}
	}
}

@objc(TVCValidatedTextFieldCell)
public final class ValidatedTextFieldCell: NSTextFieldCell {}
