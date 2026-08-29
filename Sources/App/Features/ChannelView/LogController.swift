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

private nonisolated let logControllerLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogController"
)

/** The controller state that is legitimately read from outside the main actor:
 the client and the channel the view is attached to, and the identifier that
 names it. All three are `Sendable` — two main-actor references and a string —
 and every write happens on the main actor. Everything else the controller owns
 is main-actor state. */
private struct LogControllerSharedState: Sendable {
	weak var client: IRCClient?
	weak var channel: IRCChannel?
	/// The item's identifier, which never changes once the controller is attached.
	var uniqueIdentifier = ""
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

	private nonisolated let sharedState = Mutex(LogControllerSharedState()) // nonisolated: let
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
	private var lastLineStorage: LogLine?
	private var oldestLineStorage: LogLine?

	/** This view's render pipeline, and the task that drains it. Replaced
	 wholesale when the view is cleared: dropping the stream is how queued work
	 is cancelled. */
	private var pipeline = LogRenderPipeline()
	private var pipelineTask: Task<Void, Never>?
	/** Bumped whenever queued work is cancelled. A job that was already
	 rendering checks it before it applies, which is the synchronous half of
	 cancellation — the pipeline drops the rest asynchronously. */
	private var renderGeneration = 0

	public nonisolated var associatedClient: IRCClient! { // nonisolated: pure
		sharedState.withLock { $0.client }
	}

	public nonisolated var associatedChannel: IRCChannel? { // nonisolated: pure
		sharedState.withLock { $0.channel }
	}

	private nonisolated var associatedItem: IRCTreeItem? { // nonisolated: pure
		sharedState.withLock { $0.channel ?? $0.client }
	}

	public nonisolated var uniqueIdentifier: String { // nonisolated: pure
		sharedState.withLock { $0.uniqueIdentifier }
	}

	private var baseURL: URL {
		SharedApplication.sharedThemeController().temporaryURL
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
		sharedState.withLock {
			$0.client = client
			$0.uniqueIdentifier = client.uniqueIdentifier
		}
		attachedWindow = window
		super.init()
		setUp()
	}

