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
import CocoaExtensions
import Foundation
import GlasstualPluginKit
import InlineContentKit
import os

public typealias TVCLogController = LogController

public extension Notification.Name {
	static let logControllerViewFinishedLoading = Notification.Name(
		"TVCLogControllerViewFinishedLoadingNotification"
	)
}

public typealias LogControllerPrintOperationCompletion = (LogControllerPrintOperationContext) -> Void

private let logControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogController"
)

/// Carries legacy AppKit and Objective-C values across the controller's
/// explicit hop back to the main actor. These values are consumed only by the
/// scheduled main-actor closure.
private final class LogControllerMainActorTransfer<Value>: @unchecked Sendable {
	let value: Value

	init(value: Value) {
		self.value = value
	}
}

@objc(TVCLogControllerPrintOperationContext)
@objcMembers
public final class LogControllerPrintOperationContext: NSObject {
	public private(set) weak var client: IRCClient?
	public private(set) weak var channel: IRCChannel?
	public private(set) var isHighlight: Bool
	public private(set) var logLine: LogLine
	public private(set) var lineNumber: String

	init(client: IRCClient, channel: IRCChannel?, highlight: Bool, logLine: LogLine, lineNumber: String) {
		self.client = client
		self.channel = channel
		isHighlight = highlight
		self.logLine = logLine
		self.lineNumber = lineNumber
		super.init()
	}
}

@objc(TVCLogController)
@objcMembers
public final class LogController: NSObject, @unchecked Sendable {
	public private(set) var backingView: LogView!
	public private(set) var viewIsLoaded = false
	public private(set) weak var associatedClient: IRCClient!
	public private(set) weak var associatedChannel: IRCChannel?
	public private(set) weak var attachedWindow: TVCMainWindow!
	public private(set) var newestLineNumberFromPreviousSession: String?
	public private(set) var oldestLineNumber: String?
	public private(set) var newestLineNumber: String?

	private var terminating = false
	private var historyLoadedForFirstTime = false
	private var reloadingHistory = false
	private var reloadingTheme = false
	private var historyLoaded = false
	private var activeLineCount = 0
	private var lastVisitedHighlight: String?
	private var lastLineStorage: LogLine?
	private var oldestLineStorage: LogLine?
	private var highlightedLineNumbers: [String] = []
	private var jumpToLineCallbacks: [String: (Bool) -> Void] = [:]
	private var reactionsByMessageIdentifier: [String: [String: [String]]] = [:]
	private var viewLoadedTimestamp: TimeInterval = 0
	private let highlightLock = NSRecursiveLock()
	private let reactionLock = NSLock()
	private let callbackLock = NSLock()

	private var associatedItem: IRCTreeItem {
		if let associatedChannel {
			return associatedChannel
		}
		return associatedClient
	}

	private var legacyController: TVCLogController {
		self
	}

	public var uniqueIdentifier: String {
		associatedItem.uniqueIdentifier
	}

	private var baseURL: URL {
		SharedApplication.sharedThemeController().temporaryURL
	}

	private var printingQueue: LogControllerPrintingOperationQueue {
		SharedApplication.sharedPrintingQueue()
	}

	public var numberOfLines: UInt {
		UInt(max(activeLineCount, 0))
	}

	public var inlineMediaEnabledForView: Bool {
		guard let channel = associatedChannel else {
			return false
		}
		let config = channel.config
		return TextualPreferences.showInlineMedia() ? !config.inlineMediaDisabled : config.inlineMediaEnabled
	}

	@MainActor public var viewIsSelected: Bool {
		attachedWindow.selectedViewController === self
	}

	@MainActor public var viewIsVisible: Bool {
		if let associatedChannel {
			return attachedWindow.isItemVisible(associatedChannel)
		}
		return attachedWindow.isItemVisible(associatedClient)
	}

	@available(*, unavailable, message: "Use init(client:in:) or init(channel:in:)")
	override public init() {
		fatalError("Use a designated log controller initializer")
	}

	@objc(initWithClient:inWindow:)
	public init(client: IRCClient, in window: TVCMainWindow) {
		associatedClient = client
		attachedWindow = window
		super.init()
		setUp()
	}

	@objc(initWithChannel:inWindow:)
	public init(channel: IRCChannel, in window: TVCMainWindow) {
		associatedClient = channel.associatedClient
		associatedChannel = channel
		attachedWindow = window
		super.init()
		setUp()
	}

	deinit {
		NSObject.cancelPreviousPerformRequests(withTarget: self)
	}

	private func setUp() {
		MainActor.assumeIsolated {
			backingView = LogView(viewController: self)
			loadInitialDocument()
		}
	}

	@MainActor
	private func loadInitialDocument() {
		loadAlternateHTML(initialDocument())
	}

	@MainActor
	private func loadAlternateHTML(_ html: String) {
		backingView.stopLoading()
		backingView.loadHTMLString(html, baseURL: baseURL)
	}

	private func historicLogForgetChannel() {
		LogControllerHistoricLogFile.shared().forgetItem(associatedItem)
	}

	private func historicLogResetChannel() {
		LogControllerHistoricLogFile.shared().resetData(for: associatedItem)
	}

	private func closeHistoricLog() {
		let channel = associatedChannel
		if !TextualPreferences.reloadScrollbackOnLaunch() || channel?.isUtility == true || channel?
			.isDirectChat == true ||
			(channel?.isPrivateMessage == true && !TextualPreferences.rememberServerListQueryStates())
		{
			historicLogResetChannel()
		}
	}

