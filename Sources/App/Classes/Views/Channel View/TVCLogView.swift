/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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
import Foundation
import os
import WebKit

private let logViewLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogView"
)

enum LogViewJavaScript {
	static func escape(_ string: String) -> String {
		string
			.replacingOccurrences(of: "\\", with: "\\\\")
			.replacingOccurrences(of: "\"", with: "\\\"")
			.replacingOccurrences(of: "\r", with: "\\r")
			.replacingOccurrences(of: "\n", with: "\\n")
	}

	static func describe(_ result: Any) -> String {
		switch result {
		case let string as String:
			return string
		case let array as NSArray:
			return array.description
		case let dictionary as NSDictionary:
			return dictionary.description
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return number.boolValue ? "true" : "false"
			}
			return number.stringValue
		case is NSNull:
			return "null"
		default:
			return "undefined"
		}
	}

	static func compile(_ value: Any) -> String {
		if let url = value as? URL {
			return "\"\(escape(url.absoluteString))\""
		}

		switch value {
		case let string as String:
			return "\"\(escape(string))\""
		case let number as NSNumber:
			if CFGetTypeID(number) == CFBooleanGetTypeID() {
				return number.boolValue ? "true" : "false"
			}
			return number.stringValue
		case let array as [Any]:
			return "[\(array.map(compile).joined(separator: ","))]"
		case let dictionary as [AnyHashable: Any]:
			let entries = dictionary.compactMap { key, value -> String? in
				guard let key = key as? String else {
					logViewLogger
						.debug(
							"Ignoring non-string JavaScript dictionary key: \(String(describing: type(of: key)), privacy: .public)"
						)
					return nil
				}
				return "\"\(escape(key))\":\(compile(value))"
			}
			return "{\(entries.joined(separator: ", "))}"
		case is NSNull:
			return "null"
		default:
			return "undefined"
		}
	}

	static func functionCall(_ function: String, arguments: [Any]?) -> String {
		let compiledArguments = arguments?.map(compile).joined(separator: ",") ?? ""
		return "\(function)(\(compiledArguments));\n"
	}
}

@objc(TVCLogView)
@MainActor
public final class LogView: NSObject {
	static let commonUserAgent = "Glasstual/1.0"

	@objc public weak var viewController: LogController?
	@objc public var contextMenuTarget = LogPolicyTarget()
	@objc public var selection: String?
	@objc public private(set) dynamic var isLayingOutView = false

	private let backingView: LogViewWebView

	@available(*, unavailable, message: "Use init(viewController:)")
	override public init() {
		fatalError("Use init(viewController:)")
	}

	@objc(initWithViewController:)
	public init(viewController: LogController) {
		self.viewController = viewController
		backingView = LogViewWebView()
		super.init()
		backingView.attach(to: self)
	}

	@objc public var hasSelection: Bool {
		selection?.isEmpty == false
	}

	@objc public func clearSelection() {
		evaluateFunction("Glasstual.clearSelection")
	}

	@objc public var webView: NSView {
		backingView
	}

	@objc public var webViewPolicy: LogPolicy {
		backingView.webViewPolicy
	}

	@objc public func takeContextMenuTarget() -> LogPolicyTarget {
		defer { contextMenuTarget = LogPolicyTarget() }
		return contextMenuTarget
	}

	@objc public func copyContentString() {
		stringByEvaluatingFunction("Glasstual.documentHTML") { result in
			guard let result else {
				return
			}
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(result, forType: .string)
		}
	}

	@objc(print)
	public func printContent() {
		guard let window = backingView.window else {
			return
		}

		let printInfo = NSPrintInfo.shared
		let operation = backingView.printOperation(with: printInfo)
		operation.view?.frame = NSRect(origin: .zero, size: printInfo.paperSize)
		operation.showsPrintPanel = true
		operation.showsProgressPanel = true
		operation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
	}

	@objc(keyDown:inView:)
	public func keyDown(_ event: NSEvent, in _: NSView) -> Bool {
		guard let viewController else {
			return false
		}

		let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
		if modifiers.isDisjoint(with: [.command, .option, .control]) {
			viewController.logViewWebViewKeyDown(event)
			return true
		}
		return false
	}

