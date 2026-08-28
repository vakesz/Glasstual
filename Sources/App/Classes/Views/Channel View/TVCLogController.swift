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
import Synchronization

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
/// explicit hops between the main actor and the printing queue. The values are
/// only ever touched at one end of a hop at a time.
private final class LogControllerMainActorTransfer<Value>: @unchecked Sendable {
	let value: Value

	init(value: Value) {
		self.value = value
	}
}

/// The work a printing operation produces off the main actor and hands back to
/// it. Building the closure off-main is safe; only running it is isolated.
private typealias LogControllerMainActorWork = LogControllerMainActorTransfer<@MainActor () -> Void>

/// The controller state that is legitimately read from outside the main actor:
/// the client and channel the renderer needs while it runs on the printing
/// queue, and the newest and oldest line the IRC layer consults when it decides
/// what history to ask the server for. Everything else the controller owns is
/// main-actor state. Writes all happen on the main actor; the lock is what makes
/// the reads safe.
private struct LogControllerSharedState {
	weak var client: IRCClient?
	weak var channel: IRCChannel?
	var lastLine: LogControllerMainActorTransfer<LogLine>?
	var oldestLine: LogControllerMainActorTransfer<LogLine>?
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
@MainActor
public final class LogController: NSObject {
	public private(set) var backingView: LogView!
	public private(set) var viewIsLoaded = false
	public private(set) weak var attachedWindow: TVCMainWindow!
	public private(set) var newestLineNumberFromPreviousSession: String?
	public private(set) var oldestLineNumber: String?
	public private(set) var newestLineNumber: String?

	private nonisolated let sharedState = Mutex(LogControllerSharedState())
	private var terminating = false
	private var historyLoadedForFirstTime = false
	private var reloadingHistory = false
	private var reloadingTheme = false
	private var historyLoaded = false
	private var activeLineCount = 0
	private var lastVisitedHighlight: String?
	private var highlightedLineNumbers: [String] = []
	private var jumpToLineCallbacks: [String: (Bool) -> Void] = [:]
	private var reactionsByMessageIdentifier: [String: [String: [String]]] = [:]
	private var viewLoadedTimestamp: TimeInterval = 0

	public nonisolated var associatedClient: IRCClient! {
		sharedState.withLock { $0.client }
	}

	public nonisolated var associatedChannel: IRCChannel? {
		sharedState.withLock { $0.channel }
	}

	private nonisolated var associatedItem: IRCTreeItem? {
		sharedState.withLock { $0.channel ?? $0.client }
	}

	private var lastLineStorage: LogLine? {
		get { sharedState.withLock { $0.lastLine?.value } }
		set { sharedState.withLock { $0.lastLine = newValue.map(LogControllerMainActorTransfer.init) } }
	}

	private var oldestLineStorage: LogLine? {
		get { sharedState.withLock { $0.oldestLine?.value } }
		set { sharedState.withLock { $0.oldestLine = newValue.map(LogControllerMainActorTransfer.init) } }
	}

	private nonisolated var legacyController: TVCLogController {
		self
	}

	public nonisolated var uniqueIdentifier: String {
		associatedItem?.uniqueIdentifier ?? ""
	}

	private nonisolated var baseURL: URL {
		SharedApplication.sharedThemeController().temporaryURL
	}

	private var printingQueue: LogControllerPrintingOperationQueue {
		SharedApplication.sharedPrintingQueue()
	}

	public var numberOfLines: UInt {
		UInt(max(activeLineCount, 0))
	}

	public nonisolated var inlineMediaEnabledForView: Bool {
		guard let channel = associatedChannel else {
			return false
		}
		let config = channel.config
		return TextualPreferences.showInlineMedia() ? !config.inlineMediaDisabled : config.inlineMediaEnabled
	}

	public var viewIsSelected: Bool {
		attachedWindow.selectedViewController === self
	}

