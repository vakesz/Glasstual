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
import os
import Synchronization

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

@MainActor
public final class LogController: NSObject, ServerHistoryPresentation {
	public private(set) var backingView: LogView?
	public private(set) var viewIsLoaded = false
	public private(set) weak var attachedWindow: MainWindow?
	public internal(set) var newestLineNumberFromPreviousSession: String?
	public var oldestLineNumber: String? {
		backingView?.displayedBounds.oldest
	}

	public var newestLineNumber: String? {
		backingView?.displayedBounds.newest
	}

	private nonisolated let sharedState = Mutex(LogControllerSharedState()) // nonisolated: let
	private(set) var terminating = false
	/* Loading history is the other half of this controller, and it lives in
	 `LogControllerHistoryLoading.swift`: the initial replay, the scrollback
	 pages and the server-history handshake. The state the two halves share is
	 declared here and reaches no further than this feature. */
	var historyLoadedForFirstTime = false
	var reloadingHistory = false
	var historyLoaded = false
	var historyLoadFailure: HistoricLogFetchFailure? {
		didSet { historyRecovery.initialFailure = historyLoadFailure }
	}

	var loadingOlderHistory = false
	var olderHistoryTask: Task<Void, Never>?
	var locallyExhaustedBefore: String?
	var serverHistoryRequest: ServerHistoryRequest? {
		didSet { refreshServerRetryAvailability() }
	}

	var serverHistoryCompletedBefore: Date?
	var serverHistoryExhaustedBefore: Date?
	var serverHistoryFailed = false {
		didSet {
			historyRecovery.serverFailed = serverHistoryFailed
			if !serverHistoryFailed {
				historyRecovery.serverFailureReason = nil
			}
			refreshServerRetryAvailability()
		}
	}

	var olderHistoryFailure: HistoricLogFetchFailure? {
		didSet { historyRecovery.olderFailure = olderHistoryFailure }
	}

	let historyRecovery = TranscriptHistoryRecoveryState()
	var historyStorageRecovery: TranscriptHistoryRecoveryState {
		historicLog.recovery
	}

	var historyRetryTask: Task<Void, Never>?
	var olderHistoryFailed: Bool {
		olderHistoryFailure != nil
	}

	var historyPageFetcher: @Sendable @concurrent (HistoricLogFetchRequest) async
		-> HistoricLogFetchOutcome

	private let memberRenderCache = MemberListRenderCache()
	let inlineImageLoader: NativeInlineImageLoader
	let historicLog: LogControllerHistoricLogFile
	private(set) var historicLogMutationTask: Task<Void, Never>?

	private var lastVisitedHighlight: String?
	private var highlightedLineNumbers: [String] {
		backingView?.displayedLines.filter(\.body.isHighlight).map(\.lineNumber) ?? []
	}

	private(set) var reactionsByMessageIdentifier: [String: [String: [String]]] = [:]
	private(set) var viewLoadedTimestamp: TimeInterval = 0
	var lastLineStorage: LogLine?
	var transcriptProjection = TranscriptProjectionState()
	var transcriptSessionBoundary = TranscriptSessionBoundaryState()

	/** This view's render pipeline, and the task that drains it. Replaced
	 wholesale when the view is cleared: dropping the stream is how queued work
	 is cancelled. */
	private var pipeline = LogRenderPipeline()
	private var pipelineTask: Task<Void, Never>?
	/** Bumped whenever queued work is cancelled. A job that was already
	 rendering checks it before it applies, which is the synchronous half of
	 cancellation — the pipeline drops the rest asynchronously. */
	private(set) var renderGeneration = 0
	var pendingApplications: [@MainActor () -> Void] = []
	var deferredPrepends: [@MainActor () -> Void] = []
	private var applicationTask: Task<Void, Never>?

	public nonisolated var associatedClient: IRCClient! { // nonisolated: pure
		sharedState.withLock { $0.client }
	}

	public nonisolated var associatedChannel: IRCChannel? { // nonisolated: pure
		sharedState.withLock { $0.channel }
	}

