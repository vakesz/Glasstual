/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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
	/** Argument names bound by `callAsyncJavaScript`. */
	static func argumentName(at index: Int) -> String {
		"a\(index)"
	}

	/** A dotted path of JavaScript identifiers. Call sites are compile-time
	 constants, but the body is still a script, so the shape is checked rather
	 than assumed. */
	static func isValidFunctionPath(_ function: String) -> Bool {
		let segments = function.split(separator: ".", omittingEmptySubsequences: false)
		guard segments.isEmpty == false else {
			return false
		}
		return segments.allSatisfy { segment in
			guard let first = segment.first else {
				return false
			}
			guard first.isLetter || first == "_" || first == "$" else {
				return false
			}
			return segment.allSatisfy { $0.isLetter || $0.isNumber || $0 == "_" || $0 == "$" }
		}
	}

	/** The body `callAsyncJavaScript` runs for a call to `function`. Argument
	 values never appear in it. */
	static func functionBody(_ function: String, argumentCount: Int) -> String? {
		guard isValidFunctionPath(function), argumentCount >= 0 else {
			return nil
		}
		let names = (0 ..< argumentCount).map(argumentName(at:))
		return "return \(function)(\(names.joined(separator: ",")));"
	}

	/** Reduces a bridged argument to the types `callAsyncJavaScript` converts.
	 Anything else becomes `null` rather than being passed through, because an
	 unsupported value makes the whole call throw. */
	static func sanitize(_ value: Any) -> Any {
		switch value {
		case let url as URL:
			url.absoluteString
		case let string as String:
			string
		case let number as NSNumber:
			number
		case let array as [Any]:
			array.map(sanitize)
		case let dictionary as [AnyHashable: Any]:
			sanitize(dictionary)
		default:
			NSNull()
		}
	}

	static func sanitize(_ dictionary: [AnyHashable: Any]) -> [String: Any] {
		var result: [String: Any] = [:]
		for (key, value) in dictionary {
			guard let key = key as? String else {
				logViewLogger
					.debug(
						"Ignoring non-string JavaScript dictionary key: \(String(describing: type(of: key)), privacy: .public)"
					)
				continue
			}
			result[key] = sanitize(value)
		}
		return result
	}

	/** Binds `arguments` to the names `functionBody` generates. */
	static func namedArguments(_ arguments: [Any]?) -> [String: Any] {
		var result: [String: Any] = [:]
		for (index, value) in (arguments ?? []).enumerated() {
			result[argumentName(at: index)] = sanitize(value)
		}
		return result
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

	/** Fixed for the lifetime of the view, so reloads replace this view's
	 document instead of adding another one. */
	private let documentIdentifier = UUID().uuidString
	private var loadedDocumentURL: URL?

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

	deinit {
		guard let loadedDocumentURL else {
			return
		}
		Task { @MainActor in
			LogViewThemeSchemeHandler.shared.unregisterDocument(at: loadedDocumentURL)
		}
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
		if AppController.shared.mainWindow.reloadingTheme() {
			return
		}
		if ApplicationInfo.timeIntervalSinceApplicationLaunch() < 120 {
			return
		}
		SharedApplication.sharedThemeController().recreateTemporaryCopyOfThemeIfNecessary()
	}

	/** The document is served from memory by `LogViewThemeSchemeHandler` under
	 a URL inside `baseURL`, so relative references still resolve against the
	 theme while nothing is written to disk. */
	@objc public func loadHTMLString(_ string: String, baseURL: URL) {
		isLayingOutView = true
		recreateTemporaryCopyOfThemeIfNecessary()

		let handler = LogViewThemeSchemeHandler.shared
		handler.removeStaleRenderedDocuments(in: baseURL)

		guard let documentURL = handler.documentURL(forViewIdentifier: documentIdentifier, in: baseURL) else {
			logViewLogger.error("Failed to derive a document URL inside the theme directory")
			return
		}

		if let loadedDocumentURL, loadedDocumentURL != documentURL {
			handler.unregisterDocument(at: loadedDocumentURL)
		}
		loadedDocumentURL = documentURL
		handler.registerDocument(string, at: documentURL)

		backingView.load(URLRequest(url: documentURL))
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

	/** Calls `function` in the page with `arguments` bound by name. WebKit
	 converts the values, so nothing is escaped into a script by hand. */
	public func evaluate<T>(_ function: String, arguments: [Any]? = nil) async throws -> T? {
		guard let body = LogViewJavaScript.functionBody(function, argumentCount: arguments?.count ?? 0) else {
			logViewLogger.error("Refused an unusable JavaScript function name: \(function, privacy: .public)")
			return nil
		}
		let result = try await backingView.call(body, arguments: LogViewJavaScript.namedArguments(arguments))
		return result as? T
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
		Task { @MainActor [weak self] in
			guard let self else {
				return
			}
			let result: Any? = try? await evaluate(function, arguments: arguments)
			completionHandler?(result)
		}
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
}
