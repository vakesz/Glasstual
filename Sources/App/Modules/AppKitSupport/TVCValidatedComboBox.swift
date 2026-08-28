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
import CocoaExtensions

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

	/* ISOLATION-EXCEPTION: `NSObject.awakeFromNib()` is declared nonisolated, so the
	 override cannot be main-actor isolated. AppKit decodes nibs on the main thread
	 only, which is what makes the assumption safe. */
	override public nonisolated func awakeFromNib() {
		super.awakeFromNib()

		MainActor.assumeIsolated {
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
	}

	/** Isolated so the popover teardown runs on the main actor whichever thread
	 drops the last reference. */
	isolated deinit {
		closeValidationErrorPopover()
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

	override public func textDidChange(_ notification: Notification) {
		super.textDidChange(notification)

		DispatchQueue.main.async { [weak self] in
			self?.recalculateSelection()
		}
	}

	override public func viewWillMove(toWindow newWindow: NSWindow?) {
		super.viewWillMove(toWindow: newWindow)

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
			_ = textDidChangeCallback.perform(selector, with: self)
		}
	}
}

@objc(TVCValidatedComboBoxCell)
public final class ValidatedComboBoxCell: NSComboBoxCell {}