	public var viewIsVisible: Bool {
		guard let attachedWindow else {
			return false
		}
		if let associatedChannel {
			return attachedWindow.isItemVisible(associatedChannel)
		}
		guard let associatedClient else {
			return false
		}
		return attachedWindow.isItemVisible(associatedClient)
	}

	@available(*, unavailable, message: "Use init(client:in:) or init(channel:in:)")
	override public init() {
		fatalError("Use a designated log controller initializer")
	}

	@objc(initWithClient:inWindow:)
	public init(client: IRCClient, in window: TVCMainWindow) {
		sharedState.withLock { $0.client = client }
		attachedWindow = window
		super.init()
		setUp()
	}

	@objc(initWithChannel:inWindow:)
	public init(channel: IRCChannel, in window: TVCMainWindow) {
		sharedState.withLock {
			$0.client = channel.associatedClient
			$0.channel = channel
		}
		attachedWindow = window
		super.init()
		setUp()
	}

	deinit {
		NSObject.cancelPreviousPerformRequests(withTarget: self)
	}

	private func setUp() {
		backingView = LogView(viewController: self)
		loadInitialDocument()
	}

	private func loadInitialDocument() {
		loadAlternateHTML(initialDocument())
	}

	private func loadAlternateHTML(_ html: String) {
		backingView.stopLoading()
		backingView.loadHTMLString(html, baseURL: baseURL)
	}

	private func historicLogForgetChannel() {
		guard let associatedItem else {
			return
		}
		LogControllerHistoricLogFile.shared().forgetItem(associatedItem)
	}

	private func historicLogResetChannel() {
		guard let associatedItem else {
			return
		}
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
		backingView?.stopLoading()
		backingView = nil
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

	/// Schedules `work` on the printing queue. `work` runs off the main actor
	/// and returns the closure that applies its result; the operation is not
	/// finished — and so the next operation for this controller does not start —
	/// until that closure has run. That is what keeps the JavaScript this
	/// controller evaluates in the order it was enqueued.
	private func enqueuePrintingWork(
		isStandalone: Bool = false,
		_ work: @escaping (LogControllerPrintingOperation) -> LogControllerMainActorWork?
	) {
		printingQueue.enqueueAsynchronousMessageBlock({ operation in
			let scheduled = work(operation)
			Task { @MainActor in
				defer { operation.finish() }
				guard operation.isCancelled == false else {
					return
				}
				scheduled?.value()
			}
		}, for: self, isStandalone: isStandalone)
	}

	/// Convenience for work that has nothing to do off the main actor.
	private func enqueueMainActorWork(
		isStandalone: Bool = false,
		_ work: @escaping @MainActor () -> Void
	) {
		enqueuePrintingWork(isStandalone: isStandalone) { _ in
			LogControllerMainActorTransfer(value: work)
		}
	}

	/// Snapshot of the main-actor state that rendering needs.
	private func makeRenderContext() -> LogLineRenderContext {
		LogLineRenderContext(
			channel: associatedChannel,
			networkName: associatedClient?.networkNameAlt ?? "",
			styleAbsolutePath: baseURL.path(percentEncoded: false),
			inlineMediaEnabled: inlineMediaEnabledForView,
			sessionIndicatorLineNumber: newestLineNumberFromPreviousSession,
			sessionReactions: reactionsByMessageIdentifier
		)
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
			enqueueMainActorWork { [weak self] in
				self?.evaluateFunctionNow(function, arguments: arguments)
			}
		} else {
			evaluateFunctionNow(function, arguments: arguments)
		}
	}

	/// The controller's single path to the log view's JavaScript bridge. Every
	/// caller is already on the main actor, so calls reach the view in order.
	private func evaluateFunctionNow(_ function: String, arguments: [Any]?) {
		guard viewIsLoaded, !terminating, let backingView else {
			return
		}
		backingView.evaluateFunction(function, withArguments: arguments)
	}

	private func appendToDocumentBody(_ html: String, lineNumbers: [String]) {
		evaluateFunctionNow("MessageBuffer.bufferElementAppend", arguments: [html, lineNumbers])
	}