	nonisolated var associatedItem: IRCTreeItem? { // nonisolated: pure
		sharedState.withLock { $0.channel ?? $0.client }
	}

	public nonisolated var uniqueIdentifier: String { // nonisolated: pure
		sharedState.withLock { $0.uniqueIdentifier }
	}

	public var numberOfLines: UInt {
		UInt(backingView?.displayedBounds.count ?? transcriptProjection.lineCount)
	}

	public var inlineMediaEnabledForView: Bool {
		guard let channel = associatedChannel else {
			return false
		}
		let config = channel.config
		return Preferences.Messages.showInlineMedia.detachedValue ? !config.inlineMediaDisabled : config
			.inlineMediaEnabled
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

	public convenience init(client: IRCClient, in window: MainWindow) {
		self.init(client: client, in: window, inlineImageLoader: .shared)
	}

	init(
		client: IRCClient, in window: MainWindow, inlineImageLoader: NativeInlineImageLoader,
		historicLog: LogControllerHistoricLogFile = .sharedInstance
	) {
		self.inlineImageLoader = inlineImageLoader
		self.historicLog = historicLog
		historyPageFetcher = { await historicLog.fetchOutcome($0) }
		sharedState.withLock {
			$0.client = client
			$0.uniqueIdentifier = client.uniqueIdentifier
		}
		attachedWindow = window
		super.init()
		setUp()
	}

	public init(channel: IRCChannel, in window: MainWindow) {
		inlineImageLoader = .shared
		historicLog = .sharedInstance
		let storage = historicLog
		historyPageFetcher = { await storage.fetchOutcome($0) }
		sharedState.withLock {
			$0.client = channel.associatedClient
			$0.channel = channel
			$0.uniqueIdentifier = channel.uniqueIdentifier
		}
		attachedWindow = window
		super.init()
		setUp()
	}

	private func setUp() {
		transcriptProjection.setCapacity(bufferPolicy.hardLimit)
		startPipeline()
	}

	isolated deinit {
		historyRetryTask?.cancel()
		pipelineTask?.cancel()
		olderHistoryTask?.cancel()
		applicationTask?.cancel()
		backingView?.clearLines()
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
	}

	var bufferPolicy: LogViewBufferPolicy {
		LogViewBufferPolicy(preference: Preferences.Logging.scrollbackVisibleLimit.value)
	}

	/// Makes the native AppKit transcript on first visibility. The controller
	/// itself stays live from registration so background transcript work does
	/// not depend on a view hierarchy.
	@discardableResult
	public func ensureBackingView() -> LogView {
		if let backingView {
			return backingView
		}
		let view = LogView(viewController: self)
		backingView = view
		finishLoading(view)
		return view
	}

	private func startPipeline() {
		let pipeline = pipeline
		pipelineTask = Task {
			await pipeline.run()
		}
	}

	private func stopPipeline() {
		let retired = pipeline
		Task { await retired.stop() }
		pipelineTask?.cancel()
		pipelineTask = nil
	}

	/** Drops everything this view has queued and starts a fresh pipeline.

	 Bumping the generation first is what makes the cancellation take effect
	 immediately: a job that is already rendering finds its generation stale and
	 applies nothing. Retiring the whole pipeline is what drops the jobs that had
	 not started; nothing waits for it. */
	private func cancelRenderJobs() {
		guard terminating == false else {
			return
		}
		renderGeneration += 1
		cancelOlderHistory()
		pendingApplications.removeAll()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		/* The dropped jobs include whatever was going to finish the replay, so
		 the latch has to be released here rather than waiting for a completion
		 that is never going to arrive. */
		reloadingHistory = false
		stopPipeline()
		pipeline = LogRenderPipeline()
		startPipeline()
	}

	func drainRenderJobs() async {
		await olderHistoryTask?.value
		await pipeline.barrier()
		while !pendingApplications.isEmpty {
			applyPendingBatch()
			await Task.yield()
		}
	}

	private func cancelOlderHistory() {
		historyRetryTask?.cancel()
		historyRetryTask = nil
		historyRecovery.isRetrying = false
		olderHistoryTask?.cancel()
		olderHistoryTask = nil
		loadingOlderHistory = false
		locallyExhaustedBefore = nil
		let retiredRequest = serverHistoryRequest
		serverHistoryRequest = nil
		if let retiredRequest {
			associatedClient?.cancelServerHistoryRequest(retiredRequest)
		}
		serverHistoryCompletedBefore = nil
		serverHistoryExhaustedBefore = nil
		serverHistoryFailed = false
		olderHistoryFailure = nil
	}

	func acceptsRenderGeneration(_ generation: Int) -> Bool {
		renderGeneration == generation && !terminating
	}

	private func historicLogForgetChannel() {
		guard let associatedItem else {
			return
		}
		historicLogMutationTask = historicLog.forgetView(associatedItem.uniqueIdentifier)
	}

	private func historicLogResetChannel() {
		guard let associatedItem else {
			return
		}
		historicLogMutationTask = historicLog.resetData(forView: associatedItem.uniqueIdentifier)
	}

	private func closeHistoricLog() {
		let channel = associatedChannel
		if !Preferences.Logging.reloadScrollbackOnLaunch.value || channel?.isUtility == true || channel?
			.isDirectChat == true ||
			(channel?.isPrivateMessage == true && !Preferences.Appearance.rememberQueryStates.value)
		{
			historicLogResetChannel()
		}
	}

	func tearDown(_ reason: TreeItemTeardown) {
		guard !terminating else { return }
		if reason == .applicationTermination {
			/* Bound to a local because the log message is an autoclosure, where
			 `self.` would be required and SwiftFormat would strip it. */
			let identifier = uniqueIdentifier
			logControllerLogger.debug("Preparing view controller: \(identifier, privacy: .public)")
		}
		renderGeneration += 1
		terminating = true
		refreshServerRetryAvailability()
		cancelOlderHistory()
		pendingApplications.removeAll()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		viewIsLoaded = false
		backingView?.clearLines()
		backingView = nil
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		stopPipeline()
		switch reason {
		case .applicationTermination: closeHistoricLog()
		case .permanentRemoval: historicLogForgetChannel()
		case .preservingRemoval: break
		}
	}

	/** Submits one render job to this view's pipeline.

	 `render` runs off the main actor and produces the value `apply` then acts on,
	 on the main actor, in the order the jobs were submitted. That split is what
	 replaced the printing operation: `render` may only capture what can cross
	 isolation, while `apply` is written here, on the main actor, and so may
	 capture a `LogLine`, a caller's completion block or anything else the view
	 needs. Returning `nil` from `render` drops the job. Render outputs are
	 Sendable values; AppKit presentation is constructed only during application. */
	/// Whether this view still has a pipeline to submit to. A retired view, or
	/// one whose application is on its way out, silently drops every job.
	var acceptsRenderJobs: Bool {
		terminating == false && AppController.shared.applicationIsTerminating == false
	}

	@discardableResult
	func enqueueRenderJob<Output: Sendable>(
		isStandalone: Bool = false,
		render: @escaping @Sendable @concurrent () async -> Output?,
		apply: @escaping @MainActor (Output) -> Void
	) -> Bool {
		guard acceptsRenderJobs else {
			return false
		}
		let generation = renderGeneration
		pipeline.submissions.yield(LogRenderSubmission(isStandalone: isStandalone) { [weak self] in
			guard let output = await render() else {
				return nil
			}
			return { self?.applyRenderOutput(output, generation: generation, apply) }
		})
		return true
	}

	private func applyRenderOutput<Output: Sendable>(
		_ output: Output,
		generation: Int,
		_ apply: @escaping @MainActor (Output) -> Void
	) {
		guard renderGeneration == generation, terminating == false else {
			return
		}
		pendingApplications.append { [weak self] in
			guard let self, acceptsRenderGeneration(generation) else { return }
			apply(output)
		}
		guard applicationTask == nil else { return }
		applicationTask = Task { @MainActor [weak self] in
			await Task.yield()
			while let self, !Task.isCancelled {
				guard !pendingApplications.isEmpty else {
					applicationTask = nil
					return
				}
				applyPendingBatch()
				await Task.yield()
			}
		}
	}

	private func applyPendingBatch() {
		let count = min(32, pendingApplications.count)
		let batch = Array(pendingApplications.prefix(count))
		pendingApplications.removeFirst(count)
		if let backingView {
			backingView.performEditingBatch { for apply in batch {
				apply()
			} }
		} else {
			for apply in batch {
				apply()
			}
		}
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
	func makeRenderContext() -> LogLineRenderContext {
		let channel = associatedChannel
		return LogLineRenderContext(
			inlineMediaEnabled: inlineMediaEnabledForView,
			isChannel: channel?.isChannel == true,
			members: memberRenderCache.members(in: channel),
			sessionReactions: reactionsByMessageIdentifier
		)
	}

	private func setInitialTopic() {
		setTopicNow(associatedChannel?.topic)
	}

	public func setTopic(_ topic: String?) {
		setTopicNow(topic)
	}

	private func setTopicNow(_ topic: String?) {
		guard !terminating else { return }
		backingView?.setTopic(topic?.isEmpty == false ? topic : nil)
	}

	public func moveToBottom() {
		backingView?.scrollToBottom()
	}

	public func mark() {
		let mark = (newestLineNumber ?? lastLineStorage?.uniqueIdentifier).map(TranscriptScrollbackMark.line) ?? .latest
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	public func mark(at date: Date) {
		transcriptProjection.setMark(.after(date))
		backingView?.setUnreadMarker(.after(date))
	}

	public func unmark() {
		transcriptProjection.setMark(.none)
		backingView?.setUnreadMarker(.none)
	}

	public func goToMark() {
		switch transcriptProjection.mark {
		case .none: break
		case .latest: moveToBottom()
		case let .line(identifier):
			jump(toLine: backingView?.displayedLines
				.first(where: { $0.matches(identifier: identifier) })?.lineNumber
				?? oldestLineNumber ?? identifier)
		case let .after(date):
			if let line = backingView?.displayedLines
				.first(where: { $0.receivedAt >= date && $0.lineType.isConversation })?.lineNumber
			{
				jump(toLine: line)
			}
		}
	}

	func applyReloadedLines(
		_ results: [LogLineRenderResult],
		isReload: Bool,
		suppressingPluginMessages lineNumbersToSuppress: Set<String> = []
	) {
		guard results.isEmpty == false else {
			return
		}
		var pluginObjects: [PluginPostedMessage] = []
		let channel = associatedChannel
		let suppressed = lineNumbersToSuppress.union(transcriptProjection.pendingLineNumbers)
		for result in results {
			if let pluginMessage = result.pluginMessage,
			   suppressed.contains(result.lineNumber) == false,
			   result.transcriptLine.historyCursor.map({ suppressed.contains($0.lineIdentifier) }) != true
			{
				pluginObjects.append(pluginMessage.makeObject(resolvingMembersIn: channel))
			}
		}
		let lines = results.map { applyingCurrentState(to: $0.transcriptLine) }
		if isReload {
			backingView?.appendLines(lines)
		} else {
			backingView?.replaceLines(lines)
		}
		for var pluginObject in pluginObjects {
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.dispatchDidPostNewMessage(pluginObject)
		}
		for result in results where result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: result.lineNumber)
		}
	}
}

public extension LogController {
	func reloadTheme() {
		if !terminating {
			backingView?.applyTheme()
		}
	}