	private func prepareForTermination(_ isTerminatingApplication: Bool) {
		terminating = true
		viewIsLoaded = false
		let view = backingView
		backingView = nil
		DispatchQueue.main.async {
			MainActor.assumeIsolated { view?.stopLoading() }
		}
		printingQueue.cancelOperations(for: self)
		if isTerminatingApplication {
			closeHistoricLog()
		} else {
			historicLogForgetChannel()
		}
	}

	public func prepareForApplicationTermination() {
		// swiftformat:disable:next redundantSelf
		logControllerLogger.log("Preparing view controller: \(self.uniqueIdentifier, privacy: .public)")
		prepareForTermination(true)
	}

	public func prepareForPermanentDestruction() {
		prepareForTermination(false)
	}

	public func evaluateFunction(_ function: String, withArguments arguments: [Any]?) {
		evaluateFunction(function, withArguments: arguments, onQueue: true)
	}

	@objc(evaluateFunction:withArguments:onQueue:)
	public func evaluateFunction(_ function: String, withArguments arguments: [Any]?, onQueue: Bool) {
		guard !terminating else {
			return
		}
		if onQueue {
			printingQueue.enqueueMessageBlock({ [weak self] _ in
				self?.evaluateFunctionNow(function, arguments: arguments)
			}, for: self, isStandalone: false)
		} else {
			evaluateFunctionNow(function, arguments: arguments)
		}
	}

	private func evaluateFunctionNow(_ function: String, arguments: [Any]?) {
		guard viewIsLoaded, !terminating, let backingView else {
			return
		}
		let transferredArguments = LogControllerMainActorTransfer(value: arguments)
		Task { @MainActor in
			backingView.evaluateFunction(function, withArguments: transferredArguments.value)
		}
	}

	private func appendToDocumentBody(_ html: String, lineNumbers: [String]) {
		evaluateFunctionNow("MessageBuffer.bufferElementAppend", arguments: [html, lineNumbers])
	}

	private func setInitialTopic() {
		setTopic(associatedChannel?.topic)
	}

	public func setTopic(_ topic: String?) {
		guard !terminating else {
			return
		}
		printingQueue.enqueueMessageBlock({ [weak self] _ in
			guard let self else {
				return
			}
			let topicString = topic?.isEmpty == false ? topic! : MainWindowStrings.Conversation.noTopic
			let attributes: LogRendererConfiguration = [
				.renderLinks: true,
				.lineType: TVCLogLineType.topic.rawValue,
			]
			let rendered = TVCLogRenderer.renderBody(
				topicString,
				forViewController: legacyController,
				withAttributes: attributes.rawValues,
				resultInfo: nil
			)
			evaluateFunctionNow("Glasstual.setTopicBarValue", arguments: [topicString, rendered])
		}, for: self, isStandalone: true)
	}

	public func moveToTop() {
		evaluateFunctionNow("Glasstual.scrollToTopOfView", arguments: [true])
	}

	public func moveToBottom() {
		evaluateFunctionNow("Glasstual.scrollToBottomOfView", arguments: [true])
	}

	public func mark() {
		enqueueHistoryMark(function: "_Glasstual.historyIndicatorAdd", extraArguments: [])
	}

	@objc(markAtDate:)
	public func mark(at date: Date) {
		enqueueHistoryMark(
			function: "_Glasstual.historyIndicatorAddAfterTimestamp",
			extraArguments: [date.timeIntervalSince1970]
		)
	}

	private func enqueueHistoryMark(function: String, extraArguments: [Any]) {
		printingQueue.enqueueMessageBlock({ [weak self] _ in
			guard let self else {
				return
			}
			let attributes: ThemeTemplateAttributes = [
				.historyIndicatorMessage: MainWindowStrings.Conversation.unreadMessages,
			]
			let template = TVCLogRenderer.renderTemplateNamed(.historyIndicator, attributes: attributes)
			evaluateFunctionNow(function, arguments: [template as Any] + extraArguments)
		}, for: self, isStandalone: false)
	}

	public func unmark() {
		evaluateFunctionNow("_Glasstual.historyIndicatorRemove", arguments: nil)
	}

	public func goToMark() {
		evaluateFunctionNow("Glasstual.scrollToHistoryIndicator", arguments: nil)
	}

	private func appendHistoricMessageFragment(_ html: String, lineNumbers: [String], isReload: Bool) {
		evaluateFunctionNow("_Glasstual.documentBodyAppendHistoric", arguments: [html, lineNumbers, isReload])
	}

