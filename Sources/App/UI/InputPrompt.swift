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

@objc(TDCInputPrompt)
@MainActor
public final class InputPrompt: NSObject {
	/// The alert and the text field inside it. The field used to be handed
	/// back through an `AutoreleasingUnsafeMutablePointer` out-parameter.
	private static func makeAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		prefillString: String?
	) -> (alert: NSAlert, textField: NSTextField) {
		let textField = NSTextField()
		textField.translatesAutoresizingMaskIntoConstraints = false

		textField.addConstraints([
			NSLayoutConstraint(
				item: textField,
				attribute: .width,
				relatedBy: .equal,
				toItem: nil,
				attribute: .notAnAttribute,
				multiplier: 1.0,
				constant: 295.0
			),
			NSLayoutConstraint(
				item: textField,
				attribute: .height,
				relatedBy: .equal,
				toItem: nil,
				attribute: .notAnAttribute,
				multiplier: 1.0,
				constant: 22.0
			),
		])

		textField.isEditable = true
		textField.isSelectable = true
		textField.drawsBackground = true
		textField.isBordered = true
		textField.isBezeled = true
		textField.cell?.lineBreakMode = .byTruncatingTail

		if let prefillString {
			textField.stringValue = prefillString
		}

		let alert = NSAlert()
		alert.alertStyle = .informational
		alert.messageText = titleText
		alert.informativeText = bodyText
		alert.addButton(withTitle: buttonDefault)

		if let buttonAlternate {
			alert.addButton(withTitle: buttonAlternate)
		}

		alert.accessoryView = textField
		alert.window.initialFirstResponder = textField

		return (alert, textField)
	}

	@objc(promptWithMessage:title:defaultButton:alternateButton:prefillString:completionBlock:)
	public static func prompt(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		prefillString: String?,
		completionBlock: @escaping (NSApplication.ModalResponse, String) -> Void
	) {
		let (alert, textField) = makeAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			prefillString: prefillString
		)

		let window = NSApp.keyWindow ?? NSApp.mainWindow

		if let window {
			alert.beginSheetModal(for: window) { response in
				completionBlock(response, textField.stringValue)
			}
		} else {
			let response = alert.runModal()
			completionBlock(response, textField.stringValue)
		}
	}
}
