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

@objc(TVCValidatedComboBox)
@MainActor
public final class ValidatedComboBox: NSComboBox {
	@objc public var validationBlock: ((String) -> String?)?
	@objc public var stringValueUsesOnlyFirstToken = false
	@objc public var stringValueIsTrimmed = false
	@objc public var stringValueIsInvalidOnEmpty = false
	@objc public var performValidationWhenEmpty = false
	@objc public weak var textDidChangeCallback: AnyObject?
	@objc public var caseInsensitiveComplete = false
	@objc public var defaultValue: String?

	private var cachedValidValue = false
	@objc public private(set) var valueIsPredefined = false
	private var validationPerformed = false
	private var listVisible = false
	private var selectionChangedWhileListVisible = false
	private var selectionChangedWhileSetting = false
	@objc public private(set) var lastValidationErrorDescription: String?

	@objc public var value: String {
		if let selected = objectValueOfSelectedItem as? String {
			return selected
		}

		var processedValue = stringValue

		if stringValueUsesOnlyFirstToken {
			processedValue = (processedValue as NSString).trimAndGetFirstToken
		} else if stringValueIsTrimmed {
			processedValue = (processedValue as NSString).trim
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

	override public func awakeFromNib() {
		super.awakeFromNib()

		cachedValidValue = false

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(comboBoxSelectionDidChange(_:)),
			name: NSComboBox.selectionDidChangeNotification,
			object: self
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(comboBoxWillPopUp(_:)),
			name: NSComboBox.willPopUpNotification,
			object: self
		)

		NotificationCenter.default.addObserver(
			self,
			selector: #selector(comboBoxWillDismiss(_:)),
			name: NSComboBox.willDismissNotification,
			object: self
		)
	}

	deinit {
		MainActor.assumeIsolated {
			closeValidationErrorPopover()
		}
		NotificationCenter.default.removeObserver(self)
	}

	override public var stringValue: String {
		get {
			super.stringValue
		}
		set {
			super.stringValue = newValue

			let objectIndex = indexOfItem(withObjectValue: newValue)

			if objectIndex != NSNotFound {
				selectionChangedWhileSetting = true
				selectItem(at: objectIndex)
				return
			}

			resetSelection()
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

	override public func textDidChange(_: Notification) {
		DispatchQueue.main.async { [weak self] in
			self?.recalculateSelection()
		}
	}

	override public func viewWillMove(toWindow newWindow: NSWindow?) {
		if newWindow == nil {
			closeValidationErrorPopover()
		}
	}

	@objc private func comboBoxSelectionDidChange(_: Notification) {
		selectionChangedWhileListVisible = listVisible

		if selectionChangedWhileSetting {
			selectionChangedWhileSetting = false
			recalculateSelection()
		}
	}

	@objc private func comboBoxWillPopUp(_: Notification) {
		listVisible = true
	}

	@objc private func comboBoxWillDismiss(_: Notification) {
		listVisible = false

		if selectionChangedWhileListVisible {
			selectionChangedWhileListVisible = false
			recalculateSelection()
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
			errorDescription = LocalizedKey("BasicLanguage[fo8-1h]")
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

	private func resetSelection() {
		valueIsPredefined = false
		valueChangedAction()
	}

	private func recalculateSelection() {
		valueIsPredefined = indexOfSelectedItem >= 0
		valueChangedAction()
	}

	private func valueChangedAction() {
		if valueIsPredefined {
			cachedValidValue = true
			lastValidationErrorDescription = nil
		} else {
			performValidation()
		}

		valueChangedActionPostflight()
	}

	private func valueChangedActionPostflight() {
		closeValidationErrorPopover()
		informCallbackTextDidChange()
		needsDisplay = true
	}

	private func updateBackgroundForValidity() {
		if cachedValidValue || validationPerformed == false {
			drawsBackground = false
			backgroundColor = .textBackgroundColor
		} else {
			drawsBackground = true
			backgroundColor = NSColor.systemRed.withAlphaComponent(0.08)
		}
	}

	private func informCallbackTextDidChange() {
		guard let textDidChangeCallback else {
			return
		}

		let selector = NSSelectorFromString("validatedTextFieldTextDidChange:")

		if textDidChangeCallback.responds(to: selector) {
			textDidChangeCallback.perform(selector, with: self)
		}
	}
}

@objc(TVCValidatedComboBoxCell)
public final class ValidatedComboBoxCell: NSComboBoxCell {}