	private func reloadOldLines(_ oldLines: [LogLine], isReload: Bool) {
		var lineNumbers: [String] = []
		var html = ""
		var pluginObjects: [THOPluginDidPostNewMessageConcreteObject] = []
		for logLine in oldLines {
			var resultInfo: [AnyHashable: Any]?
			guard let rendered = renderLogLine(logLine, resultInfo: &resultInfo) else {
				logControllerLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
				continue
			}
			html += rendered
			let lineNumber = logLine.uniqueIdentifier
			lineNumbers.append(lineNumber)
			if let pluginObject = resultInfo?[LogPresentationResultKey.pluginObject.rawValue]
				as? THOPluginDidPostNewMessageConcreteObject
			{
				pluginObjects.append(pluginObject)
			}
			if (resultInfo?[LogRendererResultKey.keywordMatchFound.rawValue] as? NSNumber)?
				.boolValue == true
			{
				highlightLock.withLock { highlightedLineNumbers.append(lineNumber) }
			}
		}
		appendHistoricMessageFragment(html, lineNumbers: lineNumbers, isReload: isReload)
		for pluginObject in pluginObjects {
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
	}

	@MainActor private func maybeReloadHistory() {
		guard viewIsLoaded, !historyLoaded else {
			return
		}
		reloadHistory()
	}

	@MainActor private func reloadHistory() {
		guard !terminating else {
			return
		}
		let firstLoad = !historyLoadedForFirstTime
		let channel = associatedChannel
		if firstLoad && !TextualPreferences.reloadScrollbackOnLaunch() || channel?.isUtility == true ||
			channel?.isDirectChat == true ||
			(firstLoad && channel?.isPrivateMessage == true && !TextualPreferences.rememberServerListQueryStates())
		{
			historyLoadedForFirstTime = true
			historyLoaded = true
			notifyViewFinishedLoadingHistory()
			return
		}
		if UserDefaults.standard.bool(forKey: "Optimizations -> Load History Lazily"), !viewIsVisible {
			return
		}

		reloadingHistory = true
		printingQueue.enqueueAsynchronousMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				ascending: false,
				fetchLimit: 100,
				limitToDate: limitDate
			) { [weak self] entries in
				guard let self else {
					return
				}
				defer { self.printingQueue.finishOperation(operation) }
				guard !operation.isCancelled else {
					return
				}
				let entries = Array(entries.reversed())
				if lastLineStorage == nil {
					lastLineStorage = entries.last
				}
				noteOldestLineCandidate(entries.first)
				if firstLoad {
					newestLineNumberFromPreviousSession = entries.last?.uniqueIdentifier
				}
				reloadOldLines(entries, isReload: !firstLoad)
				reloadingHistory = false
				historyLoaded = true
				historyLoadedForFirstTime = true
				notifyViewFinishedLoadingHistory()
			}
		}, for: self, isStandalone: true)
	}
}

public extension LogController {
	func reloadTheme() {
		DispatchQueue.main.async { [weak self] in
			self?.reloadThemeNow()
		}
	}

	private func reloadThemeNow() {
		guard !terminating, !reloadingTheme else {
			return
		}
		historyLoadedForFirstTime = true
		reloadingTheme = true
		clear(resetHistoricLog: false)
		reloadingTheme = false
	}

	private func dateIndicator(with date: Date) -> String {
		formatDate(date, .long, .none, false) ?? ""
	}

	func jumpToCurrentSession() {
		guard let lineNumber = newestLineNumberFromPreviousSession ?? oldestLineNumber else {
			return
		}
		jump(toLine: lineNumber)
	}

	func jumpToPresent() {
		guard let lineNumber = newestLineNumber ?? newestLineNumberFromPreviousSession else {
			return
		}
		jump(toLine: lineNumber)
	}

	@objc(jumpToLine:)
	func jump(toLine lineNumber: String) {
		jump(toLine: lineNumber, completionHandler: nil)
	}

	@objc(jumpToLine:completionHandler:)
	func jump(toLine lineNumber: String, completionHandler: ((Bool) -> Void)?) {
		if let completionHandler {
			callbackLock.withLock { jumpToLineCallbacks[lineNumber] = completionHandler }
		}
		guard let backingView else {
			return
		}
		Task { @MainActor in
			backingView.evaluateFunction("Glasstual.jumpToLine", withArguments: [lineNumber])
		}
	}

	@MainActor func notifyDidBecomeVisible() {
		evaluateFunctionNow("_Glasstual.notifyDidBecomeVisible", arguments: nil)
		maybeReloadHistory()
	}

	func notifyDidBecomeHidden() {
		evaluateFunctionNow("_Glasstual.notifyDidBecomeHidden", arguments: nil)
	}

	@MainActor func notifySelectionChanged() {
		evaluateFunctionNow("_Glasstual.notifySelectionChanged", arguments: [viewIsSelected])
	}

	private func notifyViewFinishedLoadingHistory() {
		evaluateFunctionNow("_Glasstual.viewFinishedLoadingHistory", arguments: nil)
	}

	@MainActor func changeTextSize(_ bigger: Bool) {
		evaluateFunctionNow("Glasstual.changeTextSizeMultiplier", arguments: [attachedWindow.textSizeMultiplier])
		evaluateFunctionNow("Glasstual.viewFontSizeChanged", arguments: [bigger])
	}

	func changeScrollbackLimit() {
		evaluateFunctionNow("_MessageBuffer.setBufferLimit", arguments: [TextualPreferences.scrollbackVisibleLimit()])
	}

	func notifyJumpToLine(_ lineNumber: String, successful: Bool) {
		let callback = callbackLock.withLock { jumpToLineCallbacks.removeValue(forKey: lineNumber) }
		callback?(successful)
	}

	func notifyLinesAdded(toView lineNumbers: [String]) {
		guard viewIsLoaded, !terminating else {
			return
		}
		activeLineCount += lineNumbers.count
		guard SharedApplication.sharedPluginManager().supportsFeature(.newMessagePostedEvent) else {
			return
		}
		for lineNumber in lineNumbers {
			PluginDispatcher.dequeueDidPostNewMessage(withLineNumber: lineNumber, forViewController: self)
		}
	}

