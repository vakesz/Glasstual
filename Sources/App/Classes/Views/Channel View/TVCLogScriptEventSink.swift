/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
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
import GlasstualPluginKit
import ObjectiveC
import OSLog
import WebKit

private let scriptEventLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogScriptEventSink"
)

@MainActor
private final class LogScriptEventContext {
	let webView: LogView
	let viewController: LogController
	let caller: String
	let arguments: [Any]
	let completion: (Any?) -> Void

	init(
		webView: LogView,
		viewController: LogController,
		caller: String,
		arguments: [Any],
		completion: @escaping (Any?) -> Void
	) {
		self.webView = webView
		self.viewController = viewController
		self.caller = caller
		self.arguments = arguments
		self.completion = completion
	}

	var webViewPolicy: LogPolicy {
		webView.webViewPolicy
	}

	var associatedClient: IRCClient {
		viewController.associatedClient
	}

	var associatedChannel: IRCChannel? {
		viewController.associatedChannel
	}
}

@objc(TVCLogScriptEventSink)
@MainActor
final class TVCLogScriptEventSink: NSObject, WKScriptMessageHandler {
	private weak var webView: LogView?

	@objc(initWithWebView:)
	init(webView: LogView?) {
		self.webView = webView
		super.init()
	}

	override convenience init() {
		self.init(webView: nil)
	}

	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		let selector = NSSelectorFromString("\(message.name):inWebView:")
		guard responds(to: selector) else {
			return
		}
		perform(selector, with: message.body, with: message.webView)
	}

	static func objectValueToCommon(_ object: Any) -> Any? {
		switch object {
		case is NSNull:
			nil
		case let string as String:
			string.gtmStringByUnescapingFromHTML
		default:
			object
		}
	}

	static func standardizeLineNumber(_ lineNumber: String) -> String {
		lineNumber.hasPrefix("line-") ? String(lineNumber.dropFirst(5)) : lineNumber
	}

	static func standardizeLineNumbers(_ lineNumbers: [String]) -> [String] {
		lineNumbers.map(standardizeLineNumber)
	}

	private func processInputData(
		_ inputData: Any,
		caller: String,
		webView candidate: Any,
		minimumArgumentCount: Int = 0,
		validate: ((Int, Any) -> Bool)? = nil,
		handler: (LogScriptEventContext) -> Void
	) {
		let resolvedWebView: LogView?
		if let view = candidate as? LogView {
			resolvedWebView = view
		} else if let internalView = candidate as? LogViewWebView {
			resolvedWebView = internalView.parentView
		} else {
			return
		}

		guard let resolvedWebView else {
			scriptEventLogger.fault("Parent log view disappeared while processing \(caller, privacy: .public)")
			return
		}
		guard let viewController = resolvedWebView.viewController else {
			scriptEventLogger.fault("Log controller disappeared while processing \(caller, privacy: .public)")
			return
		}

		var promiseIndex = -1
		var values: [Any] = []

		if let dictionary = inputData as? [AnyHashable: Any] {
			if let indexObject = dictionary["promiseIndex"] {
				guard let index = indexObject as? NSNumber else {
					Self.throwJavaScriptException(
						"'promiseIndex' must be a number",
						caller: caller,
						in: resolvedWebView
					)
					return
				}
				promiseIndex = index.intValue
			}
			if minimumArgumentCount > 0 {
				guard let suppliedValues = dictionary["values"] as? [Any] else {
					Self.throwJavaScriptException("'values' must be an array", caller: caller, in: resolvedWebView)
					return
				}
				values = suppliedValues
			}
		} else if minimumArgumentCount > 0 {
			switch inputData {
			case let value as String:
				values = [value]
			case let value as NSNumber:
				values = [value]
			case let suppliedValues as [Any]:
				values = suppliedValues
			case is NSNull:
				values = [NSNull()]
			default:
				break
			}
		}

		guard values.count >= minimumArgumentCount else {
			Self.throwJavaScriptException(
				"Minimum number of arguments (%lu) condition not met",
				caller: caller,
				in: resolvedWebView,
				arguments: [minimumArgumentCount]
			)
			return
		}

		if let validate, values.enumerated().contains(where: { !validate($0.offset, $0.element) }) {
			Self.throwJavaScriptException("Invalid argument type(s)", caller: caller, in: resolvedWebView)
			return
		}

		let completion: (Any?) -> Void = if promiseIndex >= 0 {
			{ [weak resolvedWebView] returnValue in
				resolvedWebView?.evaluateFunction(
					"appInternal.promiseKept",
					withArguments: [promiseIndex, returnValue ?? NSNull()]
				)
			}
		} else {
			{ _ in }
		}

		handler(LogScriptEventContext(
			webView: resolvedWebView,
			viewController: viewController,
			caller: caller,
			arguments: values,
			completion: completion
		))
	}

	private static func throwJavaScriptException(
		_ message: String,
		caller: String? = nil,
		in webView: LogView,
		arguments: [CVarArg] = []
	) {
		var formatted = arguments.isEmpty ? message : String(format: message, arguments: arguments)
		if let caller {
			formatted = "Bridged function \(caller) returned error: \(formatted)"
		}
		webView.evaluateFunction("console.error", withArguments: [formatted])
	}

	private func dispatch(
		_ inputData: Any,
		_ webView: Any,
		caller: String,
		minimum: Int = 0,
		validate: ((Int, Any) -> Bool)? = nil,
		to handler: (LogScriptEventContext) -> Void
	) {
		processInputData(inputData, caller: caller, webView: webView, minimumArgumentCount: minimum,
		                 validate: validate, handler: handler)
	}

	@objc(channelIsActive:inWebView:)
	private func channelIsActive(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.channelIsActive()",
			to: handleChannelIsActive
		)
	}

	@objc(channelMemberCount:inWebView:)
	private func channelMemberCount(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.channelMemberCount()",
			to: handleChannelMemberCount
		)
	}

	@objc(channelName:inWebView:)
	private func channelName(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.channelName()",
			to: handleChannelName
		)
	}

	@objc(channelNameDoubleClicked:inWebView:)
	private func channelNameDoubleClicked(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.channelNameDoubleClicked()",
			to: handleChannelNameDoubleClicked
		)
	}

	@objc(displayContextMenu:inWebView:)
	private func displayContextMenu(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.displayContextMenu()",
			to: handleDisplayContextMenu
		)
	}

	@objc(copySelectionWhenPermitted:inWebView:)
	private func copySelectionWhenPermitted(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.copySelectionWhenPermitted()",
			to: handleCopySelectionWhenPermitted
		)
	}

	@objc(inlineMediaEnabledForView:inWebView:)
	private func inlineMediaEnabledForView(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.inlineMediaEnabledForView()",
			to: handleInlineMediaEnabledForView
		)
	}

	@objc(loadInlineMedia:inWebView:)
	private func loadInlineMedia(_ data: Any, inWebView view: Any) {
		dispatch(data, view, caller: "app.loadInlineMedia()", minimum: 4,
		         validate: { $0 <= 2 ? $1 is String : $1 is NSNumber }, to: handleLoadInlineMedia)
	}

	@objc(localUserHostmask:inWebView:)
	private func localUserHostmask(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.localUserHostmask()",
			to: handleLocalUserHostmask
		)
	}

	@objc(localUserNickname:inWebView:)
	private func localUserNickname(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.localUserNickname()",
			to: handleLocalUserNickname
		)
	}

	@objc(logToConsole:inWebView:)
	private func logToConsole(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.logToConsole()",
			minimum: 1,
			validate: { _, value in value is String },
			to: handleLogToConsole
		)
	}

	@objc(networkName:inWebView:)
	private func networkName(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.networkName()",
			to: handleNetworkName
		)
	}

	@objc(nicknameColorStyleHash:inWebView:)
	private func nicknameColorStyleHash(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.nicknameColorStyleHash()",
			minimum: 2,
			validate: { _, value in value is String },
			to: handleNicknameColorStyleHash
		)
	}

	@objc(nicknameDoubleClicked:inWebView:)
	private func nicknameDoubleClicked(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.nicknameDoubleClicked()",
			to: handleNicknameDoubleClicked
		)
	}

	@objc(notifyJumpToLineCallback:inWebView:)
	private func notifyJumpToLineCallback(_ data: Any, inWebView view: Any) {
		dispatch(data, view, caller: "app.notifyJumpToLineCallback()", minimum: 3,
		         validate: { $0 == 0 ? $1 is String : $1 is NSNumber }, to: handleNotifyJumpToLineCallback)
	}

	@objc(notifyLinesAddedToView:inWebView:)
	private func notifyLinesAddedToView(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.notifyLinesAddedToView()",
			minimum: 1,
			validate: { _, value in value is String || value is [Any] },
			to: handleNotifyLinesAddedToView
		)
	}

	@objc(notifyLinesRemovedFromView:inWebView:)
	private func notifyLinesRemovedFromView(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.notifyLinesRemovedFromView()",
			minimum: 1,
			validate: { _, value in value is String || value is [Any] },
			to: handleNotifyLinesRemovedFromView
		)
	}

	@objc(printDebugInformation:inWebView:)
	private func printDebugInformation(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.printDebugInformation()",
			minimum: 1,
			validate: { _, value in value is String },
			to: handlePrintDebugInformation
		)
	}

	@objc(printDebugInformationToConsole:inWebView:)
	private func printDebugInformationToConsole(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.printDebugInformationToConsole()",
			minimum: 1,
			validate: { _, value in value is String },
			to: handlePrintDebugInformationToConsole
		)
	}

	@objc(renderMessagesBefore:inWebView:)
	private func renderMessagesBefore(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.renderMessagesBefore()",
			minimum: 2,
			validate: Self.stringThenNumber,
			to: handleRenderMessagesBefore
		)
	}

	@objc(renderMessagesAfter:inWebView:)
	private func renderMessagesAfter(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.renderMessagesAfter()",
			minimum: 2,
			validate: Self.stringThenNumber,
			to: handleRenderMessagesAfter
		)
	}

	@objc(renderMessagesInRange:inWebView:)
	private func renderMessagesInRange(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.renderMessagesInRange()",
			minimum: 3,
			validate: { $0 <= 1 ? $1 is String : $1 is NSNumber },
			to: handleRenderMessagesInRange
		)
	}

	@objc(renderMessageWithSiblings:inWebView:)
	private func renderMessageWithSiblings(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.renderMessageWithSiblings()",
			minimum: 3,
			validate: { $0 == 0 ? $1 is String : $1 is NSNumber },
			to: handleRenderMessageWithSiblings
		)
	}

	@objc(retrievePreferencesWithMethodName:inWebView:)
	private func retrievePreferencesWithMethodName(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.retrievePreferencesWithMethodName()",
			minimum: 1,
			validate: { _, value in value is String },
			to: handleRetrievePreferences
		)
	}

	@objc(renderTemplate:inWebView:)
	private func renderTemplate(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.renderTemplate()",
			minimum: 2,
			validate: { $0 == 0 ? $1 is String : ($1 is NSNull || $1 is [AnyHashable: Any]) },
			to: handleRenderTemplate
		)
	}

	@objc(sendPluginPayload:inWebView:)
	private func sendPluginPayload(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.sendPluginPayload()",
			minimum: 2,
			validate: { $0 != 0 || $1 is String },
			to: handleSendPluginPayload
		)
	}

	@objc(serverAddress:inWebView:)
	private func serverAddress(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.serverAddress()",
			to: handleServerAddress
		)
	}

	@objc(serverChannelCount:inWebView:)
	private func serverChannelCount(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.serverChannelCount()",
			to: handleServerChannelCount
		)
	}

	@objc(serverIsConnected:inWebView:)
	private func serverIsConnected(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.serverIsConnected()",
			to: handleServerIsConnected
		)
	}

	@objc(setChannelName:inWebView:)
	private func setChannelName(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.setChannelName()",
			minimum: 1,
			validate: Self.nullOrString,
			to: handleSetChannelName
		)
	}

	@objc(setNickname:inWebView:)
	private func setNickname(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.setNickname()",
			minimum: 1,
			validate: Self.nullOrString,
			to: handleSetNickname
		)
	}

	@objc(setLineContext:inWebView:)
	private func setLineContext(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.setLineContext()",
			minimum: 1,
			validate: { _, value in value is NSNull || value is [AnyHashable: Any] },
			to: handleSetLineContext
		)
	}

	@objc(setSelection:inWebView:)
	private func setSelection(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.setSelection()",
			minimum: 1,
			validate: Self.nullOrString,
			to: handleSetSelection
		)
	}

	@objc(setURLAddress:inWebView:)
	private func setURLAddress(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.setURLAddress()",
			minimum: 1,
			validate: Self.nullOrString,
			to: handleSetURLAddress
		)
	}

	@objc(sidebarInversionIsEnabled:inWebView:)
	private func sidebarInversionIsEnabled(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.sidebarInversionIsEnabled()",
			to: handleSidebarInversionIsEnabled
		)
	}
}