	@objc(initWithChannel:inWindow:)
	public init(channel: IRCChannel, in window: TVCMainWindow) {
		sharedState.withLock {
			$0.client = channel.associatedClient
			$0.channel = channel
			$0.uniqueIdentifier = channel.uniqueIdentifier
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
		startPipeline()
		loadInitialDocument()
	}

	private func startPipeline() {
		let pipeline = pipeline
		let viewIsLoaded = viewIsLoaded
		pipelineTask = Task {
			if viewIsLoaded {
				await pipeline.markViewLoaded()
			}
			await pipeline.run()
		}
	}

	private func stopPipeline() {
		let retired = pipeline
		Task { await retired.stop() }
		pipelineTask = nil
	}

	/** Drops everything this view has queued and starts a fresh pipeline.

	 Bumping the generation first is what makes the cancellation take effect
	 immediately: a job that is already rendering finds its generation stale and
	 applies nothing. Retiring the whole pipeline is what drops the jobs that had
	 not started; nothing waits for it. */
	func cancelRenderJobs() {
		guard terminating == false else {
			return
		}
		renderGeneration += 1
		stopPipeline()
		pipeline = LogRenderPipeline()
		startPipeline()
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
		LogControllerHistoricLogFile.shared().forgetView(associatedItem.uniqueIdentifier)
	}

	private func historicLogResetChannel() {
		guard let associatedItem else {
			return
		}
		LogControllerHistoricLogFile.shared().resetData(forView: associatedItem.uniqueIdentifier)
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
		renderGeneration += 1
		terminating = true
		viewIsLoaded = false
		backingView?.stopLoading()
		backingView = nil
		stopPipeline()
		if isTerminatingApplication {
			closeHistoricLog()
		} else {
			historicLogForgetChannel()
		}
	}

	public func prepareForApplicationTermination() {
		/* Bound to a local because the log message is an autoclosure, where
		 `self.` would be required and SwiftFormat would strip it. */
		let identifier = uniqueIdentifier
		logControllerLogger.log("Preparing view controller: \(identifier, privacy: .public)")
		prepareForTermination(true)
	}

	public func prepareForPermanentDestruction() {
		prepareForTermination(false)
	}

	/** Submits one render job to this view's pipeline.

	 `render` runs off the main actor and produces the value `apply` then acts on,
	 on the main actor, in the order the jobs were submitted. That split is what
	 replaced the printing operation: `render` may only capture what can cross
	 isolation, while `apply` is written here, on the main actor, and so may
	 capture a `LogLine`, a caller's completion block or anything else the view
	 needs. Returning `nil` from `render` drops the job.

	 `sending` rather than `Sendable`: a job may produce values that are not
	 `Sendable` — log lines decoded inside the render, for one — as long as it
	 built them itself and keeps no reference, which is exactly what region
	 isolation checks. */
	private func enqueueRenderJob<Output>(
		isStandalone: Bool = false,
		render: @escaping @Sendable @concurrent () async -> sending Output?,
		apply: @escaping @MainActor (sending Output) -> Void
	) {
		guard terminating == false, AppController.shared.applicationIsTerminating == false else {
			return
		}
		let generation = renderGeneration
		pipeline.submissions.yield(LogRenderSubmission(isStandalone: isStandalone) { [weak self] in
			guard let output = await render() else {
				return nil
			}
			return { self?.applyRenderOutput(output, generation: generation, apply) }
		})
	}

	private func applyRenderOutput<Output>(
		_ output: sending Output,
		generation: Int,
		_ apply: @MainActor (sending Output) -> Void
	) {
		guard renderGeneration == generation, terminating == false else {
			return
		}
		apply(output)
	}

	/// Convenience for work that has nothing to do off the main actor. It still
	/// takes its turn in the pipeline, which is what keeps it in order.
	private func enqueueMainActorWork(
		isStandalone: Bool = false,
		_ work: @escaping @MainActor () -> Void
	) {
		enqueueRenderJob(isStandalone: isStandalone, render: { true }, apply: { _ in work() })
	}

	/// Snapshot of the main-actor state that rendering needs.
	private func makeRenderContext() -> LogLineRenderContext {
		let channel = associatedChannel
		return LogLineRenderContext(
			networkName: associatedClient?.networkNameAlt ?? "",
			styleAbsolutePath: baseURL.path(percentEncoded: false),
			inlineMediaEnabled: inlineMediaEnabledForView,
			isChannel: channel?.isChannel == true,
			nicknameFormat: Self.resolvedNicknameFormat(),
			members: (channel?.memberList ?? []).map(RenderedMember.init),
			sessionIndicatorLineNumber: newestLineNumberFromPreviousSession,
			sessionReactions: reactionsByMessageIdentifier
		)
	}

	/// The nickname format the active theme and the preferences resolve to.
	private static func resolvedNicknameFormat() -> String {
		let themeFormat = SharedApplication.sharedThemeController().settings.themeNicknameFormat
		let resolved = themeFormat ?? TextualPreferences.themeNicknameFormat()
		return resolved.isEmpty ? TextualPreferences.themeNicknameFormatDefault() : resolved
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
	public nonisolated func setTopic(_ topic: String?) { // nonisolated: pure
		Task { @MainActor in
			self.setTopicNow(topic)
		}
	}

	private func setTopicNow(_ topic: String?) {
		guard !terminating else {
			return
		}
		let topicString = topic?.isEmpty == false ? topic! : MainWindowStrings.Conversation.noTopic
		enqueueRenderJob(isStandalone: true) { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let body = PluginDispatcher.willRenderMessage(
				topicString,
				forViewController: viewController,
				lineType: .topic,
				memberType: .normal
			)
			let attributes: LogRendererConfiguration = [
				.renderLinks: true,
				.lineType: TVCLogLineType.topic.rawValue,
			]
			return TVCLogRenderer.renderBody(body, withAttributes: attributes.rawValues)
		} apply: { [weak self] (rendered: String) in
			self?.evaluateFunctionNow("Glasstual.setTopicBarValue", arguments: [topicString, rendered])
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
		enqueueRenderJob {
			let attributes: ThemeTemplateAttributes = [
				.historyIndicatorMessage: MainWindowStrings.Conversation.unreadMessages,
			]
			return TVCLogRenderer.renderTemplateNamed(.historyIndicator, attributes: attributes)
		} apply: { [weak self] (template: String) in
			self?.evaluateFunctionNow(function, arguments: [template as Any] + extraArguments)
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
		let channel = associatedChannel
		for result in results {
			html += result.html
			lineNumbers.append(result.lineNumber)
			if let pluginMessage = result.pluginMessage {
				pluginObjects.append(pluginMessage.makeObject(resolvingMembersIn: channel))
			}
			if result.isHighlight {
				highlightedLineNumbers.append(result.lineNumber)
			}
		}
		appendHistoricMessageFragment(html, lineNumbers: lineNumbers, isReload: isReload)
		for var pluginObject in pluginObjects {
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
		if TextualPreferences.loadHistoryLazily(), !viewIsVisible {
			return
		}

		reloadingHistory = true
		fetchHistory(firstLoad: firstLoad)
	}

	private func fetchHistory(firstLoad: Bool) {
		guard let associatedItem else {
			return
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let context = makeRenderContext()
		let limitDate = Date(timeIntervalSince1970: viewLoadedTimestamp)
		let request = HistoricLogFetchRequest(
			viewIdentifier: viewIdentifier,
			kind: .newest(ascending: false, fetchLimit: 100, limitToDate: limitDate)
		)
		/* Everything the render needs is a value, so the fetch is awaited inside
		 the job rather than before it. The pipeline slot stays open until the
		 history has been applied, which is what keeps later prints behind it. */
		enqueueRenderJob(isStandalone: true) { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let xpcEntries = await HistoricLogClient.shared.fetchEntries(request)
			let entries = Array(HistoricLogClient.logLines(from: xpcEntries).reversed())
			let snapshots = Self.applyingMessageRenderers(
				to: entries.map { LogLineSnapshot($0, in: context) },
				for: viewController
			)
			let results = Self.render(snapshots, context: context, using: ThemeLogLineRenderer())
			return (entries: entries, results: results)
		} apply: { [weak self] (loaded: (entries: [LogLine], results: [LogLineRenderResult])) in
			self?.applyReloadedHistory(
				loaded.entries,
				results: loaded.results,
				forView: viewIdentifier,
				firstLoad: firstLoad
			)
		}
	}

	private func applyReloadedHistory(
		_ entries: [LogLine],
		results: [LogLineRenderResult],
		forView viewIdentifier: String,
		firstLoad: Bool
	) {
		LogControllerHistoricLogFile.shared().indexLogLines(entries, forView: viewIdentifier)
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

	func notifyJumpToLine(_ lineNumber: String, successful: Bool) {
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

	nonisolated func processingInlineMediaPayload( // nonisolated: pure
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
		/* The link parser's scheme set is user-extensible, so an address that
		 became clickable is not necessarily one the inline-content service can
		 handle. It only ever fetches over HTTP, and aborts on a file: URL. */
		guard let scheme = URL(string: address)?.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else {
			return
		}

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
		cancelRenderJobs()
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
		let viewIdentifier = associatedItem.uniqueIdentifier
		let kind: HistoricLogFetchRequest.Kind = after
			? .after(uniqueIdentifier: lineNumber, fetchLimit: maximumNumberOfLines, limitToDate: nil)
			: .before(uniqueIdentifier: lineNumber, fetchLimit: maximumNumberOfLines, limitToDate: nil)
		fetchAndRender(
			HistoricLogFetchRequest(viewIdentifier: viewIdentifier, kind: kind),
			completionBlock: completionBlock
		) { controller, entries in
			guard after == false else {
				return
			}
			controller.noteOldestLineCandidate(entries.first)
			if entries.isEmpty {
				controller.noteLocalScrollbackExhausted()
			}
		}
	}

	/** Fetches, indexes and renders one range of scrollback.

	 The fetch is awaited on the main actor — the client queues it behind
	 anything else already asked for this view — and only the render is handed
	 to the printing queue. */
	private func fetchAndRender(
		_ request: HistoricLogFetchRequest,
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void,
		noteFetched: (@MainActor (LogController, [LogLine]) -> Void)? = nil
	) {
		let viewIdentifier = request.viewIdentifier
		Task { @MainActor [weak self] in
			let xpcEntries = await HistoricLogClient.shared.fetchEntries(request)
			guard let self else {
				return
			}
			let entries = LogControllerHistoricLogFile.shared()
				.decodeAndIndex(xpcEntries, forView: viewIdentifier)
			noteFetched?(self, entries)
			renderFetchedLogLines(entries, completionBlock: completionBlock)
		}
	}

	private func renderFetchedLogLines(
		_ logLines: [LogLine],
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		let context = makeRenderContext()
		let lines = logLines.map { LogLineSnapshot($0, in: context) }
		enqueueRenderJob(isStandalone: true) { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let snapshots = Self.applyingMessageRenderers(to: lines, for: viewController)
			return Self.render(snapshots, context: context, using: ThemeLogLineRenderer())
		} apply: { [weak self] (results: [LogLineRenderResult]) in
			self?.applyFetchedRender(results, completionBlock: completionBlock)
		}
	}

	/// Hands a rendered scrollback page to the caller that asked for it and
	/// tells the plugins about the lines it carried.
	private func applyFetchedRender(
		_ results: [LogLineRenderResult],
		completionBlock: @escaping ([[AnyHashable: Any]]) -> Void
	) {
		let channel = associatedChannel
		for pluginMessage in results.compactMap(\.pluginMessage) {
			var pluginObject = pluginMessage.makeObject(resolvingMembersIn: channel)
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
		completionBlock(results.map { result in
			let entry: RenderedLogEntry = [
				.lineNumber: result.lineNumber,
				.html: result.html,
				.timestamp: result.timestamp,
			]
			return entry.anyHashableValues
		})
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
		fetchAndRender(
			HistoricLogFetchRequest(
				viewIdentifier: associatedItem.uniqueIdentifier,
				kind: .between(
					afterUniqueIdentifier: lineNumberAfter,
					beforeUniqueIdentifier: lineNumberBefore,
					fetchLimit: maximumNumberOfLines
				)
			),
			completionBlock: completionBlock
		)
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
		fetchAndRender(
			HistoricLogFetchRequest(
				viewIdentifier: associatedItem.uniqueIdentifier,
				kind: .around(
					uniqueIdentifier: lineNumber,
					before: numberOfLinesBefore,
					after: numberOfLinesAfter,
					limitToDate: nil
				)
			),
			completionBlock: completionBlock
		)
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
		LogControllerHistoricLogFile.shared().indexLogLines(logLines, forView: associatedItem.uniqueIdentifier)
		noteOldestLineCandidate(logLines.first)
		let context = makeRenderContext()
		let lines = logLines.map { LogLineSnapshot($0, in: context) }
		enqueueRenderJob { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let snapshots = Self.applyingMessageRenderers(to: lines, for: viewController)
			let results = Self.render(snapshots, context: context, using: ThemeLogLineRenderer())
			guard results.isEmpty == false else {
				return nil
			}
			return (html: results.map(\.html).joined(), lineNumbers: results.map(\.lineNumber))
		} apply: { [weak self] (prepended: (html: String, lineNumbers: [String])) in
			self?.evaluateFunctionNow(
				"_Glasstual.documentBodyPrependRemoteHistory",
				arguments: [prepended.html, prepended.lineNumbers]
			)
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
		/* A snapshot: the caller still holds the line it handed over, and rendering
		 continues off the main actor after this returns. */
		let logLine = inputLogLine.duplicate()
		lastLineStorage = logLine
		noteOldestLineCandidate(logLine)
		let context = makeRenderContext()
		let line = LogLineSnapshot(logLine, in: context)
		enqueueRenderJob { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let request = LogLineRenderRequest(
				line: Self.applyingMessageRenderers(to: [line], for: viewController)[0],
				context: context
			)
			guard let result = Self.render(request, using: ThemeLogLineRenderer()) else {
				logControllerLogger
					.error("Failed to render log line \(request.line.sourceDescription, privacy: .public)")
				return nil
			}
			return result
		} apply: { [weak self] result in
			self?.applyPrintedLine(logLine, result: result, completionBlock: postPrintBlock)
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
		if let pluginMessage = result.pluginMessage {
			PluginDispatcher.enqueueDidPostNewMessage(pluginMessage.makeObject(resolvingMembersIn: channel))
		}
		appendToDocumentBody(result.html, lineNumbers: [lineNumber])
		if result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: lineNumber)
		}
		LogControllerHistoricLogFile.shared().writeNewEntry(with: logLine, forView: associatedItem.uniqueIdentifier)
		/* The body was scanned against the member snapshot the line rendered
		 with; the conversation weight belongs to whoever is in the channel now. */
		for member in result.mentionedNicknames.compactMap({ channel?.findMember($0) }) {
			if logLine.memberType == .localUser {
				member.outgoingConversation()
			} else {
				member.conversation()
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
		let settings: ThemeSettings = themeController.settings
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
		tokens[.userConfiguredTextEncoding] = String.Encoding
			.ianaCharsetName(forRawValue: associatedClient.config.primaryEncoding)
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
		let appearanceToken: ThemeAppearanceToken = settings.underlyingWindowColorIsDark ? .dark : .light
		tokens[.appearanceToken] = appearanceToken.rawValue
		return TVCLogRenderer.renderTemplateNamed(.baseLayout, attributes: tokens) ?? ""
	}

	private func generateOverrideStyle() -> ThemeTemplateAttributes {
		let settings: ThemeSettings = SharedApplication.sharedThemeController().settings
		guard let channelFont = settings.themeChannelViewFont ?? TextualPreferences.themeChannelViewFont() else {
			return [:]
		}
		var tokens: ThemeTemplateAttributes = [:]
		if channelFont.fontName.hasPrefix(".") {
			tokens[.userConfiguredFontName] = "-apple-system, BlinkMacSystemFont, system-ui, sans-serif"
		} else {
			tokens[.userConfiguredFontName] = LogViewContentPolicy.cssStringLiteral(channelFont.fontName)
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
			/* Releases the jobs the pipeline has been holding: everything queued
			 before the web view finished loading waits for this. */
			let pipeline = pipeline
			Task { await pipeline.markViewLoaded() }
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
		AppController.shared.menuController?.memberSendDroppedFiles(toSelectedChannel: [filename])
	}

	/// The newest line this view printed. The IRC layer consults it when it
	/// decides what history to ask the server for.
	func lastLine() -> LogLine? {
		lastLineStorage
	}
}