	func notifyLinesRemoved(fromView lineNumbers: [String]) {
		guard viewIsLoaded, !terminating else {
			return
		}
		activeLineCount = max(0, activeLineCount - lineNumbers.count)
	}

	func notifyHistoricLogWillDeleteLines(_ lineNumbers: [String]) {
		guard !terminating else {
			return
		}
		highlightLock.withLock { highlightedLineNumbers.removeAll { lineNumbers.contains($0) } }
	}

	func processingInlineMediaPayloadSucceeded(_ payload: InlineContentPayload) {
		evaluateFunctionNow("_InlineMediaLoader.processPayload", arguments: [payload.javaScriptObject])
	}

	func processingInlineMediaPayload(_ payload: InlineContentPayload, failedWithError error: Error) {
		logControllerLogger.error(
			"Processing request for '\(payload.uniqueIdentifier, privacy: .public)' at '\(payload.lineNumber, privacy: .public)' failed: \(error.localizedDescription, privacy: .public)"
		)
	}

	private func processInlineMedia(_ links: [LinkParserResult], atLineNumber lineNumber: String) {
		for (index, link) in links.enumerated() {
			processInlineMediaAtAddress(
				link.stringValue,
				withUniqueIdentifier: link.uniqueIdentifier,
				atLineNumber: lineNumber,
				index: UInt(index)
			)
		}
	}

	func processInlineMediaAtAddress(
		_ address: String,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String,
		index: UInt
	) {
		LogControllerInlineMediaService.shared().processAddress(
			address,
			withUniqueIdentifier: uniqueIdentifier,
			atLineNumber: lineNumber,
			index: index,
			forItem: associatedItem
		)
	}

	func highlightAvailable(_: Bool) -> Bool {
		guard viewIsLoaded, !terminating else {
			return false
		}
		return highlightLock.withLock { !highlightedLineNumbers.isEmpty }
	}

	func nextHighlight() {
		visitHighlight(offset: 1)
	}

	func previousHighlight() {
		visitHighlight(offset: -1)
	}

	private func visitHighlight(offset: Int) {
		guard viewIsLoaded, !terminating else {
			return
		}
		let target: String? = highlightLock.withLock {
			guard !highlightedLineNumbers.isEmpty else {
				return nil
			}
			let current = lastVisitedHighlight.flatMap(highlightedLineNumbers.firstIndex(of:))
			let index = current.map { ($0 + offset + highlightedLineNumbers.count) % highlightedLineNumbers.count } ?? 0
			lastVisitedHighlight = highlightedLineNumbers[index]
			return lastVisitedHighlight
		}
		if let target {
			jump(toLine: target)
		}
	}

	private func clear(resetHistoricLog: Bool) {
		guard !terminating else {
			return
		}
		printingQueue.cancelOperations(for: self)
		if resetHistoricLog {
			historicLogResetChannel()
		}
		highlightLock.withLock { highlightedLineNumbers.removeAll() }
		activeLineCount = 0
		lastVisitedHighlight = nil
		oldestLineNumber = nil
		newestLineNumber = nil
		lastLineStorage = nil
		oldestLineStorage = nil
		viewIsLoaded = false
		reloadingHistory = false
		historyLoaded = false
		Task { @MainActor [weak self] in
			self?.loadInitialDocument()
		}
	}

	func clear() {
		clear(resetHistoricLog: true)
	}

	func renderLogLinesBeforeLineNumber(
		_ lineNumber: String,
		maximumNumberOfLines: UInt,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		renderLogLines(after: false, lineNumber: lineNumber, maximumNumberOfLines: maximumNumberOfLines,
		               completionBlock: completionBlock)
	}

	func renderLogLinesAfterLineNumber(
		_ lineNumber: String,
		maximumNumberOfLines: UInt,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		renderLogLines(after: true, lineNumber: lineNumber, maximumNumberOfLines: maximumNumberOfLines,
		               completionBlock: completionBlock)
	}