	private func setInitialTopic() {
		setTopicNow(associatedChannel?.topic)
	}

	/// `IRCChannel` publishes topic changes from a property observer that is not
	/// isolated, so hop before touching any of the controller's state.
	public nonisolated func setTopic(_ topic: String?) {
		Task { @MainActor in
			self.setTopicNow(topic)
		}
	}

	private func setTopicNow(_ topic: String?) {
		guard !terminating else {
			return
		}
		let topicString = topic?.isEmpty == false ? topic! : MainWindowStrings.Conversation.noTopic
		enqueuePrintingWork(isStandalone: true) { [weak self] _ in
			guard let self else {
				return nil
			}
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
			return LogControllerMainActorTransfer(value: { [weak self] in
				self?.evaluateFunctionNow("Glasstual.setTopicBarValue", arguments: [topicString, rendered])
			})
		}
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
		enqueuePrintingWork { [weak self] _ in
			let attributes: ThemeTemplateAttributes = [
				.historyIndicatorMessage: MainWindowStrings.Conversation.unreadMessages,
			]
			let template = TVCLogRenderer.renderTemplateNamed(.historyIndicator, attributes: attributes)
			let arguments = [template as Any] + extraArguments
			return LogControllerMainActorTransfer(value: {
				self?.evaluateFunctionNow(function, arguments: arguments)
			})
		}
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

	private func applyReloadedLines(_ results: [LogLineRenderResult], isReload: Bool) {
		var lineNumbers: [String] = []
		var html = ""
		var pluginObjects: [THOPluginDidPostNewMessageConcreteObject] = []
		for result in results {
			html += result.html
			lineNumbers.append(result.lineNumber)
			if let pluginObject = result.pluginObject {
				pluginObjects.append(pluginObject)
			}
			if result.isHighlight {
				highlightedLineNumbers.append(result.lineNumber)
			}
		}
		appendHistoricMessageFragment(html, lineNumbers: lineNumbers, isReload: isReload)
		for pluginObject in pluginObjects {
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
	}

	private func maybeReloadHistory() {
		guard viewIsLoaded, !historyLoaded else {
			return
		}
		reloadHistory()
	}

	private func reloadHistory() {
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
		fetchHistory(firstLoad: firstLoad)
	}

	private func fetchHistory(firstLoad: Bool) {
		guard let associatedItem else {
			return
		}
		let context = makeRenderContext()
		let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
		printingQueue.enqueueAsynchronousMessageBlock({ [weak self] operation in
			guard let self else {
				operation.finish()
				return
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				ascending: false,
				fetchLimit: 100,
				limitToDate: limitDate
			) { entries in
				guard operation.isCancelled == false else {
					operation.finish()
					return
				}
				let entries = Array(entries.reversed())
				let results = Self.render(entries, context: context, using: renderer)
				let transfer = LogControllerMainActorTransfer(value: (entries: entries, results: results))
				Task { @MainActor [weak self] in
					defer { operation.finish() }
					self?.applyReloadedHistory(
						transfer.value.entries,
						results: transfer.value.results,
						firstLoad: firstLoad
					)
				}
			}
		}, for: self, isStandalone: true)
	}

	private func applyReloadedHistory(
		_ entries: [LogLine],
		results: [LogLineRenderResult],
		firstLoad: Bool
	) {
		if lastLineStorage == nil {
			lastLineStorage = entries.last
		}
		noteOldestLineCandidate(entries.first)
		if firstLoad {
			newestLineNumberFromPreviousSession = entries.last?.uniqueIdentifier
		}
		applyReloadedLines(results, isReload: !firstLoad)
		reloadingHistory = false
		historyLoaded = true
		historyLoadedForFirstTime = true
		notifyViewFinishedLoadingHistory()
	}
}

public extension LogController {
	func reloadTheme() {
		reloadThemeNow()
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

	private nonisolated func dateIndicator(with date: Date) -> String {
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
			jumpToLineCallbacks[lineNumber] = completionHandler
		}
		guard let backingView else {
			return
		}
		backingView.evaluateFunction("Glasstual.jumpToLine", withArguments: [lineNumber])
	}

	func notifyDidBecomeVisible() {
		evaluateFunctionNow("_Glasstual.notifyDidBecomeVisible", arguments: nil)
		maybeReloadHistory()
	}

	func notifyDidBecomeHidden() {
		evaluateFunctionNow("_Glasstual.notifyDidBecomeHidden", arguments: nil)
	}

	func notifySelectionChanged() {
		evaluateFunctionNow("_Glasstual.notifySelectionChanged", arguments: [viewIsSelected])
	}

	private func notifyViewFinishedLoadingHistory() {
		evaluateFunctionNow("_Glasstual.viewFinishedLoadingHistory", arguments: nil)
	}

	func changeTextSize(_ bigger: Bool) {
		evaluateFunctionNow("Glasstual.changeTextSizeMultiplier", arguments: [attachedWindow.textSizeMultiplier])
		evaluateFunctionNow("Glasstual.viewFontSizeChanged", arguments: [bigger])
	}

	func changeScrollbackLimit() {
		evaluateFunctionNow("_MessageBuffer.setBufferLimit", arguments: [TextualPreferences.scrollbackVisibleLimit()])
	}

	func notifyJumpToLine(_ lineNumber: String, successful: Bool, scrolledToBottom _: Bool) {
		let callback = jumpToLineCallbacks.removeValue(forKey: lineNumber)
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
		highlightedLineNumbers.removeAll { lineNumbers.contains($0) }
	}

	func processingInlineMediaPayloadSucceeded(_ payload: InlineContentPayload) {
		evaluateFunctionNow("_InlineMediaLoader.processPayload", arguments: [payload.javaScriptObject])
	}

	nonisolated func processingInlineMediaPayload(
		_ payload: InlineContentPayload,
		failedWithError error: Error
	) {
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
		guard let associatedItem else {
			return
		}
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
		return !highlightedLineNumbers.isEmpty
	}

	func nextHighlight() {
		visitHighlight(offset: 1)
	}

	func previousHighlight() {
		visitHighlight(offset: -1)
	}

	private func visitHighlight(offset: Int) {
		guard viewIsLoaded, !terminating, !highlightedLineNumbers.isEmpty else {
			return
		}
		let current = lastVisitedHighlight.flatMap(highlightedLineNumbers.firstIndex(of:))
		let index = current.map { ($0 + offset + highlightedLineNumbers.count) % highlightedLineNumbers.count } ?? 0
		let target = highlightedLineNumbers[index]
		lastVisitedHighlight = target
		jump(toLine: target)
	}

	private func clear(resetHistoricLog: Bool) {
		guard !terminating else {
			return
		}
		printingQueue.cancelOperations(for: self)
		if resetHistoricLog {
			historicLogResetChannel()
		}
		highlightedLineNumbers.removeAll()
		activeLineCount = 0
		lastVisitedHighlight = nil
		oldestLineNumber = nil
		newestLineNumber = nil
		lastLineStorage = nil
		oldestLineStorage = nil
		viewIsLoaded = false
		reloadingHistory = false
		historyLoaded = false
		loadInitialDocument()
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
		guard let associatedItem else {
			return
		}
		let context = makeRenderContext()
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			let historicLog = LogControllerHistoricLogFile.shared()
			let completion: ([LogLine]) -> Void = { [weak self] entries in
				self?.finishRendering(
					entries,
					context: context,
					renderer: renderer,
					operation: operation,
					completionBlock: completionBlock
				)
			}
			if after {
				historicLog.fetchEntries(
					for: associatedItem,
					afterUniqueIdentifier: lineNumber,
					fetchLimit: maximumNumberOfLines,
					limitToDate: nil,
					withCompletionBlock: completion
				)
			} else {
				historicLog.fetchEntries(
					for: associatedItem,
					beforeUniqueIdentifier: lineNumber,
					fetchLimit: maximumNumberOfLines,
					limitToDate: nil
				) { [weak self] entries in
					guard let self, operation.isCancelled == false else {
						return
					}
					let transfer = LogControllerMainActorTransfer(value: entries)
					Task { @MainActor [weak self] in
						self?.noteOldestLineCandidate(transfer.value.first)
						if transfer.value.isEmpty {
							self?.noteLocalScrollbackExhausted()
						}
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
		guard let associatedItem else {
			return
		}
		let context = makeRenderContext()
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				afterUniqueIdentifier: lineNumberAfter,
				beforeUniqueIdentifier: lineNumberBefore,
				fetchLimit: maximumNumberOfLines
			) { [weak self] entries in
				self?.finishRendering(
					entries,
					context: context,
					renderer: renderer,
					operation: operation,
					completionBlock: completionBlock
				)
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
		guard let associatedItem else {
			return
		}
		let context = makeRenderContext()
		printingQueue.enqueueMessageBlock({ [weak self] operation in
			guard let self else {
				return
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			LogControllerHistoricLogFile.shared().fetchEntries(
				for: associatedItem,
				withUniqueIdentifier: lineNumber,
				beforeFetchLimit: numberOfLinesBefore,
				afterFetchLimit: numberOfLinesAfter,
				limitToDate: nil
			) { [weak self] entries in
				self?.finishRendering(
					entries,
					context: context,
					renderer: renderer,
					operation: operation,
					completionBlock: completionBlock
				)
			}
		}, for: self, isStandalone: true)
	}

	/// Renders `logLines` off the main actor and delivers them back on it.
	private nonisolated func finishRendering(
		_ logLines: [LogLine],
		context: LogLineRenderContext,
		renderer: ThemeLogLineRenderer,
		operation: LogControllerPrintingOperation,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		guard operation.isCancelled == false else {
			return
		}
		let results = Self.render(logLines, context: context, using: renderer)
		let renderedLogLines = results.map { result -> [AnyHashable: Any] in
			let entry: RenderedLogEntry = [
				.lineNumber: result.lineNumber,
				.html: result.html,
				.timestamp: result.timestamp,
			]
			return entry.anyHashableValues
		}
		let transfer = LogControllerMainActorTransfer(value: (
			results: results,
			renderedLogLines: renderedLogLines,
			completionBlock: completionBlock
		))
		Task { @MainActor in
			for pluginObject in transfer.value.results.compactMap(\.pluginObject) {
				pluginObject.isProcessedInBulk = true
				PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
			}
			transfer.value.completionBlock(transfer.value.renderedLogLines)
		}
	}

	private func noteOldestLineCandidate(_ logLine: LogLine?) {
		guard let logLine else {
			return
		}
		guard let oldestLineStorage else {
			oldestLineStorage = logLine
			return
		}
		if logLine.receivedAt < oldestLineStorage.receivedAt {
			self.oldestLineStorage = logLine
		}
	}

	private func noteLocalScrollbackExhausted() {
		guard let channel = associatedChannel,
		      let client = associatedClient,
		      let oldestLineStorage
		else {
			return
		}
		client.requestChatHistory(before: oldestLineStorage.receivedAt, in: channel)
	}

	func prependHistoricLogLines(_ logLines: [LogLine]) {
		guard !terminating, !logLines.isEmpty, let associatedItem else {
			return
		}
		for logLine in logLines {
			LogControllerHistoricLogFile.shared().indexLogLine(logLine, for: associatedItem)
		}
		noteOldestLineCandidate(logLines.first)
		let context = makeRenderContext()
		enqueuePrintingWork { [weak self] _ in
			guard let self else {
				return nil
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			let results = Self.render(logLines, context: context, using: renderer)
			guard results.isEmpty == false else {
				return nil
			}
			let html = results.map(\.html).joined()
			let lineNumbers = results.map(\.lineNumber)
			return LogControllerMainActorTransfer(value: { [weak self] in
				self?.evaluateFunctionNow(
					"_Glasstual.documentBodyPrependRemoteHistory",
					arguments: [html, lineNumbers]
				)
			})
		}
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
		let request = LogLineRenderRequest(logLine: logLine, context: makeRenderContext())
		enqueuePrintingWork { [weak self] _ in
			guard let self else {
				return nil
			}
			let renderer = ThemeLogLineRenderer(viewController: self)
			guard let result = Self.render(request, using: renderer) else {
				logControllerLogger.error("Failed to render log line \(logLine.description, privacy: .public)")
				return nil
			}
			return LogControllerMainActorTransfer(value: { [weak self] in
				self?.applyPrintedLine(logLine, result: result, completionBlock: postPrintBlock)
			})
		}
	}

	private func applyPrintedLine(
		_ logLine: LogLine,
		result: LogLineRenderResult,
		completionBlock postPrintBlock: LogControllerPrintOperationCompletion?
	) {
		guard !terminating else {
			return
		}
		/* The client can be torn down between enqueueing the line and printing
		 it; there is nothing left to attribute the line to if it has been. */
		guard let client = associatedClient, let associatedItem else {
			return
		}
		let lineNumber = result.lineNumber
		let channel = associatedChannel
		if oldestLineNumber == nil {
			oldestLineNumber = lineNumber
		}
		newestLineNumber = lineNumber
		if result.isHighlight {
			highlightedLineNumbers.append(lineNumber)
			if let channel {
				client.cacheHighlight(in: channel, with: logLine)
			}
		}
		if let pluginObject = result.pluginObject {
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
		appendToDocumentBody(result.html, lineNumbers: [lineNumber])
		if result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: lineNumber)
		}
		LogControllerHistoricLogFile.shared().writeNewEntry(with: logLine, for: associatedItem)
		for user in result.users {
			if logLine.memberType == .localUser {
				user.outgoingConversation()
			} else {
				user.conversation()
			}
		}
		postPrintBlock?(LogControllerPrintOperationContext(
			client: client,
			channel: channel,
			highlight: result.isHighlight,
			logLine: logLine,
			lineNumber: lineNumber
		))
	}

	func noteReaction(
		_ emoji: String,
		fromNickname nickname: String,
		toMessageIdentifier messageIdentifier: String
	) {
		guard !emoji.isEmpty, !nickname.isEmpty, !messageIdentifier.isEmpty else {
			return
		}
		var reactions = reactionsByMessageIdentifier[messageIdentifier] ?? [:]
		var nicknames = reactions[emoji] ?? []
		if !nicknames.contains(nickname) {
			nicknames.append(nickname)
		}
		reactions[emoji] = nicknames
		reactionsByMessageIdentifier[messageIdentifier] = reactions
	}

	func reactionsForMessageIdentifier(_ messageIdentifier: String) -> [String: [String]]? {
		guard let reactions = reactionsByMessageIdentifier[messageIdentifier], !reactions.isEmpty else {
			return nil
		}
		return reactions
	}
}

public extension LogController {
	private func usesCustomScrollers() -> Bool {
		NSScroller.preferredScrollerStyle != .overlay && TextualPreferences.themeChannelViewUsesCustomScrollers()
	}

	private func initialDocument() -> String {
		let themeController = SharedApplication.sharedThemeController()
		guard let activeTheme = themeController.theme, let associatedClient else {
			return ""
		}
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

	func logViewWebViewFinishedLoading() {
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
		attachedWindow?.redirectKeyDown(event)
	}

	@objc(logViewWebViewReceivedDropWithFile:)
	func logViewWebViewReceivedDrop(withFile filename: String) {
		NSObject.applicationController().menuController?.memberSendDroppedFiles(toSelectedChannel: [filename])
	}

	nonisolated func lastLine() -> LogLine? {
		sharedState.withLock { $0.lastLine?.value }
	}

	nonisolated func oldestLine() -> LogLine? {
		sharedState.withLock { $0.oldestLine?.value }
	}
}
