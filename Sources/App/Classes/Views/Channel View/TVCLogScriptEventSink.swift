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

/** The argument contract and body of one bridged function.
 Kept as data so the whole table stays in one place and can be checked for
 completeness against `TVCLogScriptEventSink.ScriptMessage.allCases`. */
@MainActor
private struct ScriptMessageHandler {
	let minimumArgumentCount: Int
	let validate: ((Int, Any) -> Bool)?
	let invoke: @MainActor (TVCLogScriptEventSink, LogScriptEventContext) -> Void

	init(
		minimum: Int = 0,
		validate: ((Int, Any) -> Bool)? = nil,
		invoke: @escaping @MainActor (TVCLogScriptEventSink, LogScriptEventContext) -> Void
	) {
		minimumArgumentCount = minimum
		self.validate = validate
		self.invoke = invoke
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

	/** Every name registered with `WKUserContentController` maps to exactly one
	 case. Dispatch used to go through `NSSelectorFromString` plus `perform`,
	 which silently dropped any registered name that had no matching selector. */
	enum ScriptMessage: String, CaseIterable, Sendable {
		case appearance
		case channelIsActive
		case channelMemberCount
		case channelName
		case channelNameDoubleClicked
		case displayContextMenu
		case copySelectionWhenPermitted
		case inlineMediaEnabledForView
		case loadInlineMedia
		case localUserHostmask
		case localUserNickname
		case logToConsole
		case networkName
		case nicknameColorStyleHash
		case nicknameDoubleClicked
		case notifyLinesAddedToView
		case notifyLinesRemovedFromView
		case notifyJumpToLineCallback
		case printDebugInformation
		case printDebugInformationToConsole
		case renderMessagesBefore
		case renderMessagesAfter
		case renderMessagesInRange
		case renderMessageWithSiblings
		case renderTemplate
		case retrievePreferencesWithMethodName
		case sendPluginPayload
		case serverAddress
		case serverChannelCount
		case serverIsConnected
		case setChannelName
		case setNickname
		case setLineContext
		case setSelection
		case setURLAddress
		case sidebarInversionIsEnabled
		case styleSettingsRetrieveValue
		case styleSettingsSetValue
		case topicBarDoubleClicked
		case finishedLayingOutView
	}

	/// The exact set of handler names `WKUserContentController` must register.
	static let registeredMessageNames: [String] = ScriptMessage.allCases.map(\.rawValue)

	func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let scriptMessage = ScriptMessage(rawValue: message.name) else {
			scriptEventLogger.error(
				"Ignoring unregistered script message '\(message.name, privacy: .public)'"
			)
			return
		}
		guard let handler = Self.handlers[scriptMessage] else {
			scriptEventLogger.fault(
				"No handler bound for script message '\(message.name, privacy: .public)'"
			)
			return
		}
		guard let sourceWebView = message.webView else {
			scriptEventLogger.fault(
				"Script message '\(message.name, privacy: .public)' arrived without a web view"
			)
			return
		}
		processInputData(
			message.body,
			caller: "app.\(scriptMessage.rawValue)()",
			webView: sourceWebView,
			minimumArgumentCount: handler.minimumArgumentCount,
			validate: handler.validate
		) { context in
			handler.invoke(self, context)
		}
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
}

extension TVCLogScriptEventSink {
	fileprivate static let handlers: [ScriptMessage: ScriptMessageHandler] = queryHandlers
		.merging(mutationHandlers) { first, _ in first }

