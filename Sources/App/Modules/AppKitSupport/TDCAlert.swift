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

@objc public enum TDCAlertResponse: UInt, Sendable {
	case `default` = 1000
	case alternate = 1001
	case other = 1002
}

public typealias TDCAlertCompletionBlock = (TDCAlertResponse, Bool, Any?) -> Void

private final class AlertContext: NSObject, @unchecked Sendable {
	var suppressionKey: String?
	var completionBlock: TDCAlertCompletionBlock?
}

@objc(TDCAlert)
public final class TDCAlert: NSObject {
	private static let suppressionPrefix = "Text Input Prompt Suppression -> "

	// MARK: - Modal Alerts (Panel)

	@objc(modalAlertWithMessage:title:defaultButton:alternateButton:)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?
	) -> Bool {
		modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			suppressionResponse: nil
		)
	}

	@objc(modalAlertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?
	) -> Bool {
		modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			suppressionResponse: nil
		)
	}

	@objc(modalAlertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:accessoryView:)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?
	) -> Bool {
		modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: accessoryView,
			suppressionResponse: nil
		)
	}

	@objc(modalAlertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:suppressionResponse:)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		suppressionResponse: UnsafeMutablePointer<ObjCBool>?
	) -> Bool {
		modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			suppressionResponse: suppressionResponse
		)
	}

	@objc(
		modalAlertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:accessoryView:suppressionResponse:
	)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?,
		suppressionResponse: UnsafeMutablePointer<ObjCBool>?
	) -> Bool {
		let response = modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: accessoryView,
			suppressionResponse: suppressionResponse
		)

		return response == .default
	}

	@objc(modalAlertWithMessage:title:defaultButton:alternateButton:otherButton:)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?
	) -> TDCAlertResponse {
		modalAlert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			suppressionResponse: nil
		)
	}

	@objc(
		modalAlertWithMessage:title:defaultButton:alternateButton:otherButton:suppressionKey:suppressionText:accessoryView:suppressionResponse:
	)
	public static func modalAlert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?,
		suppressionResponse: UnsafeMutablePointer<ObjCBool>?
	) -> TDCAlertResponse {
		if Thread.isMainThread == false {
			nonisolated(unsafe) var result: TDCAlertResponse = .alternate

			performSynchronouslyOnMainQueue {
				result = modalAlert(
					withMessage: bodyText,
					title: titleText,
					defaultButton: buttonDefault,
					alternateButton: buttonAlternate,
					otherButton: buttonOther,
					suppressionKey: suppressKey,
					suppressionText: suppressText,
					accessoryView: accessoryView,
					suppressionResponse: suppressionResponse
				)
			}

			return result
		}

		let result: (response: TDCAlertResponse, suppression: Bool?) = MainActor.assumeIsolated {
			var suppressKey = suppressKey
			var suppressText = suppressText

			if let key = suppressKey {
				suppressKey = suppressionKey(withBase: key)

				if isSuppressed(fullKey: suppressKey!) {
					/* The alert *was* suppressed; reporting nil left the caller's
					 out-parameter holding whatever it was initialised to. */
					return (.default, true)
				}
			}

			if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
				suppressText = PromptStrings.Alert.doNotShowAgain
			}

			let alert = NSAlert()
			alert.messageText = titleText
			alert.informativeText = bodyText
			alert.addButton(withTitle: buttonDefault)

			if let buttonAlternate {
				alert.addButton(withTitle: buttonAlternate)
			}

			if let buttonOther {
				alert.addButton(withTitle: buttonOther)
			}

			/* Only a key can record the choice, so showing the checkbox without one gave
			 the user a "do not show again" control that did nothing. */
			if suppressKey != nil {
				alert.showsSuppressionButton = true
				alert.suppressionButton?.title = suppressText ?? ""
			}

			if let accessoryView {
				alert.accessoryView = accessoryView
			}

			let returnCode = alert.runModal()
			let response = convertResponse(from: returnCode)

			let suppressed = recordSuppression(
				for: alert.suppressionButton,
				withKey: suppressKey
			)

			return (response, suppressed)
		}

		if let suppressionResponse, let suppression = result.suppression {
			suppressionResponse.pointee = ObjCBool(suppression)
		}

		return result.response
	}
}

// MARK: - Non-blocking Alerts (Panel)

