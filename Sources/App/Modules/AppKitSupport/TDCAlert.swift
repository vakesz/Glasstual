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

@objc public enum TDCAlertResponse: UInt {
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
	public class func modalAlert(
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
	public class func modalAlert(
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
	public class func modalAlert(
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
	public class func modalAlert(
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
	public class func modalAlert(
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
	public class func modalAlert(
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
	public class func modalAlert(
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

			XRPerformBlockSynchronouslyOnMainQueue {
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

		var suppressKey = suppressKey
		var suppressText = suppressText

		if let key = suppressKey {
			suppressKey = suppressionKey(withBase: key)

			if UserDefaults.standard.bool(forKey: suppressKey!) {
				return .default
			}
		}

		if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
			suppressText = LocalizedKey("Prompts[68u-z9]")
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

		if suppressKey != nil || suppressText != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = suppressText ?? ""
		}

		if let accessoryView {
			alert.accessoryView = accessoryView
		}

		let returnCode = alert.runModal()
		let response = convertResponse(from: returnCode)

		finalizeAlert(
			alert,
			with: response,
			completionBlock: nil,
			suppressionKey: suppressKey,
			suppressionResponse: suppressionResponse
		)

		return response
	}

	// MARK: - Non-blocking Alerts (Panel)

	@objc(alertWithMessage:title:defaultButton:alternateButton:)
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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
	public class func alert(
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

			XRPerformBlockSynchronouslyOnMainQueue {
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

		var suppressKey = suppressKey
		var suppressText = suppressText

		if let key = suppressKey {
			suppressKey = suppressionKey(withBase: key)

			if UserDefaults.standard.bool(forKey: suppressKey!) {
				completionBlock?(.default, true, nil)
				return nil
			}
		}

		if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
			suppressText = LocalizedKey("Prompts[68u-z9]")
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

		if suppressKey != nil || suppressText != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = suppressText ?? ""
		}

		if let accessoryView {
			alert.accessoryView = accessoryView
		}

		let context = AlertContext()
		context.suppressionKey = suppressKey
		context.completionBlock = completionBlock

		/* A sheet on the main window is preferred so that the alert is
		 attached to what it is about. When the main window is hidden, any other
		 visible window hosts the sheet instead. */
		let masterController = NSObject.masterController()
		var hostWindow: NSWindow? = MainActor.assumeIsolated {
			masterController.mainWindow
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
			XRPerformBlockAsynchronouslyOnMainQueue {
				alertSheetResponseCallback(alert, returnCode: alert.runModal(), contextInfo: context)
			}
		}

		return alert
	}

	// MARK: - Non-blocking Alerts (Sheet)

	@objc(alertSheetWithWindow:body:title:defaultButton:alternateButton:otherButton:)
	public class func alertSheet(
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
	public class func alertSheet(
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
	public class func alertSheet(
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
	public class func alertSheet(
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
	public class func alertSheet(
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
			XRPerformBlockSynchronouslyOnMainQueue {
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

		var suppressKey = suppressKey
		var suppressText = suppressText

		if let key = suppressKey {
			suppressKey = suppressionKey(withBase: key)

			if UserDefaults.standard.bool(forKey: suppressKey!) {
				completionBlock?(.default, true, nil)
				return
			}
		}

		if suppressKey != nil, suppressText == nil || suppressText?.isEmpty == true {
			suppressText = LocalizedKey("Prompts[68u-z9]")
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

		if suppressKey != nil || suppressText != nil {
			alert.showsSuppressionButton = true
			alert.suppressionButton?.title = suppressText ?? ""
		}

		if let accessoryView {
			alert.accessoryView = accessoryView
		}

		let context = AlertContext()
		context.suppressionKey = suppressKey
		context.completionBlock = completionBlock

		alert.beginSheetModal(for: window) { returnCode in
			alertSheetResponseCallback(alert, returnCode: returnCode, contextInfo: context)
		}
	}

	// MARK: - Utilities

	@objc(suppressionKeyWithBase:)
	public class func suppressionKey(withBase base: String) -> String {
		if base.hasPrefix(suppressionPrefix) {
			return base
		}

		return suppressionPrefix + base
	}

	private class func alertSheetResponseCallback(
		_ alert: NSAlert,
		returnCode: NSApplication.ModalResponse,
		contextInfo context: AlertContext
	) {
		finalizeAlert(
			alert,
			with: convertResponse(from: returnCode),
			completionBlock: context.completionBlock,
			suppressionKey: context.suppressionKey,
			suppressionResponse: nil
		)
	}

	private class func finalizeAlert(
		_ underlyingAlert: NSAlert?,
		with response: TDCAlertResponse,
		completionBlock: TDCAlertCompletionBlock?,
		suppressionKey: String?,
		suppressionResponse: UnsafeMutablePointer<ObjCBool>?
	) {
		let suppressed = recordSuppression(
			for: underlyingAlert?.suppressionButton,
			withKey: suppressionKey
		)

		if let suppressionResponse {
			suppressionResponse.pointee = ObjCBool(suppressed)
		}

		completionBlock?(response, suppressed, underlyingAlert)
	}

	private class func recordSuppression(for suppressionButton: NSButton?, withKey suppressionKey: String?) -> Bool {
		if suppressionButton == nil, suppressionKey == nil {
			return false
		}

		let suppressed = suppressionButton?.state == .on

		if suppressed, let suppressionKey {
			UserDefaults.standard.set(true, forKey: suppressionKey)
		}

		return suppressed
	}

	private class func convertResponse(from response: NSApplication.ModalResponse) -> TDCAlertResponse {
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
