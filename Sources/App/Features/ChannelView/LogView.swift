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

	/** Binds `arguments` to the names `functionBody` generates, each one
	 reduced to a value the bridge converts. */
	static func namedArguments(_ arguments: [Any]?) -> [String: JavaScriptValue] {
		var result: [String: JavaScriptValue] = [:]
		for (index, value) in (arguments ?? []).enumerated() {
			result[argumentName(at: index)] = JavaScriptValue(bridging: value)
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

@MainActor
public final class LogView: NSObject {
	static let commonUserAgent = "Glasstual/1.0"

	public weak var viewController: LogController?
	public var contextMenuTarget = LogPolicyTarget()
	public var selection: String?
	/** Observed with `publisher(for:)` by the channel view's loading overlay,
	 which is key-value observation: the property has to stay visible to the
	 Objective-C runtime and dynamically dispatched or the key path resolves
	 to nothing. */
	@objc public private(set) dynamic var isLayingOutView = false

	private let backingView: LogViewWebView

	/** Fixed for the lifetime of the view, so reloads replace this view's
	 document instead of adding another one. */
	private let documentIdentifier = UUID().uuidString
	private var loadedDocumentURL: URL?
	private var finishedLoadingTask: Task<Void, Never>?

	@available(*, unavailable, message: "Use init(viewController:)")
	override public init() {
		fatalError("Use init(viewController:)")
	}

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

	public var hasSelection: Bool {
		selection?.isEmpty == false
	}

	public func clearSelection() {
		evaluateFunction("Glasstual.clearSelection")
	}

	public var webView: NSView {
		backingView
	}

	public var webViewPolicy: LogPolicy {
		backingView.webViewPolicy
	}

	public func takeContextMenuTarget() -> LogPolicyTarget {
		defer { contextMenuTarget = LogPolicyTarget() }
		return contextMenuTarget
	}

	public func copyContentString() {
		stringByEvaluatingFunction("Glasstual.documentHTML") { result in
			guard let result else {
				return
			}
			NSPasteboard.general.clearContents()
			NSPasteboard.general.setString(result, forType: .string)
		}
	}

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

	public func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
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

	public func informDelegateWebViewFinishedLoading() {
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

	public func informDelegateWebViewClosedUnexpectedly() {
		viewController?.logViewWebViewClosedUnexpectedly()
	}

	public func setViewFinishedLayout() {
		isLayingOutView = false
	}

	public static func emptyCaches() {
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
	public func loadHTMLString(_ string: String, baseURL: URL) {
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

	public func stopLoading() {
		finishedLoadingTask?.cancel()
		finishedLoadingTask = nil
		backingView.stopLoading()
	}

	/** The delegate is told a beat after the last navigation settles, so that a
	 redirect chain reports once. Cancelling the task is what `stopLoading()`
	 needs; a pending `perform(_:afterDelay:)` used to carry the same meaning. */
	func informDelegateWebViewFinishedLoading(after delay: Duration) {
		finishedLoadingTask?.cancel()
		finishedLoadingTask = Task { [weak self] in
			try? await Task.sleep(for: delay)

			guard Task.isCancelled == false, let self else { return }

			finishedLoadingTask = nil
			informDelegateWebViewFinishedLoading()
		}
	}

	public func findString(_ searchString: String, movingForward: Bool) {
		backingView.find(searchString, movingForward: movingForward)
	}

	public func evaluateJavaScript(_ code: String) {
		evaluateJavaScript(code, completionHandler: nil)
	}

	public func evaluateJavaScript(_ code: String, completionHandler: ((Any?) -> Void)?) {
		DispatchQueue.main.async { [weak self] in
			self?.backingView.evaluate(code, completionHandler: completionHandler)
		}
	}

	public static func descriptionOfJavaScriptResult(_ result: Any) -> String {
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

	public func evaluateFunction(_ function: String) {
		evaluateFunction(function, withArguments: nil, completionHandler: nil)
	}

	public func evaluateFunction(_ function: String, withArguments arguments: [Any]?) {
		evaluateFunction(function, withArguments: arguments, completionHandler: nil)
	}

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

	public func booleanByEvaluatingFunction(_ function: String, completionHandler: ((Bool) -> Void)?) {
		booleanByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	public func booleanByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: ((Bool) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?((result as? NSNumber)?.boolValue ?? false)
		}
	}

	public func stringByEvaluatingFunction(_ function: String, completionHandler: ((String?) -> Void)?) {
		stringByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	public func stringByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: ((String?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?(result as? String)
		}
	}

	public func arrayByEvaluatingFunction(_ function: String, completionHandler: (([Any]?) -> Void)?) {
		arrayByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	public func arrayByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: (([Any]?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?(result as? [Any])
		}
	}

	public func dictionaryByEvaluatingFunction(
		_ function: String,
		completionHandler: (([String: JavaScriptValue]?) -> Void)?
	) {
		dictionaryByEvaluatingFunction(function, withArguments: nil, completionHandler: completionHandler)
	}

	public func dictionaryByEvaluatingFunction(
		_ function: String,
		withArguments arguments: [Any]?,
		completionHandler: (([String: JavaScriptValue]?) -> Void)?
	) {
		evaluateFunction(function, withArguments: arguments) { result in
			completionHandler?((result as? [AnyHashable: Any]).map(JavaScriptValue.object(bridging:)))
		}
	}

	public func logToJavaScriptConsole(_ message: String) {
		evaluateFunction("console.log", withArguments: [message])
	}
}