public extension TDCAlert {
	@objc(alertWithMessage:title:defaultButton:alternateButton:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?
	) -> NSAlert {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: nil
		)!
	}

	@objc(alertWithMessage:title:defaultButton:alternateButton:otherButton:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?
	) -> NSAlert {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: nil
		)!
	}

	@objc(alertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			completionBlock: nil
		)
	}

	@objc(alertWithMessage:title:defaultButton:alternateButton:completionBlock:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(alertWithMessage:title:defaultButton:alternateButton:otherButton:completionBlock:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(alertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:completionBlock:)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(
		alertWithMessage:title:defaultButton:alternateButton:otherButton:suppressionKey:suppressionText:completionBlock:
	)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(
		alertWithMessage:title:defaultButton:alternateButton:suppressionKey:suppressionText:accessoryView:completionBlock:
	)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		alert(
			withMessage: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: nil,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: accessoryView,
			completionBlock: completionBlock
		)
	}

	@objc(
		alertWithMessage:title:defaultButton:alternateButton:otherButton:suppressionKey:suppressionText:accessoryView:completionBlock:
	)
	static func alert(
		withMessage bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?,
		completionBlock: TDCAlertCompletionBlock?
	) -> NSAlert? {
		if Thread.isMainThread == false {
			nonisolated(unsafe) var result: NSAlert?

			performSynchronouslyOnMainQueue {
				result = alert(
					withMessage: bodyText,
					title: titleText,
					defaultButton: buttonDefault,
					alternateButton: buttonAlternate,
					otherButton: buttonOther,
					suppressionKey: suppressKey,
					suppressionText: suppressText,
					accessoryView: accessoryView,
					completionBlock: completionBlock
				)
			}

			return result
		}

		let context = AlertContext()
		context.completionBlock = completionBlock

		return MainActor.assumeIsolated { () -> NSAlert? in
			var suppressKey = suppressKey
			var suppressText = suppressText

			if let key = suppressKey {
				suppressKey = suppressionKey(withBase: key)

				if isSuppressed(fullKey: suppressKey!) {
					context.completionBlock?(.default, true, nil)
					return nil
				}
			}

			if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
				suppressText = PromptStrings.Alert.doNotShowAgain
			}

			let alert = NSAlert()
			alert.alertStyle = .informational
			alert.messageText = titleText
			alert.informativeText = bodyText
			alert.addButton(withTitle: buttonDefault)

			if let buttonAlternate {
				alert.addButton(withTitle: buttonAlternate)
			}

			if let buttonOther {
				alert.addButton(withTitle: buttonOther)
			}

			/* Only a key can record the choice, so showing the checkbox without one gave
			 the user a "do not show again" control that did nothing. */
			if suppressKey != nil {
				alert.showsSuppressionButton = true
				alert.suppressionButton?.title = suppressText ?? ""
			}

			if let accessoryView {
				alert.accessoryView = accessoryView
			}

			context.suppressionKey = suppressKey

			/* A sheet on the main window is preferred so that the alert is
			 attached to what it is about. When the main window is hidden, any other
			 visible window hosts the sheet instead. */
			let applicationController: ApplicationController = AppController.shared
			var hostWindow: NSWindow? = MainActor.assumeIsolated {
				applicationController.mainWindow
			}

			if hostWindow?.isVisible == false {
				hostWindow = nil

				for window in NSApp.orderedWindows {
					if window.isVisible, window.attachedSheet == nil, (window is NSPanel) == false {
						hostWindow = window
						break
					}
				}
			}

			if let hostWindow {
				alert.beginSheetModal(for: hostWindow) { returnCode in
					alertSheetResponseCallback(alert, returnCode: returnCode, contextInfo: context)
				}
			} else {
				/* Last resort: during launch and migration no window exists yet
				 that could host a sheet, so the alert has to run application
				 modal. Return to the caller before blocking so that this method
				 stays non-blocking regardless of how the alert is presented. */
				performAsynchronouslyOnMainQueue {
					alertSheetResponseCallback(alert, returnCode: alert.runModal(), contextInfo: context)
				}
			}

			return alert
		}
	}
}

// MARK: - Non-blocking Alerts (Sheet)