	func jumpToCurrentSession() {
		for lineNumber in [transcriptSessionBoundary.firstCurrentSessionLineNumber,
		                   newestLineNumberFromPreviousSession, oldestLineNumber].compactMap(\.self)
			where backingView?.jump(to: lineNumber) == true
		{
			return
		}
	}

	func jumpToPresent() {
		moveToBottom()
	}

	func jump(toLine lineNumber: String) {
		jump(toLine: lineNumber, completionHandler: nil)
	}

	func jump(toLine lineNumber: String, completionHandler: ((Bool) -> Void)?) {
		let successful = backingView?.jump(to: lineNumber) == true
		completionHandler?(successful)
	}

	func notifyDidBecomeVisible() {
		maybeReloadHistory()
	}

	func notifyDidBecomeHidden() {}

	func notifySelectionChanged() {}

	func changeTextSize(_: Bool) {
		guard let attachedWindow else {
			return
		}
		backingView?.setTextScale(attachedWindow.textSizeMultiplier)
	}

	func changeScrollbackLimit() {
		let policy = bufferPolicy
		transcriptProjection.setCapacity(policy.hardLimit)
		backingView?.setBufferLimit(policy.hardLimit)
	}

	func notifyHistoricLogWillDeleteLines(_ lineNumbers: [String]) {
		guard !terminating else {
			return
		}
		if let lastVisitedHighlight, lineNumbers.contains(lastVisitedHighlight) {
			self.lastVisitedHighlight = nil
		}
	}