	private static let queryHandlers: [ScriptMessage: ScriptMessageHandler] = [
		.appearance: ScriptMessageHandler { $0.handleAppearance($1) },
		.channelIsActive: ScriptMessageHandler { $0.handleChannelIsActive($1) },
		.channelMemberCount: ScriptMessageHandler { $0.handleChannelMemberCount($1) },
		.channelName: ScriptMessageHandler { $0.handleChannelName($1) },
		.channelNameDoubleClicked: ScriptMessageHandler { $0.handleChannelNameDoubleClicked($1) },
		.displayContextMenu: ScriptMessageHandler { $0.handleDisplayContextMenu($1) },
		.copySelectionWhenPermitted: ScriptMessageHandler { $0.handleCopySelectionWhenPermitted($1) },
		.inlineMediaEnabledForView: ScriptMessageHandler { $0.handleInlineMediaEnabledForView($1) },
		.loadInlineMedia: ScriptMessageHandler(minimum: 4, validate: leadingStrings(3)) {
			$0.handleLoadInlineMedia($1)
		},
		.localUserHostmask: ScriptMessageHandler { $0.handleLocalUserHostmask($1) },
		.localUserNickname: ScriptMessageHandler { $0.handleLocalUserNickname($1) },
		.logToConsole: ScriptMessageHandler(minimum: 1, validate: isString) { $0.handleLogToConsole($1) },
		.networkName: ScriptMessageHandler { $0.handleNetworkName($1) },
		.nicknameColorStyleHash: ScriptMessageHandler(minimum: 2, validate: isString) {
			$0.handleNicknameColorStyleHash($1)
		},
		.nicknameDoubleClicked: ScriptMessageHandler { $0.handleNicknameDoubleClicked($1) },
		.serverAddress: ScriptMessageHandler { $0.handleServerAddress($1) },
		.serverChannelCount: ScriptMessageHandler { $0.handleServerChannelCount($1) },
		.serverIsConnected: ScriptMessageHandler { $0.handleServerIsConnected($1) },
		.sidebarInversionIsEnabled: ScriptMessageHandler { $0.handleSidebarInversionIsEnabled($1) },
		.topicBarDoubleClicked: ScriptMessageHandler { $0.handleTopicBarDoubleClicked($1) },
		.finishedLayingOutView: ScriptMessageHandler { $0.handleFinishedLayingOutView($1) },
	]

	private static let mutationHandlers: [ScriptMessage: ScriptMessageHandler] = [
		.notifyLinesAddedToView: ScriptMessageHandler(minimum: 1, validate: stringOrArray) {
			$0.handleNotifyLinesAddedToView($1)
		},
		.notifyLinesRemovedFromView: ScriptMessageHandler(minimum: 1, validate: stringOrArray) {
			$0.handleNotifyLinesRemovedFromView($1)
		},
		.notifyJumpToLineCallback: ScriptMessageHandler(minimum: 3, validate: leadingStrings(1)) {
			$0.handleNotifyJumpToLineCallback($1)
		},
		.printDebugInformation: ScriptMessageHandler(minimum: 1, validate: isString) {
			$0.handlePrintDebugInformation($1)
		},
		.printDebugInformationToConsole: ScriptMessageHandler(minimum: 1, validate: isString) {
			$0.handlePrintDebugInformationToConsole($1)
		},
		.renderMessagesBefore: ScriptMessageHandler(minimum: 2, validate: leadingStrings(1)) {
			$0.handleRenderMessagesBefore($1)
		},
		.renderMessagesAfter: ScriptMessageHandler(minimum: 2, validate: leadingStrings(1)) {
			$0.handleRenderMessagesAfter($1)
		},
		.renderMessagesInRange: ScriptMessageHandler(minimum: 3, validate: leadingStrings(2)) {
			$0.handleRenderMessagesInRange($1)
		},
		.renderMessageWithSiblings: ScriptMessageHandler(minimum: 3, validate: leadingStrings(1)) {
			$0.handleRenderMessageWithSiblings($1)
		},
		.renderTemplate: ScriptMessageHandler(minimum: 2, validate: templateArgument) {
			$0.handleRenderTemplate($1)
		},
		.retrievePreferencesWithMethodName: ScriptMessageHandler(minimum: 1, validate: isString) {
			$0.handleRetrievePreferences($1)
		},
		.sendPluginPayload: ScriptMessageHandler(minimum: 2, validate: pluginPayloadArgument) {
			$0.handleSendPluginPayload($1)
		},
		.setChannelName: ScriptMessageHandler(minimum: 1, validate: nullOrString) {
			$0.handleSetChannelName($1)
		},
		.setNickname: ScriptMessageHandler(minimum: 1, validate: nullOrString) { $0.handleSetNickname($1) },
		.setLineContext: ScriptMessageHandler(minimum: 1, validate: lineContextArgument) {
			$0.handleSetLineContext($1)
		},
		.setSelection: ScriptMessageHandler(minimum: 1, validate: nullOrString) { $0.handleSetSelection($1) },
		.setURLAddress: ScriptMessageHandler(minimum: 1, validate: nullOrString) {
			$0.handleSetURLAddress($1)
		},
		.styleSettingsRetrieveValue: ScriptMessageHandler(minimum: 1, validate: isString) {
			$0.handleStyleSettingsRetrieveValue($1)
		},
		.styleSettingsSetValue: ScriptMessageHandler(minimum: 2, validate: styleSettingArgument) {
			$0.handleStyleSettingsSetValue($1)
		},
	]