public extension TDCAlert {
	@objc(alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:)
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?
	) {
		alertSheet(
			with: window,
			body: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: nil
		)
	}

	@objc(alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:completionBlock:)
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		completionBlock: TDCAlertCompletionBlock?
	) {
		alertSheet(
			with: window,
			body: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:accessoryView:completionBlock:)
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		accessoryView: NSView?,
		completionBlock: TDCAlertCompletionBlock?
	) {
		alertSheet(
			with: window,
			body: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: nil,
			suppressionText: nil,
			accessoryView: accessoryView,
			completionBlock: completionBlock
		)
	}

	@objc(
		alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:suppressionKey:suppressionText:completionBlock:
	)
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		completionBlock: TDCAlertCompletionBlock?
	) {
		alertSheet(
			with: window,
			body: bodyText,
			title: titleText,
			defaultButton: buttonDefault,
			alternateButton: buttonAlternate,
			otherButton: buttonOther,
			suppressionKey: suppressKey,
			suppressionText: suppressText,
			accessoryView: nil,
			completionBlock: completionBlock
		)
	}

	@objc(
		alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:suppressionKey:suppressionText:accessoryView:completionBlock:
	)
	static func alertSheet(
		with window: NSWindow,
		body bodyText: String,
		title titleText: String,
		defaultButton buttonDefault: String,
		alternateButton buttonAlternate: String?,
		otherButton buttonOther: String?,
		suppressionKey suppressKey: String?,
		suppressionText suppressText: String?,
		accessoryView: NSView?,
		completionBlock: TDCAlertCompletionBlock?
	) {
		if Thread.isMainThread == false {
			performSynchronouslyOnMainQueue {
				alertSheet(
					with: window,
					body: bodyText,
					title: titleText,
					defaultButton: buttonDefault,
					alternateButton: buttonAlternate,
					otherButton: buttonOther,
					suppressionKey: suppressKey,
					suppressionText: suppressText,
					accessoryView: accessoryView,
					completionBlock: completionBlock
				)
			}

			return
		}

		let context = AlertContext()
		context.completionBlock = completionBlock

		MainActor.assumeIsolated {
			var suppressKey = suppressKey
			var suppressText = suppressText

			if let key = suppressKey {
				suppressKey = suppressionKey(withBase: key)

				if isSuppressed(fullKey: suppressKey!) {
					context.completionBlock?(.default, true, nil)
					return
				}
			}

			if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
				suppressText = PromptStrings.Alert.doNotShowAgain
			}

			let alert = NSAlert()
			alert.alertStyle = .informational
			alert.messageText = titleText
			alert.informativeText = bodyText
			alert.addButton(withTitle: buttonDefault)

			if let buttonAlternate {
				alert.addButton(withTitle: buttonAlternate)
			}

			if let buttonOther {
				alert.addButton(withTitle: buttonOther)
			}

			/* Only a key can record the choice, so showing the checkbox without one gave
			 the user a "do not show again" control that did nothing. */
			if suppressKey != nil {
				alert.showsSuppressionButton = true
				alert.suppressionButton?.title = suppressText ?? ""
			}

			if let accessoryView {
				alert.accessoryView = accessoryView
			}

			context.suppressionKey = suppressKey

			alert.beginSheetModal(for: window) { returnCode in
				alertSheetResponseCallback(alert, returnCode: returnCode, contextInfo: context)
			}
		}
	}
}

// MARK: - Utilities

extension TDCAlert {
	/// Whether the user has previously chosen "do not show again" for an alert
	/// whose `suppressionKey:` argument was `baseKey`.
	public static func isSuppressed(baseKey: String) -> Bool {
		isSuppressed(fullKey: suppressionKey(withBase: baseKey))
	}

	static func isSuppressed(fullKey: String) -> Bool {
		UserDefaults.standard.bool(forKey: fullKey)
	}

	@objc(suppressionKeyWithBase:)
	public static func suppressionKey(withBase base: String) -> String {
		if base.hasPrefix(suppressionPrefix) {
			return base
		}

		return suppressionPrefix + base
	}

	@MainActor
	private static func alertSheetResponseCallback(
		_ alert: NSAlert,
		returnCode: NSApplication.ModalResponse,
		contextInfo context: AlertContext
	) {
		finalizeAlert(
			alert,
			with: convertResponse(from: returnCode),
			completionBlock: context.completionBlock,
			suppressionKey: context.suppressionKey
		)
	}

	@MainActor
	private static func finalizeAlert(
		_ underlyingAlert: NSAlert?,
		with response: TDCAlertResponse,
		completionBlock: TDCAlertCompletionBlock?,
		suppressionKey: String?
	) {
		let suppressed = recordSuppression(
			for: underlyingAlert?.suppressionButton,
			withKey: suppressionKey
		)

		completionBlock?(response, suppressed, underlyingAlert)
	}

	@MainActor
	private static func recordSuppression(for suppressionButton: NSButton?, withKey suppressionKey: String?) -> Bool {
		if suppressionButton == nil, suppressionKey == nil {
			return false
		}

		let suppressed = suppressionButton?.state == .on

		if suppressed, let suppressionKey {
			UserDefaults.standard.set(true, forKey: suppressionKey)
		}

		return suppressed
	}

	private static func convertResponse(from response: NSApplication.ModalResponse) -> TDCAlertResponse {
		switch response {
		case .alertSecondButtonReturn:
			.alternate
		case .alertThirdButtonReturn:
			.other
		default:
			.default
		}
	}
}