	func processInlineMedia(_ links: [LinkParserResult], atLineNumber lineNumber: String) {
		for link in links {
			processInlineMediaAtAddress(
				link.stringValue,
				withUniqueIdentifier: link.uniqueIdentifier,
				atLineNumber: lineNumber
			)
		}
	}

	@discardableResult
	func processInlineMediaAtAddress(
		_ address: String,
		withUniqueIdentifier linkIdentifier: String,
		atLineNumber lineNumber: String
	) -> UUID? {
		/* The link parser's scheme set is user-extensible, so an address that
		 became clickable is not necessarily one the inline-content service can
		 handle. It only ever fetches over HTTP, and aborts on a file: URL. */
		guard let url = URL(string: address),
		      let scheme = url.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else {
			return nil
		}

		guard backingView?.displayedLines.contains(where: { $0.lineNumber == lineNumber }) == true else { return nil }
		let generation = renderGeneration
		let loader = inlineImageLoader
		// Only admission failures run synchronously; successful callbacks receive the assigned token.
		var requestIdentifier: UUID?
		requestIdentifier = loader.load(
			url: url,
			viewIdentifier: uniqueIdentifier,
			lineNumber: lineNumber,
			linkIdentifier: linkIdentifier
		) { [weak self] result in
			switch result {
			case let .success(image):
				guard let self, acceptsRenderGeneration(generation), backingView?.addInlineImage(image) == true else {
					if let requestIdentifier {
						loader.cancelLoad(requestIdentifier)
					}
					return
				}
			case let .failure(error):
				let reason = (error as? NativeInlineImageError)?.logDescription ?? error.localizedDescription
				logControllerLogger.error(
					"Inline image request failed for '\(address, privacy: .public)': \(reason, privacy: .public)"
				)
			}
		}
		return requestIdentifier
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
		let index = current.map { ($0 + offset + highlightedLineNumbers.count) % highlightedLineNumbers.count }
			?? (offset > 0 ? 0 : highlightedLineNumbers.count - 1)
		let target = highlightedLineNumbers[index]
		lastVisitedHighlight = target
		jump(toLine: target)
	}