	private func renderLogLines(
		after: Bool,
		lineNumber: String,
		maximumNumberOfLines: UInt,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		precondition(maximumNumberOfLines > 0)
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			let completion: ([LogLine]) -> Void = { [weak self] entries in
				guard let self, !operation.isCancelled else {
					return
				}
				finishRendering(entries, completionBlock: completionBlock)
			}
			if after {
				LogControllerHistoricLogFile.shared().fetchEntries(
					for: associatedItem,
					afterUniqueIdentifier: lineNumber,
					fetchLimit: maximumNumberOfLines,
					limitToDate: nil,
					withCompletionBlock: completion
				)
			} else {
				LogControllerHistoricLogFile.shared().fetchEntries(
					for: associatedItem,
					beforeUniqueIdentifier: lineNumber,
					fetchLimit: maximumNumberOfLines,
					limitToDate: nil
				) { [weak self] entries in
					guard let self, !operation.isCancelled else {
						return
					}
					noteOldestLineCandidate(entries.first)
					if entries.isEmpty {
						noteLocalScrollbackExhausted()
					}
					completion(entries)
				}
			}
		}, for: self, isStandalone: true)
	}

	@objc(renderLogLinesAfterLineNumber:beforeLineNumber:maximumNumberOfLines:completionBlock:)
	func renderLogLines(
		afterLineNumber lineNumberAfter: String,
		beforeLineNumber lineNumberBefore: String,
		maximumNumberOfLines: UInt,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				afterUniqueIdentifier: lineNumberAfter,
				beforeUniqueIdentifier: lineNumberBefore,
				fetchLimit: maximumNumberOfLines
			) { [weak self] entries in
				guard let self, !operation.isCancelled else {
					return
				}
				finishRendering(entries, completionBlock: completionBlock)
			}
		}, for: self, isStandalone: true)
	}

	@objc(renderLogLineAtLineNumber:numberOfLinesBefore:numberOfLinesAfter:completionBlock:)
	func renderLogLine(
		atLineNumber lineNumber: String,
		numberOfLinesBefore: UInt,
		numberOfLinesAfter: UInt,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				withUniqueIdentifier: lineNumber,
				beforeFetchLimit: numberOfLinesBefore,
				afterFetchLimit: numberOfLinesAfter,
				limitToDate: nil
			) { [weak self] entries in
				guard let self, !operation.isCancelled else {
					return
				}
				finishRendering(entries, completionBlock: completionBlock)
			}
		}, for: self, isStandalone: true)
	}

	private func finishRendering(
		_ logLines: [LogLine],
		completionBlock: ([[AnyHashable: Any]]) -> Void
	) {
		var renderedLogLines: [[AnyHashable: Any]] = []
		var pluginObjects: [THOPluginDidPostNewMessageConcreteObject] = []
		for logLine in logLines {
			var resultInfo: [AnyHashable: Any]?
			guard let html = renderLogLine(logLine, resultInfo: &resultInfo) else {
				logControllerLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
				continue
			}
			let renderedEntry: RenderedLogEntry = [
				.lineNumber: logLine.uniqueIdentifier,
				.html: html,
				.timestamp: logLine.receivedAt.timeIntervalSince1970,
			]
			renderedLogLines.append(renderedEntry.anyHashableValues)
			if let pluginObject = resultInfo?[LogPresentationResultKey.pluginObject.rawValue]
				as? THOPluginDidPostNewMessageConcreteObject
			{
				pluginObjects.append(pluginObject)
			}
		}
		for pluginObject in pluginObjects {
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
		completionBlock(renderedLogLines)
	}

	private func noteOldestLineCandidate(_ logLine: LogLine?) {
		guard let logLine else {
			return
		}
		if oldestLineStorage == nil || logLine.receivedAt < oldestLineStorage!.receivedAt {
			oldestLineStorage = logLine
		}
	}

	private func noteLocalScrollbackExhausted() {
		guard let channel = associatedChannel, let oldestLineStorage else {
			return
		}
		DispatchQueue.main.async { [weak self] in
			self?.associatedClient.requestChatHistory(before: oldestLineStorage.receivedAt, in: channel)
		}
	}

	func prependHistoricLogLines(_ logLines: [LogLine]) {
		guard !terminating, !logLines.isEmpty else {
			return
		}
		let item = associatedItem
		for logLine in logLines {
			LogControllerHistoricLogFile.shared().indexLogLine(logLine, for: item)
		}
		noteOldestLineCandidate(logLines.first)
		printingQueue.enqueueMessageBlock({ [weak self] _ in
			guard let self else {
				return
			}
			var lineNumbers: [String] = []
			var html = ""
			for logLine in logLines {
				var resultInfo: [AnyHashable: Any]?
				guard let lineHTML = renderLogLine(logLine, resultInfo: &resultInfo) else {
					logControllerLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
					continue
				}
				html += lineHTML
				lineNumbers.append(logLine.uniqueIdentifier)
			}
			guard !lineNumbers.isEmpty else {
				return
			}
			evaluateFunctionNow(
				"_Glasstual.documentBodyPrependRemoteHistory",
				arguments: [html, lineNumbers]
			)
		}, for: self, isStandalone: false)
	}
}

public extension LogController {
	func print(_ logLine: LogLine) {
		print(logLine, completionBlock: nil)
	}