	@objc public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		guard
			let viewController,
			let fileURL = NSURL(from: sender.draggingPasteboard) as URL?,
			fileURL.isFileURL
		else {
			return false
		}
		viewController.logViewWebViewReceivedDrop(withFile: fileURL.path)
		return true
	}

	@objc public func informDelegateWebViewFinishedLoading() {
		guard let viewController else {
			return
		}

		let viewDescription = description
		logViewLogger.debug("View finished loading: \(viewDescription, privacy: .public)")
		evaluateJavaScript(
			"if (_Glasstual._viewBodyDidLoadAnimationFrame) { " +
				"window.cancelAnimationFrame(_Glasstual._viewBodyDidLoadAnimationFrame); " +
				"_Glasstual._viewBodyDidLoad(); }"
		)
		setViewFinishedLayout()
		viewController.logViewWebViewFinishedLoading()
	}

	@objc public func informDelegateWebViewClosedUnexpectedly() {
		viewController?.logViewWebViewClosedUnexpectedly()
	}

	@objc public func setViewFinishedLayout() {
		isLayingOutView = false
	}

	@objc public static func emptyCaches() {
		LogViewWebView.emptyCaches()
	}

	private func recreateTemporaryCopyOfThemeIfNecessary() {
		if NSObject.applicationController().mainWindow.reloadingTheme() {
			return
		}
		if ApplicationInfo.timeIntervalSinceApplicationLaunch() < 120 {
			return
		}
		SharedApplication.sharedThemeController().recreateTemporaryCopyOfThemeIfNecessary()
	}

	@objc public func loadHTMLString(_ string: String, baseURL: URL) {
		isLayingOutView = true
		recreateTemporaryCopyOfThemeIfNecessary()

		let filename = "\(UUID().uuidString).html"
		let fileURL = baseURL.appendingPathComponent(filename)
		do {
			try string.write(to: fileURL, atomically: false, encoding: .utf8)
		} catch {
			logViewLogger.error("Failed to write temporary file: \(error.localizedDescription, privacy: .public)")
			return
		}
		_ = backingView.loadFileURL(
			fileURL,
			allowingReadAccessTo: SharedApplication.sharedThemeController().temporaryURL
		)
	}

	@objc public func stopLoading() {
		NSObject.cancelPreviousPerformRequests(
			withTarget: self,
			selector: #selector(informDelegateWebViewFinishedLoading),
			object: nil
		)
		backingView.stopLoading()
	}

	@objc(findString:movingForward:)
	public func findString(_ searchString: String, movingForward: Bool) {
		backingView.find(searchString, movingForward: movingForward)
	}

	@objc public func evaluateJavaScript(_ code: String) {
		evaluateJavaScript(code, completionHandler: nil)
	}

	@objc(evaluateJavaScript:completionHandler:)
	public func evaluateJavaScript(_ code: String, completionHandler: ((Any?) -> Void)?) {
		DispatchQueue.main.async { [weak self] in
			self?.backingView.evaluate(code, completionHandler: completionHandler)
		}
	}

	@objc public static func descriptionOfJavaScriptResult(_ result: Any) -> String {
		LogViewJavaScript.describe(result)
	}

	@objc public static func escapeJavaScriptString(_ string: String) -> String {
		LogViewJavaScript.escape(string)
	}

	@objc public func evaluateFunction(_ function: String) {
		evaluateFunction(function, withArguments: nil, completionHandler: nil)
	}

	@objc(evaluateFunction:withArguments:)
	public func evaluateFunction(_ function: String, withArguments arguments: [Any]?) {
		evaluateFunction(function, withArguments: arguments, completionHandler: nil)
	}

	@objc(evaluateFunction:withArguments:completionHandler:)
	public func evaluateFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: ((Any?) -> Void)?
	) {
		evaluateJavaScript(
			LogViewJavaScript.functionCall(function, arguments: arguments),
			completionHandler: completionHandler
		)
	}

	@objc(booleanByEvaluatingFunction:completionHandler:)
	public func booleanByEvaluatingFunction(_ function: String, completionHandler: ((Bool) -> Void)?) {
		booleanByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	@objc(booleanByEvaluatingFunction:withArguments:completionHandler:)
	public func booleanByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: ((Bool) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?((result as? NSNumber)?.boolValue ?? false)
		}
	}

	@objc(stringByEvaluatingFunction:completionHandler:)
	public func stringByEvaluatingFunction(_ function: String, completionHandler: ((String?) -> Void)?) {
		stringByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	@objc(stringByEvaluatingFunction:withArguments:completionHandler:)
	public func stringByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: ((String?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?(result as? String)
		}
	}

	@objc(arrayByEvaluatingFunction:completionHandler:)
	public func arrayByEvaluatingFunction(_ function: String, completionHandler: (([Any]?) -> Void)?) {
		arrayByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	@objc(arrayByEvaluatingFunction:withArguments:completionHandler:)
	public func arrayByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: (([Any]?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?(result as? [Any])
		}
	}

	@objc(dictionaryByEvaluatingFunction:completionHandler:)
	public func dictionaryByEvaluatingFunction(
		_ function: String,
		completionHandler: (([String: Any]?) -> Void)?
	) {
		dictionaryByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	@objc(dictionaryByEvaluatingFunction:withArguments:completionHandler:)
	public func dictionaryByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: (([String: Any]?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?(result as? [String: Any])
		}
	}

	@objc(logToJavaScriptConsole:)
	public func logToJavaScriptConsole(_ message: String) {
		evaluateFunction("console.log", withArguments: [message])
	}

	@objc(compiledFunctionCall:withArguments:)
	public func compiledFunctionCall(_ function: String, withArguments arguments: [Any]?) -> String {
		LogViewJavaScript.functionCall(function, arguments: arguments)
	}
}