	private func clear(resetHistoricLog: Bool) {
		guard !terminating else {
			return
		}
		cancelRenderJobs()
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		if resetHistoricLog {
			historicLogResetChannel()
			transcriptProjection.reset()
			transcriptSessionBoundary.reset()
			newestLineNumberFromPreviousSession = nil
		} else {
			transcriptProjection.becomeDormant()
		}
		lastVisitedHighlight = nil
		lastLineStorage = nil
		reloadingHistory = false
		historyLoaded = false
		backingView?.clearLines()
		if let backingView {
			viewIsLoaded = false
			finishLoading(backingView)
		}
	}

	func clear() {
		clear(resetHistoricLog: true)
	}
}

extension LogController {
	/// The row as it should be drawn now: the delivery and reaction updates
	/// that arrived after it rendered are folded in at the last moment, so a
	/// line re-applied by a replay or a theme change carries them too.
	func applyingCurrentState(to input: TranscriptLine) -> TranscriptLine {
		var line = input
		if let update = transcriptProjection.deliveryUpdates[line.lineNumber] {
			line.deliveryState = update.state
			line.messageIdentifier = update.messageIdentifier ?? line.messageIdentifier
			line.deliveryFailureReason = update.reason
		}
		if let identifier = line.messageIdentifier, let delta = reactionsByMessageIdentifier[identifier] {
			line.mergeReactions(delta)
		}
		return line
	}
}

public extension LogController {
	func print(_ logLine: LogLine) {
		print(logLine, completionBlock: nil)
	}

