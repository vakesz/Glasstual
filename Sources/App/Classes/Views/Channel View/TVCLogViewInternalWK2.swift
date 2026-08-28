/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
import ObjectiveC
import os
import WebKit

private let logViewWebKitLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogViewWebKit"
)

@MainActor
private enum WebKitStyleResourceAccess {
	private typealias BooleanSetter = @convention(c) (AnyObject, Selector, Bool) -> Void

	static func allowFileResources(in configuration: WKWebViewConfiguration) {
		invoke(
			selector: NSSelectorFromString("_setAllowUniversalAccessFromFileURLs:"),
			on: configuration
		)
		invoke(
			selector: NSSelectorFromString("_setAllowFileAccessFromFileURLs:"),
			on: configuration.preferences
		)
	}

	private static func invoke(selector: Selector, on object: AnyObject) {
		guard let method = class_getInstanceMethod(type(of: object), selector) else {
			preconditionFailure("Required WebKit style-resource selector is unavailable: \(selector)")
		}

		let setter = unsafeBitCast(method_getImplementation(method), to: BooleanSetter.self)
		setter(object, selector, true)
	}
}

@objc(TVCLogViewInternalWK2)
@MainActor
final class LogViewWebView: WKWebView, WKNavigationDelegate, WKUIDelegate {
	@MainActor
	private enum SharedResources {
		static let messageHandlerNames = [
			"appearance",
			"channelIsActive",
			"channelMemberCount",
			"channelName",
			"channelNameDoubleClicked",
			"displayContextMenu",
			"copySelectionWhenPermitted",
			"encryptionAuthenticateUser",
			"inlineMediaEnabledForView",
			"loadInlineMedia",
			"localUserHostmask",
			"localUserNickname",
			"logToConsole",
			"networkName",
			"nicknameColorStyleHash",
			"nicknameDoubleClicked",
			"notifyLinesAddedToView",
			"notifyLinesRemovedFromView",
			"notifyJumpToLineCallback",
			"printDebugInformation",
			"printDebugInformationToConsole",
			"renderMessagesBefore",
			"renderMessagesAfter",
			"renderMessagesInRange",
			"renderMessageWithSiblings",
			"renderTemplate",
			"retrievePreferencesWithMethodName",
			"sendPluginPayload",
			"serverAddress",
			"serverChannelCount",
			"serverIsConnected",
			"setChannelName",
			"setNickname",
			"setLineContext",
			"setSelection",
			"setURLAddress",
			"sidebarInversionIsEnabled",
			"styleSettingsRetrieveValue",
			"styleSettingsSetValue",
			"topicBarDoubleClicked",
			"finishedLayingOutView",
		]

		static let scriptSink = TVCLogScriptEventSink(webView: nil)
		static let policy = LogPolicy()
		static let configuration: WKWebViewConfiguration = {
			let configuration = WKWebViewConfiguration()

			/* Styles load from file URLs and reference scripts, images, and
			 their own resources through other file URLs. WebKit treats every
			 file URL as a separate origin. These private flags remain isolated
			 here until the theme loader adopts a custom URL scheme handler. */
			WebKitStyleResourceAccess.allowFileResources(in: configuration)

			let contentController = WKUserContentController()
			for name in messageHandlerNames {
				contentController.add(scriptSink, name: name)
			}
			configuration.userContentController = contentController
			return configuration
		}()
	}

	@objc(t_parentView) weak var parentView: LogView?
	@objc(t_viewIsLoading) var viewIsLoading = false
	@objc(t_viewIsNavigating) var viewIsNavigating = false

	private var loadingObservation: NSKeyValueObservation?

	init() {
		super.init(frame: .zero, configuration: SharedResources.configuration)
	}

	@available(*, unavailable)
	required init?(coder _: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	@objc(initWithHostView:)
	convenience init(hostView: LogView) {
		self.init()
		attach(to: hostView)
	}

	func attach(to hostView: LogView) {
		parentView = hostView
		allowsBackForwardNavigationGestures = false
		allowsMagnification = false
		translatesAutoresizingMaskIntoConstraints = false
		allowsLinkPreview = TextualPreferences.webKit2PreviewLinks()
		underPageBackgroundColor = .clear
		customUserAgent = LogView.commonUserAgent
		/* The log view holds a native bridge and runs third-party theme
		 JavaScript; the inspector is a development tool, not a shipped one. */
		#if DEBUG
			isInspectable = true
		#endif
		navigationDelegate = self
		uiDelegate = self
	}

	deinit {
		loadingObservation?.invalidate()
	}

	@objc var webViewPolicy: LogPolicy {
		SharedResources.policy
	}

	override func loadFileURL(_ URL: URL, allowingReadAccessTo readAccessURL: URL) -> WKNavigation? {
		startObservingLoading()
		return super.loadFileURL(URL, allowingReadAccessTo: readAccessURL)
	}

	override func loadHTMLString(_ string: String, baseURL: URL?) -> WKNavigation? {
		startObservingLoading()
		return super.loadHTMLString(string, baseURL: baseURL)
	}

	override func stopLoading() {
		stopObservingLoading()
		super.stopLoading()
	}

	override func keyDown(with event: NSEvent) {
		if parentView?.keyDown(event, in: self) == true {
			return
		}
		super.keyDown(with: event)
	}

	override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
		parentView?.performDragOperation(sender) ?? false
	}