	@objc(print:completionBlock:)
	func print(
		_ inputLogLine: LogLine,
		completionBlock postPrintBlock: LogControllerPrintOperationCompletion?
	) {
		guard !terminating else {
			return
		}
		let logLine: LogLine
		if inputLogLine is MutableLogLine {
			guard let immutableLogLine = inputLogLine.copy() as? LogLine else {
				assertionFailure("MutableLogLine.copy() must return LogLine")
				return
			}
			logLine = immutableLogLine
		} else {
			logLine = inputLogLine
		}
		lastLineStorage = logLine
		noteOldestLineCandidate(logLine)
		printingQueue.enqueueMessageBlock({ [weak self] _ in
			guard let self else {
				return
			}
			var resultInfo: [AnyHashable: Any]?
			guard let html = renderLogLine(logLine, resultInfo: &resultInfo) else {
				logControllerLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
				return
			}
			let lineNumber = logLine.uniqueIdentifier
			let users = resultInfo?[LogRendererResultKey.users.rawValue] as? Set<ChannelUser> ?? []
			let processMedia = (resultInfo?[LogPresentationResultKey.processInlineMedia.rawValue] as? NSNumber)?
				.boolValue ?? false
			let highlighted = (resultInfo?[LogRendererResultKey.keywordMatchFound.rawValue] as? NSNumber)?
				.boolValue ?? false
			let pluginObject = resultInfo?[LogPresentationResultKey.pluginObject.rawValue]
				as? THOPluginDidPostNewMessageConcreteObject
			let transferredValues = LogControllerMainActorTransfer(value: (
				logLine: logLine,
				pluginObject: pluginObject,
				resultInfo: resultInfo,
				postPrintBlock: postPrintBlock
			))
			DispatchQueue.main.async { [weak self] in
				guard let self, !self.terminating else {
					return
				}
				let logLine = transferredValues.value.logLine
				let pluginObject = transferredValues.value.pluginObject
				let resultInfo = transferredValues.value.resultInfo
				let postPrintBlock = transferredValues.value.postPrintBlock
				if oldestLineNumber == nil {
					oldestLineNumber = lineNumber
				}
				newestLineNumber = lineNumber
				let client = associatedClient!
				let channel = associatedChannel
				if highlighted {
					highlightLock.withLock { self.highlightedLineNumbers.append(lineNumber) }
					if let channel, let nativeLogLine = (logLine as AnyObject) as? LogLine {
						client.cacheHighlight(in: channel, with: nativeLogLine)
					}
				}
				if let pluginObject {
					PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
				}
				appendToDocumentBody(html, lineNumbers: [lineNumber])
				if processMedia {
					let links = resultInfo?[LogRendererResultKey.links.rawValue] as? [LinkParserResult] ?? []
					processInlineMedia(links, atLineNumber: lineNumber)
				}
				LogControllerHistoricLogFile.shared().writeNewEntry(with: logLine, for: associatedItem)
				for user in users {
					if logLine.memberType == .localUser {
						user.outgoingConversation()
					} else {
						user.conversation()
					}
				}
				if let postPrintBlock {
					postPrintBlock(LogControllerPrintOperationContext(
						client: client,
						channel: channel,
						highlight: highlighted,
						logLine: logLine,
						lineNumber: lineNumber
					))
				}
			}
		}, for: self, isStandalone: false)
	}

	func noteReaction(
		_ emoji: String,
		fromNickname nickname: String,
		toMessageIdentifier messageIdentifier: String
	) {
		guard !emoji.isEmpty, !nickname.isEmpty, !messageIdentifier.isEmpty else {
			return
		}
		reactionLock.withLock {
			var reactions = reactionsByMessageIdentifier[messageIdentifier] ?? [:]
			var nicknames = reactions[emoji] ?? []
			if !nicknames.contains(nickname) {
				nicknames.append(nickname)
			}
			reactions[emoji] = nicknames
			reactionsByMessageIdentifier[messageIdentifier] = reactions
		}
	}

	func reactionsForMessageIdentifier(_ messageIdentifier: String) -> [String: [String]]? {
		reactionLock.withLock {
			guard let reactions = reactionsByMessageIdentifier[messageIdentifier], !reactions.isEmpty else {
				return nil
			}
			return reactions
		}
	}

	private func reactions(for logLine: LogLine) -> [String: [String]]? {
		let archived = logLine.reactions
		let session = logLine.messageIdentifier.flatMap(reactionsForMessageIdentifier)
		guard let session, !session.isEmpty else {
			return archived
		}
		guard let archived, !archived.isEmpty else {
			return session
		}
		var merged = archived
		for (emoji, nicknames) in session {
			var values = merged[emoji] ?? []
			for nickname in nicknames where !values.contains(nickname) {
				values.append(nickname)
			}
			merged[emoji] = values
		}
		return merged
	}

	private func renderLogLine(
		_ logLine: LogLine,
		resultInfo output: inout [AnyHashable: Any]?
	) -> String? {
		let lineType = logLine.lineType
		let lineTypeString = logLine.lineTypeString ?? ""
		let renderLinks = !LinkParser.bannedLineTypes.contains(lineTypeString)
		var rendererAttributes = LogRendererConfiguration(rawValues: logLine.rendererAttributes ?? [:])
		if let excludeKeywords = logLine.excludeKeywords {
			rendererAttributes[.excludedKeywords] = excludeKeywords
		}
		if let highlightKeywords = logLine.highlightKeywords {
			rendererAttributes[.highlightKeywords] = highlightKeywords
		}
		rendererAttributes[.renderLinks] = renderLinks
		rendererAttributes[.lineType] = lineType.rawValue
		rendererAttributes[.memberType] = logLine.memberType.rawValue

		var rendererResults: NSDictionary?
		let renderedBody = TVCLogRenderer.renderBody(
			logLine.messageBody,
			forViewController: legacyController,
			withAttributes: rendererAttributes.rawValues,
			resultInfo: &rendererResults
		)
		let results = LogRendererResults(rawValues: rendererResults as? [String: Any] ?? [:])
		let highlighted = (results[.keywordMatchFound] as? NSNumber)?
			.boolValue ?? false
		let inlineMedia = inlineMediaEnabledForView && (lineType == .privateMessage || lineType == .action)
		return finishRenderingLogLine(
			logLine,
			renderedBody: renderedBody,
			results: results,
			highlighted: highlighted,
			inlineMedia: inlineMedia,
			output: &output
		)
	}