	func print(
		_ inputLogLine: LogLine,
		completionBlock postPrintBlock: LogControllerPrintOperationCompletion?
	) {
		guard !terminating else {
			return
		}
		/* A snapshot: the caller still holds the line it handed over, and rendering
		 continues off the main actor after this returns. */
		let logLine = inputLogLine
		lastLineStorage = logLine
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
			return Self.renderJob(request)
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
		let alreadyDisplayed = backingView?.displayedLines.contains { $0.matches(identifier: lineNumber) } == true
		if result.isHighlight {
			if let channel {
				client.cacheHighlight(in: channel, with: logLine)
			}
		}
		let projectionAction = transcriptProjection.record(logLine, rendered: result)
		if case .append = projectionAction, !alreadyDisplayed {
			var displayedLine = applyingCurrentState(to: result.transcriptLine)
			if transcriptSessionBoundary.consumePendingMarker(for: result) {
				displayedLine.markers.insert(
					.currentSession(MainWindowStrings.Conversation.currentSession),
					at: 0
				)
			}
			backingView?.appendLines([displayedLine])
		}
		if let pluginMessage = result.pluginMessage, !alreadyDisplayed {
			PluginDispatcher.dispatchDidPostNewMessage(pluginMessage.makeObject(resolvingMembersIn: channel))
		}
		if case .append = projectionAction, !alreadyDisplayed, result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: lineNumber)
		}
		historicLog.writeNewEntry(with: logLine, forView: associatedItem.uniqueIdentifier)
		/* The body was scanned against the member snapshot the line rendered
		 with; the conversation weight belongs to whoever is in the channel now. */
		if let channel {
			let direction: ChannelConversationDirection = logLine.memberType == .localUser ? .outgoing : .mention
			for nickname in result.mentionedNicknames where channel.findMember(nickname) != nil {
				channel.recordConversation(with: nickname, direction: direction)
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
		/* A view that is still replaying history has not drawn the line yet; the
		 reactions are handed to it when the replay finishes. */
		guard transcriptProjection.phase == .active else {
			return
		}
		enqueueMainActorWork { [weak self] in
			self?.backingView?.updateReactions(reactions, messageIdentifier: messageIdentifier)
		}
	}

	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: LogLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		transcriptProjection.updateDelivery(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason
		)
		guard transcriptProjection.phase == .active else {
			return
		}
		let update = TranscriptDeliveryUpdate(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason
		)
		enqueueMainActorWork { [weak self] in
			guard let self else { return }
			backingView?.updateDelivery(update)
			if let identifier = update.messageIdentifier, let reactions = reactionsByMessageIdentifier[identifier] {
				backingView?.updateReactions(reactions, messageIdentifier: identifier)
			}
		}
	}
}

public extension LogController {
	private func finishLoading(_ view: LogView) {
		guard !viewIsLoaded,
		      let associatedClient,
		      let attachedWindow
		else {
			return
		}
		withExtendedLifetime((associatedClient, attachedWindow)) {
			viewIsLoaded = true
			viewLoadedTimestamp = Date().timeIntervalSince1970
			view.setBufferLimit(bufferPolicy.hardLimit)
			view.setTextScale(attachedWindow.textSizeMultiplier)
			setInitialTopic()
			reloadHistory()
		}
	}

	func logViewKeyDown(_ event: NSEvent) {
		attachedWindow?.redirectKeyDown(event)
	}

	func logViewReceivedDrop(withFile filename: String) {
		AppController.shared.menuController?.memberSendDroppedFiles(toSelectedChannel: [filename])
	}

	/// The newest line this view printed. The IRC layer consults it when it
	/// decides what history to ask the server for.
	func lastLine() -> LogLine? {
		lastLineStorage
	}
}