	@objc static func emptyCaches() {
		let types: Set<String> = [WKWebsiteDataTypeDiskCache, WKWebsiteDataTypeMemoryCache]
		SharedResources.configuration.websiteDataStore.removeData(
			ofTypes: types,
			modifiedSince: .distantPast
		) {
			logViewWebKitLogger.debug("WebKit cache cleared")
		}
	}

	@objc(findString:movingForward:)
	func find(_ searchString: String, movingForward: Bool) {
		let configuration = WKFindConfiguration()
		configuration.backwards = movingForward == false
		configuration.caseSensitive = false
		configuration.wraps = true
		find(searchString, configuration: configuration) { result in
			if result.matchFound == false {
				NSSound.beep()
			}
		}
	}

	private func startObservingLoading() {
		guard loadingObservation == nil else {
			return
		}

		/* No .initial: the observation is installed before the load starts, so
		 the initial callback reports isLoading == false and would declare the
		 view finished against a blank page. */
		loadingObservation = observe(\.isLoading, options: [.new]) { [weak self] _, change in
			MainActor.assumeIsolated {
				guard let self else {
					return
				}
				self.viewIsLoading = change.newValue ?? self.isLoading
				self.maybeInformDelegateWebViewFinishedLoading()
			}
		}
	}

	private func stopObservingLoading() {
		loadingObservation?.invalidate()
		loadingObservation = nil
	}

	private func maybeInformDelegateWebViewFinishedLoading() {
		guard viewIsLoading == false, viewIsNavigating == false else {
			return
		}
		stopObservingLoading()
		parentView?.perform(
			#selector(LogView.informDelegateWebViewFinishedLoading),
			with: nil,
			afterDelay: 1.2,
			inModes: [.common]
		)
	}

	@objc var maintainsInactiveSelection: Bool {
		true
	}

	@objc(_t_evaluateJavaScript:completionHandler:)
	func evaluate(_ code: String, completionHandler: ((Any?) -> Void)?) {
		evaluateJavaScript(code) { [weak self] result, error in
			if let error {
				self?.logJavaScriptError(error)
			}
			completionHandler?(result is NSNull ? nil : result)
		}
	}

	private func logJavaScriptError(_ error: Error) {
		let nsError = error as NSError
		let lineNumber = nsError.userInfo["WKJavaScriptExceptionLineNumber"] as? NSNumber
		let errorMessage = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String
		let sourceURL = nsError.userInfo["WKJavaScriptExceptionSourceURL"] as? URL
		let channelName = parentView?.viewController?.associatedChannel?.name ?? "Server Console"

		guard let lineNumber, let errorMessage, let sourceURL else {
			logViewWebKitLogger.error(
				"JavaScript error in \(channelName, privacy: .private): \(error.localizedDescription, privacy: .public)"
			)
			return
		}

		let sourcePath = sourceURL.standardizedFileURL.path(percentEncoded: false)
		let errorDescription = "JavaScript error in \(channelName) on line \(lineNumber.uintValue) of \(sourcePath): \(errorMessage)"
		logViewWebKitLogger.error("\(errorDescription, privacy: .public)")
	}

	func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
		precondition(webView === self)
		let viewDescription = description
		logViewWebKitLogger.error("WebView content process terminated. Reloading \(viewDescription, privacy: .public)")
		viewIsLoading = false
		viewIsNavigating = false
		stopObservingLoading()
		parentView?.informDelegateWebViewClosedUnexpectedly()
	}

	func webView(
		_ webView: WKWebView,
		decidePolicyFor navigationAction: WKNavigationAction,
		decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void
	) {
		precondition(webView === self)
		guard let parentView else {
			decisionHandler(.cancel)
			return
		}

		SharedResources.policy.webView2(
			webView,
			logView: parentView,
			decidePolicyFor: navigationAction,
			decisionHandler: decisionHandler
		)
	}

	func webView(
		_ webView: WKWebView,
		didReceive challenge: URLAuthenticationChallenge,
		completionHandler: @escaping @MainActor (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
	) {
		precondition(webView === self)
		guard let parentView else {
			completionHandler(.performDefaultHandling, nil)
			return
		}

		SharedResources.policy.webView2(
			webView,
			logView: parentView,
			didReceive: challenge,
			completionHandler: completionHandler
		)
	}

	func webView(_ webView: WKWebView, didStartProvisionalNavigation _: WKNavigation!) {
		precondition(webView === self)
		viewIsNavigating = true
	}

	func webView(_ webView: WKWebView, didFinish _: WKNavigation!) {
		precondition(webView === self)
		viewIsNavigating = false
		maybeInformDelegateWebViewFinishedLoading()
	}

	/** WKWebView has no public hook that replaces the context menu while
	 retaining WebKit's Inspect Element, Look Up, and Search items. If
	 WebKit stops invoking this private delegate method, its default menu
	 remains available. */
	@objc(_webView:contextMenu:forElement:)
	func webView(_ webView: WKWebView, contextMenu menu: NSMenu, forElement _: Any) -> NSMenu {
		precondition(webView === self)
		guard let parentView else {
			return menu
		}

		return SharedResources.policy.webView2(
			webView,
			logView: parentView,
			contextMenuWithDefaultMenu: menu
		)
	}
}