	/// The first `count` arguments must be strings; every later one a number.
	private nonisolated static func leadingStrings(_ count: Int) -> (Int, Any) -> Bool {
		{ index, value in index < count ? value is String : value is NSNumber }
	}

	private nonisolated static func isString(_: Int, _ value: Any) -> Bool {
		value is String
	}

	private nonisolated static func nullOrString(_: Int, _ value: Any) -> Bool {
		value is NSNull || value is String
	}

	private nonisolated static func stringOrArray(_: Int, _ value: Any) -> Bool {
		value is String || value is [Any]
	}

	private nonisolated static func templateArgument(_ index: Int, _ value: Any) -> Bool {
		if index == 0 {
			return value is String
		}
		return value is NSNull || value is [AnyHashable: Any]
	}

	private nonisolated static func lineContextArgument(_: Int, _ value: Any) -> Bool {
		value is NSNull || value is [AnyHashable: Any]
	}

	private nonisolated static func pluginPayloadArgument(_ index: Int, _ value: Any) -> Bool {
		index != 0 || value is String
	}

	private nonisolated static func styleSettingArgument(_ index: Int, _ value: Any) -> Bool {
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

	/** Preferences a style is allowed to read through
	 `app.retrievePreferencesWithMethodName()`.

	 The bridge used to resolve the name against the Objective-C runtime and
	 call the resulting IMP, which reached every inherited `NSObject` class
	 method as well. Styles only ever need presentation settings, so the set
	 is enumerated rather than discovered. */
	static let permittedPreferences: [String: @MainActor () -> Any?] = [
		"autoAddScrollbackMark": { NSNumber(value: TextualPreferences.autoAddScrollbackMark()) },
		"conversationTrackingIncludesUserModeSymbol": {
			NSNumber(value: TextualPreferences.conversationTrackingIncludesUserModeSymbol())
		},
		"copyOnSelect": { NSNumber(value: TextualPreferences.copyOnSelect()) },
		"disableNicknameColorHashing": { NSNumber(value: TextualPreferences.disableNicknameColorHashing()) },
		"inlineMediaMaxHeight": { NSNumber(value: TextualPreferences.inlineMediaMaxHeight()) },
		"inlineMediaMaxWidth": { NSNumber(value: TextualPreferences.inlineMediaMaxWidth()) },
		"removeAllFormatting": { NSNumber(value: TextualPreferences.removeAllFormatting()) },
		"rightToLeftFormatting": { NSNumber(value: TextualPreferences.rightToLeftFormatting()) },
		"scrollbackVisibleLimit": { NSNumber(value: TextualPreferences.scrollbackVisibleLimit()) },
		"showDateChanges": { NSNumber(value: TextualPreferences.showDateChanges()) },
		"showInlineMedia": { NSNumber(value: TextualPreferences.showInlineMedia()) },
		"showJoinLeave": { NSNumber(value: TextualPreferences.showJoinLeave()) },
		"themeChannelViewFontName": { TextualPreferences.themeChannelViewFontName() },
		"themeChannelViewFontSize": { NSNumber(value: Double(TextualPreferences.themeChannelViewFontSize())) },
		"themeChannelViewUsesCustomScrollers": {
			NSNumber(value: TextualPreferences.themeChannelViewUsesCustomScrollers())
		},
		"themeName": { TextualPreferences.themeName() },
		"themeNicknameFormat": { TextualPreferences.themeNicknameFormat() },
		"themeTimestampFormat": { TextualPreferences.themeTimestampFormat() },
		"webKit2PreviewLinks": { NSNumber(value: TextualPreferences.webKit2PreviewLinks()) },
	]

	private func handleRetrievePreferences(_ context: LogScriptEventContext) {
		guard let name = Self.objectValueToCommon(context.arguments[0]) as? String else {
			context.completion(nil)
			return
		}
		guard let read = Self.permittedPreferences[name] else {
			fail("Preference named '%@' is not readable by a style", context, [name])
			context.completion(nil)
			return
		}
		context.completion(read())
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