	private func finishRenderingLogLine(
		_ logLine: LogLine,
		renderedBody: String,
		results: LogRendererResults,
		highlighted: Bool,
		inlineMedia: Bool,
		output: inout [AnyHashable: Any]?
	) -> String? {
		let lineType = logLine.lineType
		let lineTypeString = logLine.lineTypeString ?? ""
		let lineNumber = logLine.uniqueIdentifier
		let receivedAt = logLine.receivedAt
		let activeTheme = SharedApplication.sharedThemeController().theme!

		let lineClass: LogLineClassToken = if lineType == .privateMessage || lineType == .action || lineType ==
			.notice
		{
			.text
		} else {
			.event
		}
		var templateAttributes: ThemeTemplateAttributes = [
			.activeStyleAbsolutePath: baseURL.path(percentEncoded: false),
			.applicationResourcePath: PathInfo.applicationResources,
			.timestamp: receivedAt.timeIntervalSince1970,
			.formattedTimestamp: logLine.formattedTimestamp,
			.localizedTimestamp: formatDateLongStyle(receivedAt, false) ?? "",
			.lineType: lineTypeString,
			.command: logLine.command,
			.rawCommand: logLine.command,
			.lineClassAttribute: lineClass.rawValue,
			.highlightAttribute: String(highlighted),
			.message: logLine.messageBody,
			.formattedMessage: renderedBody,
			.isHighlight: highlighted,
			.isRemoteMessage: logLine.memberType == .normal,
			.inlineMediaEnabled: inlineMedia,
			.lineNumber: lineNumber,
			.lineRenderTime: Date().timeIntervalSince1970,
		]

		let nickname = logLine.formattedNickname(in: associatedChannel)?
			.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
		if nickname.isEmpty {
			templateAttributes[.isNicknameAvailable] = false
		} else {
			templateAttributes[.isNicknameAvailable] = true
			templateAttributes[.nicknameColorStyle] = logLine.nicknameColorStyle
			templateAttributes[.nicknameColorStyleOverride] = logLine.nicknameColorStyleOverride
			templateAttributes[.nicknameColorHashingEnabled] = !TextualPreferences.disableNicknameColorHashing()
			templateAttributes[.formattedNickname] = nickname
			templateAttributes[.nickname] = logLine.nickname ?? ""
			templateAttributes[.nicknameType] = logLine.memberTypeString
		}
		if let messageIdentifier = logLine.messageIdentifier, !messageIdentifier.isEmpty {
			templateAttributes[.messageIdentifier] = messageIdentifier
		}
		if let deliveryState = logLine.deliveryStateString {
			templateAttributes[.deliveryState] = deliveryState
		}
		if let replyIdentifier = logLine.replyToMessageIdentifier, !replyIdentifier.isEmpty {
			templateAttributes[.replyToMessageIdentifier] = replyIdentifier
		}
		if let reactions = reactions(for: logLine),
		   let data = try? JSONEncoder().encode(reactions),
		   let json = String(data: data, encoding: .utf8)
		{
			templateAttributes[.reactionsJSON] = json
		}
		if logLine.isEncrypted {
			templateAttributes[.isEncrypted] = true
		}
		templateAttributes[.configuredServerName] = associatedClient.networkNameAlt
		if logLine.isFirstForDay, TextualPreferences.showDateChanges() {
			templateAttributes[.showDateIndicator] = true
			templateAttributes[.dateIndicatorMessage] = dateIndicator(with: receivedAt)
		}
		if lineNumber == newestLineNumberFromPreviousSession {
			templateAttributes[.showSessionIndicator] = true
			templateAttributes[.sessionIndicatorMessage] = MainWindowStrings.Conversation.currentSession
		}

		var result = results.rawValues
		result[LogPresentationResultKey.processInlineMedia.rawValue] = inlineMedia
		if SharedApplication.sharedPluginManager().supportsFeature(.newMessagePostedEvent) {
			let pluginObject = THOPluginDidPostNewMessageConcreteObject()
			pluginObject.keywordMatchFound = highlighted
			pluginObject.lineTypeRawValue = lineType.rawValue
			pluginObject.memberTypeRawValue = logLine.memberType.rawValue
			pluginObject.senderNickname = logLine.nickname
			pluginObject.receivedAt = receivedAt
			pluginObject.lineNumber = lineNumber
			pluginObject
				.messageContents =
				results.value(for: .bodyWithoutEffects, as: String.self) ?? ""
			pluginObject
				.hyperlinks =
				results.value(for: .links, as: [LinkParserResult].self) ?? []
			pluginObject
				.users = Array(
					results.value(for: .users, as: Set<ChannelUser>.self) ?? []
				)
			result[LogPresentationResultKey.pluginObject.rawValue] = pluginObject
		}
		output = Dictionary(uniqueKeysWithValues: result.map { (AnyHashable($0.key), $0.value) })
		guard let template = activeTheme.template(withLineType: lineType) else {
			return nil
		}
		return TVCLogRenderer.renderTemplate(template, attributes: templateAttributes)
	}

	@MainActor
	private func usesCustomScrollers() -> Bool {
		NSScroller.preferredScrollerStyle != .overlay && TextualPreferences.themeChannelViewUsesCustomScrollers()
	}