extension TVCLogScriptEventSink {
	@objc(appearance:inWebView:)
	private func appearance(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.appearance()",
			to: handleAppearance
		)
	}

	@objc(styleSettingsRetrieveValue:inWebView:)
	private func styleSettingsRetrieveValue(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.styleSettingsRetrieveValue()",
			minimum: 1,
			validate: { _, value in value is String },
			to: handleStyleSettingsRetrieveValue
		)
	}

	@objc(styleSettingsSetValue:inWebView:)
	private func styleSettingsSetValue(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.styleSettingsSetValue()",
			minimum: 2,
			validate: Self.styleSettingArgument,
			to: handleStyleSettingsSetValue
		)
	}

	@objc(topicBarDoubleClicked:inWebView:)
	private func topicBarDoubleClicked(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.topicBarDoubleClicked()",
			to: handleTopicBarDoubleClicked
		)
	}

	@objc(finishedLayingOutView:inWebView:)
	private func finishedLayingOutView(_ data: Any, inWebView view: Any) {
		dispatch(
			data,
			view,
			caller: "app.finishedLayingOutView()",
			to: handleFinishedLayingOutView
		)
	}

	private static func stringThenNumber(_ index: Int,
	                                     _ value: Any) -> Bool
	{
		index == 0 ? value is String : value is NSNumber
	}

	private static func nullOrString(_: Int, _ value: Any) -> Bool {
		value is NSNull || value is String
	}

	private static func styleSettingArgument(_ index: Int, _ value: Any) -> Bool {
		if index == 0 {
			return value is String
		}
		return value is [Any] || value is [AnyHashable: Any] || value is NSNull || value is NSNumber || value is String
	}

	private func handleChannelIsActive(_ context: LogScriptEventContext) {
		context.completion(context.associatedChannel?.isActive ?? false)
	}

	private func handleChannelMemberCount(_ context: LogScriptEventContext) {
		guard let channel = context.associatedChannel, channel.isChannel else {
			Self.throwJavaScriptException("View is not a channel", caller: context.caller, in: context.webView)
			return
		}
		context.completion(channel.numberOfMembers)
	}

	private func handleChannelName(_ context: LogScriptEventContext) {
		context.completion(context.associatedChannel?.name)
	}

	private func handleChannelNameDoubleClicked(_ context: LogScriptEventContext) {
		context.webViewPolicy.perform(
			NSSelectorFromString("channelNameDoubleClickedInWebView:"),
			with: context.webView
		)
	}

	private func handleDisplayContextMenu(_ context: LogScriptEventContext) {
		context.webViewPolicy.perform(NSSelectorFromString("displayContextMenuInWebView:"), with: context.webView)
	}

	private func handleCopySelectionWhenPermitted(_ context: LogScriptEventContext) {
		guard TextualPreferences.copyOnSelect(), let selection = context.webView.selection else {
			context.completion(false)
			return
		}
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(selection, forType: .string)
		context.completion(true)
	}

	private func handleInlineMediaEnabledForView(_ context: LogScriptEventContext) {
		context.completion(context.viewController.inlineMediaEnabledForView)
	}

	private func handleLoadInlineMedia(_ context: LogScriptEventContext) {
		guard let address = Self.objectValueToCommon(context.arguments[0]) as? String,
		      !address.isEmpty
		else { return fail(
			"Length of address is 0",
			context
		) }
		guard let identifier = Self.objectValueToCommon(context.arguments[1]) as? String,
		      !identifier.isEmpty
		else { return fail(
			"Length of unique identifier is 0",
			context
		) }
		guard let rawLine = Self.objectValueToCommon(context.arguments[2]) as? String else { return fail(
			"Length of line number is 0",
			context
		) }
		let lineNumber = Self.standardizeLineNumber(rawLine)
		guard !lineNumber.isEmpty else { return fail("Length of line number is 0", context) }
		let index = (Self.objectValueToCommon(context.arguments[3]) as? NSNumber)?.uintValue ?? 0
		context.viewController.processInlineMediaAtAddress(
			address,
			withUniqueIdentifier: identifier,
			atLineNumber: lineNumber,
			index: index
		)
	}

	private func handleLocalUserHostmask(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.userHostmask)
	}

	private func handleLocalUserNickname(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.userNickname)
	}

	private func handleLogToConsole(_ context: LogScriptEventContext) {
		let message = Self.objectValueToCommon(context.arguments[0]) as? String ?? ""
		scriptEventLogger.info("JavaScript: \(message, privacy: .public)")
	}

	private func handleNetworkName(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.networkName)
	}

	private func handleNicknameColorStyleHash(_ context: LogScriptEventContext) {
		let input = Self.objectValueToCommon(context.arguments[0]) as? String ?? ""
		let style = Self.objectValueToCommon(context.arguments[1]) as? String
		let colorStyle: TPCThemeSettingsNicknameColorStyle
		switch style {
		case "HSL-dark": colorStyle = .dark
		case "HSL-light": colorStyle = .light
		default: return fail("Invalid style", context)
		}
		context.completion(UserNicknameColorStyleGenerator.hash(for: input, colorStyle: colorStyle))
	}

	private func handleNicknameDoubleClicked(_ context: LogScriptEventContext) {
		context.webViewPolicy.perform(
			NSSelectorFromString("nicknameDoubleClickedInWebView:"),
			with: context.webView
		)
	}

	private func handleNotifyJumpToLineCallback(_ context: LogScriptEventContext) {
		let completion = context.completion
		guard let rawLine = Self.objectValueToCommon(context.arguments[0]) as? String else { fail(
			"Length of line number is 0",
			context
		); completion(nil); return }
		let lineNumber = Self.standardizeLineNumber(rawLine)
		guard !lineNumber.isEmpty else { fail("Length of line number is 0", context); completion(nil); return }
		let successful = (Self.objectValueToCommon(context.arguments[1]) as? NSNumber)?.boolValue ?? false
		/* The style also reports whether the jump landed at the bottom of the
		 buffer. Scroll position is owned entirely by the style's JavaScript,
		 so there is nothing on this side to tell; the argument is ignored. */
		context.viewController.notifyJumpToLine(lineNumber, successful: successful)
	}

	private func handleNotifyLinesAddedToView(_ context: LogScriptEventContext) {
		handleNotifyLines(added: true, context)
	}

	private func handleNotifyLinesRemovedFromView(_ context: LogScriptEventContext) {
		handleNotifyLines(
			added: false,
			context
		)
	}

	private func handleNotifyLines(added: Bool, _ context: LogScriptEventContext) {
		let raw = Self.objectValueToCommon(context.arguments[0])
		let values: [Any] = (raw as? String).map { [$0] } ?? (raw as? [Any] ?? [])
		let stringValues = values.compactMap { $0 as? String }
		guard stringValues.count == values.count else { return fail(
			"Line numbers must be a string or an array of strings",
			context
		) }
		let lines = Self.standardizeLineNumbers(stringValues)
		if added {
			context.viewController.notifyLinesAdded(toView: lines)
		} else {
			context.viewController.notifyLinesRemoved(fromView: lines)
		}
	}

	private func handlePrintDebugInformation(_ context: LogScriptEventContext) {
		context.associatedClient.printDebugInformation(
			Self.objectValueToCommon(context.arguments[0]) as? String ?? "",
			in: context.associatedChannel
		)
	}

	private func handlePrintDebugInformationToConsole(_ context: LogScriptEventContext) {
		context.associatedClient.printDebugInformation(
			toConsole: Self.objectValueToCommon(context.arguments[0]) as? String ?? ""
		)
	}

	private func handleRenderMessagesBefore(_ context: LogScriptEventContext) {
		handleRenderMessages(
			after: false,
			context
		)
	}

	private func handleRenderMessagesAfter(_ context: LogScriptEventContext) {
		handleRenderMessages(after: true, context)
	}

	private func handleRenderMessages(after: Bool, _ context: LogScriptEventContext) {
		let completion = context.completion
		guard let rawLine = Self.objectValueToCommon(context.arguments[0]) as? String else { fail(
			"Length of line number is 0",
			context
		); completion(nil); return }
		let line = Self.standardizeLineNumber(rawLine)
		guard !line.isEmpty else { fail("Length of line number is 0", context); completion(nil); return }
		let maximum = (Self.objectValueToCommon(context.arguments[1]) as? NSNumber)?.intValue ?? 0
		guard maximum > 0
		else { fail("Maximum number of lines must be equal to 1 or greater", context); completion(nil); return }
		let finished: ([[AnyHashable: Any]]) -> Void = { completion($0) }
		if after {
			context.viewController.renderLogLinesAfterLineNumber(
				line,
				maximumNumberOfLines: UInt(maximum),
				completionBlock: finished
			)
		} else {
			context.viewController.renderLogLinesBeforeLineNumber(
				line,
				maximumNumberOfLines: UInt(maximum),
				completionBlock: finished
			)
		}
	}

	private func handleRenderMessagesInRange(_ context: LogScriptEventContext) {
		let completion = context.completion
		guard let rawAfter = Self.objectValueToCommon(context.arguments[0]) as? String,
		      let rawBefore = Self.objectValueToCommon(context.arguments[1]) as? String
		else { fail(
			"Length of line number is 0",
			context
		); completion(nil); return }
		let after = Self.standardizeLineNumber(rawAfter), before = Self.standardizeLineNumber(rawBefore)
		guard !after.isEmpty,
		      !before.isEmpty else { fail("Length of line number is 0", context); completion(nil); return }
		let maximum = (Self.objectValueToCommon(context.arguments[2]) as? NSNumber)?.intValue ?? -1
		guard maximum >= 0
		else { fail("Maximum number of lines must be equal to 0 or greater", context); completion(nil); return }
		context.viewController.renderLogLines(
			afterLineNumber: after,
			beforeLineNumber: before,
			maximumNumberOfLines: UInt(maximum)
		) { completion($0) }
	}

	private func handleRenderMessageWithSiblings(_ context: LogScriptEventContext) {
		let completion = context.completion
		guard let rawLine = Self.objectValueToCommon(context.arguments[0]) as? String else { fail(
			"Length of line number is 0",
			context
		); completion(nil); return }
		let line = Self.standardizeLineNumber(rawLine)
		guard !line.isEmpty else { fail("Length of line number is 0", context); completion(nil); return }
		let before = (Self.objectValueToCommon(context.arguments[1]) as? NSNumber)?.intValue ?? -1
		let after = (Self.objectValueToCommon(context.arguments[2]) as? NSNumber)?.intValue ?? -1
		guard before >= 0,
		      after >= 0
		else { fail("Number of lines must be equal to 0 or greater", context); completion(nil); return }
		context.viewController.renderLogLine(
			atLineNumber: line,
			numberOfLinesBefore: UInt(before),
			numberOfLinesAfter: UInt(after)
		) { completion($0) }
	}

	private func handleRenderTemplate(_ context: LogScriptEventContext) {
		guard let name = Self.objectValueToCommon(context.arguments[0]) as? String, !name.isEmpty else { fail(
			"Length of template name is 0",
			context
		); context.completion(nil); return }
		let attributes = Self.objectValueToCommon(context.arguments[1]) as? [String: Any]
		context.completion(TVCLogRenderer.renderTemplateNamed(name, attributes: attributes))
	}

	private func handleRetrievePreferences(_ context: LogScriptEventContext) {
		guard let methodName = Self.objectValueToCommon(context.arguments[0]) as? String
		else { context.completion(nil); return }
		let selector = NSSelectorFromString(methodName)
		guard let method = class_getClassMethod(TextualPreferences.self, selector) else { fail(
			"Unknown method named: '%@'",
			context,
			[methodName]
		); context.completion(nil); return }
		guard method_getNumberOfArguments(method) == 2 else { fail(
			"Method named '%@' takes arguments",
			context,
			[methodName]
		); context.completion(nil); return }
		let returnType = method_copyReturnType(method)
		defer { free(returnType) }
		let implementation = method_getImplementation(method)
		context.completion(Self.invokePreference(
			implementation,
			selector: selector,
			returnType: returnType,
			context: context
		))
	}

	private static func invokePreference(
		_ implementation: IMP,
		selector: Selector,
		returnType: UnsafePointer<CChar>,
		context: LogScriptEventContext
	) -> Any? {
		let target: AnyClass = TextualPreferences.self
		switch returnType.pointee {
		case 64: return unsafeBitCast(implementation, to: (@convention(c) (AnyClass, Selector) -> AnyObject?).self)(
				target,
				selector
			)
		case 66: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Bool).self
			)(target, selector))
		case 99: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Int8).self
			)(target, selector))
		case 67: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> UInt8).self
			)(target, selector))
		case 73: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> UInt32).self
			)(target, selector))
		case 83: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> UInt16).self
			)(target, selector))
		case 76, 81: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> UInt64).self
			)(target, selector))
		case 105: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Int32).self
			)(target, selector))
		case 115: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Int16).self
			)(target, selector))
		case 108, 113: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Int64).self
			)(target, selector))
		case 102: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Float).self
			)(target, selector))
		case 100: return NSNumber(value: unsafeBitCast(
				implementation,
				to: (@convention(c) (AnyClass, Selector) -> Double).self
			)(target, selector))
		case 118: fail(
				"Method named '%@' does not return a value",
				context,
				[NSStringFromSelector(selector)]
			); return nil
		default: fail(
				"Method named '%@' returns an unsupported type",
				context,
				[NSStringFromSelector(selector)]
			); return nil
		}
	}

	private func handleSendPluginPayload(_ context: LogScriptEventContext) {
		guard SharedApplication.sharedPluginManager().supportsFeature(.webViewJavaScriptPayloads) else { return fail(
			"There are no plugins loaded that support JavaScript payloads",
			context
		) }
		guard let label = Self.objectValueToCommon(context.arguments[0]) as? String, !label.isEmpty else { return fail(
			"Length of payload label is 0",
			context
		) }
		let payload = PluginJavaScriptPayload(); payload.payloadLabel = label; payload.payloadContents = Self
			.objectValueToCommon(context.arguments[1])
		PluginDispatcher.perform(
			NSSelectorFromString("didReceiveJavaScriptPayload:fromViewController:"),
			with: payload,
			with: context.viewController
		)
	}

	private func handleServerAddress(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.serverAddress)
	}

	private func handleServerChannelCount(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.channelCount)
	}

	private func handleServerIsConnected(_ context: LogScriptEventContext) {
		context.completion(context.associatedClient.isLoggedIn)
	}

	private func handleSetChannelName(_ context: LogScriptEventContext) {
		context.webView.contextMenuTarget.channelName = Self.objectValueToCommon(context.arguments[0]) as? String
	}

	private func handleSetNickname(_ context: LogScriptEventContext) {
		context.webView.contextMenuTarget.nickname = Self.objectValueToCommon(context.arguments[0]) as? String
	}

	private func handleSetLineContext(_ context: LogScriptEventContext) {
		let value = Self.objectValueToCommon(context.arguments[0]) as? [AnyHashable: Any]
		let target = context.webView.contextMenuTarget
		target.lineNumber = value?["lineNumber"] as? String; target.lineMessageIdentifier = value?["msgid"] as? String
		target.lineType = value?["lineType"] as? String; target.lineNickname = value?["nickname"] as? String; target
			.lineExcerpt = value?["excerpt"] as? String
	}

	private func handleSetSelection(_ context: LogScriptEventContext) {
		let value = Self.objectValueToCommon(context.arguments[0]) as? String; context.webView.selection = value?
			.isEmpty == true ? nil : value
	}

	private func handleSetURLAddress(_ context: LogScriptEventContext) {
		context.webView.contextMenuTarget.anchorURL = Self.objectValueToCommon(context.arguments[0]) as? String
	}

	private func handleSidebarInversionIsEnabled(_ context: LogScriptEventContext) {
		context.completion(context.viewController.attachedWindow.userInterfaceObjects.isDarkAppearance)
	}

	private func handleAppearance(_ context: LogScriptEventContext) {
		context.completion(context.viewController.attachedWindow.userInterfaceObjects.shortAppearanceDescription)
	}

	private func handleStyleSettingsRetrieveValue(_ context: LogScriptEventContext) {
		let key = Self.objectValueToCommon(context.arguments[0]) as? String ?? ""; var error: NSString?
		let result = SharedApplication.sharedThemeController().settings.styleSettingsRetrieveValue(
			forKey: key,
			error: &error
		)
		if let error {
			Self.throwJavaScriptException(error as String, caller: context.caller, in: context.webView)
		}; context.completion(result)
	}

	private func handleStyleSettingsSetValue(_ context: LogScriptEventContext) {
		let key = Self.objectValueToCommon(context.arguments[0]) as? String ?? ""; let value = Self
			.objectValueToCommon(context.arguments[1]); var error: NSString?
		let result = SharedApplication.sharedThemeController().settings.styleSettingsSetValue(
			value,
			forKey: key,
			error: &error
		)
		if let error {
			Self.throwJavaScriptException(error as String, caller: context.caller, in: context.webView)
		}
		if result {
			NSObject.applicationController().world.evaluateFunction(
				onAllViews: "Glasstual.styleSettingDidChange",
				arguments: [key]
			)
		}
		context.completion(result)
	}

	private func handleTopicBarDoubleClicked(_ context: LogScriptEventContext) {
		context.webViewPolicy.topicBarDoubleClicked()
	}

	private func handleFinishedLayingOutView(_ context: LogScriptEventContext) {
		context.webView.setViewFinishedLayout()
	}

	private func fail(_ message: String, _ context: LogScriptEventContext, _ arguments: [CVarArg] = []) {
		Self.fail(message, context, arguments)
	}

	private static func fail(_ message: String, _ context: LogScriptEventContext, _ arguments: [CVarArg] = []) {
		throwJavaScriptException(message, caller: context.caller, in: context.webView, arguments: arguments)
	}
}