	@MainActor
	private func initialDocument() -> String {
		let themeController = SharedApplication.sharedThemeController()
		let activeTheme = themeController.theme!
		let settings = themeController.settings
		var tokens = generateOverrideStyle()
		tokens[.applicationResourcePath] = PathInfo.applicationResources
		tokens[.applicationTemplatesPath] = activeTheme.applicationTemplateRepositoryPath
		tokens[.activeStyleAbsolutePath] = baseURL.path(percentEncoded: false)
		tokens[.activeStyleCSSFiles] = activeTheme.temporaryCSSFilePaths
		tokens[.activeStyleJSFiles] = activeTheme.temporaryJSFilePaths
		tokens[.cacheToken] = themeController.cacheToken
		tokens[.configuredServerName] = associatedClient.networkNameAlt
		tokens[.isReloadingStyle] = reloadingTheme
		tokens[.operatingSystemVersion] = SystemInformation.systemStandardVersion
		let appearance = attachedWindow.userInterfaceObjects
		tokens[.appearanceDescription] = appearance.shortAppearanceDescription
		tokens[.sidebarInversionIsEnabled] = appearance.isDarkAppearance
		tokens[.userConfiguredTextEncoding] = NSString
			.ce_charsetRepresentation(from: associatedClient.config.primaryEncoding)
		tokens[.userStyleSheetRules] = TextualPreferences.themeUserStyleSheetRules()
		tokens[.usesCustomScrollers] = usesCustomScrollers()
		if let channel = associatedChannel {
			tokens[.isChannelView] = channel.isChannel
			tokens[.isPrivateMessageView] = channel.isPrivateMessage
			tokens[.isUtilityView] = channel.isUtility
			tokens[.channelName] = channel.name
			tokens[.viewTypeToken] = channel.channelTypeString
		} else {
			tokens[.viewTypeToken] = ChannelViewTypeToken.server.rawValue
		}
		let textDirection: ChannelViewTextDirectionToken = TextualPreferences.rightToLeftFormatting()
			? .rightToLeft : .leftToRight
		tokens[.textDirectionToken] = textDirection.rawValue
		let appearanceToken: ChannelViewAppearanceToken = settings.underlyingWindowColorIsDark ? .dark : .light
		tokens[.appearanceToken] = appearanceToken.rawValue
		return TVCLogRenderer.renderTemplateNamed(.baseLayout, attributes: tokens) ?? ""
	}

	@MainActor
	private func generateOverrideStyle() -> ThemeTemplateAttributes {
		let settings = SharedApplication.sharedThemeController().settings
		guard let channelFont = settings.themeChannelViewFont ?? TextualPreferences.themeChannelViewFont() else {
			return [:]
		}
		var tokens: ThemeTemplateAttributes = [:]
		if channelFont.fontName.hasPrefix(".") {
			tokens[.userConfiguredFontName] = "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
		} else {
			tokens[.userConfiguredFontName] = "\"\(channelFont.fontName)\""
		}
		tokens[.userConfiguredFontSize] = channelFont.pointSize * (72.0 / 96.0)
		let indentOffset = settings.indentationOffset
		if indentOffset.rounded() < 0 || TextualPreferences.rightToLeftFormatting() {
			tokens[.nicknameIndentationAvailable] = false
		} else {
			tokens[.nicknameIndentationAvailable] = true
			let timeFormat = settings.themeTimestampFormat ?? TextualPreferences.themeTimestampFormat()
			let time = formattedTimestamp(Date() as NSDate, timeFormat as NSString) as String? ?? ""
			let size = (time as NSString).size(withAttributes: [.font: channelFont])
			tokens[.predefinedTimestampWidth] = size.width + indentOffset
		}
		return tokens
	}

	@MainActor func logViewWebViewFinishedLoading() {
		guard !viewIsLoaded,
		      let associatedClient,
		      let attachedWindow
		else {
			return
		}
		withExtendedLifetime((associatedClient, attachedWindow)) {
			viewIsLoaded = true
			viewLoadedTimestamp = Date().timeIntervalSince1970
			let channel = associatedChannel
			let viewType = channel?.channelTypeString ?? ChannelViewTypeToken.server.rawValue
			evaluateFunctionNow("Glasstual.viewInitiated", arguments: [
				viewType,
				associatedClient.uniqueIdentifier,
				channel?.uniqueIdentifier ?? NSNull(),
				channel?.name ?? NSNull(),
			])
			let visibleItem = channel ?? associatedClient
			let state: LogViewState = [
				.selected: attachedWindow.selectedViewController === self,
				.visible: attachedWindow.isItemVisible(visibleItem),
				.reloadingTheme: reloadingTheme,
				.textSizeMultiplier: attachedWindow.textSizeMultiplier,
				.scrollbackLimit: TextualPreferences.scrollbackVisibleLimit(),
			]
			evaluateFunctionNow("_Glasstual.viewFinishedLoading", arguments: [state.rawValues])
			setInitialTopic()
			reloadHistory()
			NotificationCenter.default.post(name: .logControllerViewFinishedLoading, object: self)
			printingQueue.updateReadinessState(for: self)
		}
	}

	func logViewWebViewClosedUnexpectedly() {
		guard !terminating else {
			return
		}
		clear(resetHistoricLog: false)
	}

	func logViewWebViewKeyDown(_ event: NSEvent) {
		let transferredEvent = LogControllerMainActorTransfer(value: event)
		MainActor.assumeIsolated {
			attachedWindow.redirectKeyDown(transferredEvent.value)
		}
	}

	@objc(logViewWebViewReceivedDropWithFile:)
	func logViewWebViewReceivedDrop(withFile filename: String) {
		MainActor.assumeIsolated {
			NSObject.applicationController().menuController?.memberSendDroppedFiles(toSelectedChannel: [filename])
		}
	}

	func lastLine() -> LogLine? {
		lastLineStorage
	}

	func oldestLine() -> LogLine? {
		oldestLineStorage
	}
}

private extension NSLocking {
	@discardableResult
	func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
		lock()
		defer { unlock() }
		return try body()
	}
}
