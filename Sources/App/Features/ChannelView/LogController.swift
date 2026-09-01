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

/// One initial projection render, including the subset that actually came from
/// historic storage so indexing and previous-session markers stay accurate.
private nonisolated struct TranscriptHistoryRenderOutput: Sendable { // nonisolated: value
	let historicEntries: [LogLine]
	let entries: [LogLine]
	let results: [LogLineRenderResult]
}

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

@MainActor
public final class LogController: NSObject {
	public private(set) var backingView: LogView?
	public private(set) var viewIsLoaded = false
	public private(set) weak var attachedWindow: MainWindow!
	public private(set) var newestLineNumberFromPreviousSession: String?
	public private(set) var oldestLineNumber: String?
	public private(set) var newestLineNumber: String?

	private nonisolated let sharedState = Mutex(LogControllerSharedState()) // nonisolated: let
	private var terminating = false
	private var historyLoadedForFirstTime = false
	private var reloadingHistory = false
	private var historyLoaded = false
	private var loadingOlderHistory = false
	private var lastVisitedHighlight: String?
	private var highlightedLineNumbers: [String] = []
	private var reactionsByMessageIdentifier: [String: [String: [String]]] = [:]
	private var viewLoadedTimestamp: TimeInterval = 0
	private var lastLineStorage: LogLine?
	private var oldestLineStorage: LogLine?
	private var transcriptProjection = TranscriptProjectionState()
	private var transcriptSessionBoundary = TranscriptSessionBoundaryState()

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

	public var numberOfLines: UInt {
		UInt(transcriptProjection.lineCount)
	}

	public var inlineMediaEnabledForView: Bool {
		guard let channel = associatedChannel else {
			return false
		}
		let config = channel.config
		return Preferences.Messages.showInlineMedia.detachedValue ? !config.inlineMediaDisabled : config
			.inlineMediaEnabled
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

	public init(client: IRCClient, in window: MainWindow) {
		sharedState.withLock {
			$0.client = client
			$0.uniqueIdentifier = client.uniqueIdentifier
		}
		attachedWindow = window
		super.init()
		setUp()
	}

	public init(channel: IRCChannel, in window: MainWindow) {
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
		transcriptProjection.setCapacity(bufferPolicy.hardLimit)
		startPipeline()
	}

	private var bufferPolicy: LogViewBufferPolicy {
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
		stopPipeline()
		pipeline = LogRenderPipeline()
		startPipeline()
	}

	func drainRenderJobs() async {
		await pipeline.drain()
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
		if !Preferences.Logging.reloadScrollbackOnLaunch.value || channel?.isUtility == true || channel?
			.isDirectChat == true ||
			(channel?.isPrivateMessage == true && !Preferences.Appearance.rememberQueryStates.value)
		{
			historicLogResetChannel()
		}
	}

	private func prepareForTermination(_ isTerminatingApplication: Bool) {
		renderGeneration += 1
		terminating = true
		viewIsLoaded = false
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
			inlineMediaEnabled: inlineMediaEnabledForView,
			isChannel: channel?.isChannel == true,
			nicknameFormat: Self.resolvedNicknameFormat(),
			members: (channel?.memberList ?? []).map(RenderedMember.init),
			sessionReactions: reactionsByMessageIdentifier
		)
	}

	/// The nickname format is part of the native transcript theme.
	private static func resolvedNicknameFormat() -> String {
		let format = SharedApplication.sharedThemeController().theme.nicknameFormat
		return format.isEmpty ? TranscriptTheme.lines.nicknameFormat : format
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
		guard !terminating else { return }
		backingView?.setTopic(topic?.isEmpty == false ? topic : nil)
	}

	public func moveToTop() {
		backingView?.scrollToTop()
	}

	public func moveToBottom() {
		backingView?.scrollToBottom()
	}

	public func mark() {
		transcriptProjection.setMark(.latest)
		backingView?.setUnreadMarker(.latest)
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
		case let .after(date):
			if let line = transcriptProjection.renderedLineNumber(onOrAfter: date) {
				jump(toLine: line)
			}
		}
	}

	private func applyReloadedLines(
		_ results: [LogLineRenderResult],
		isReload: Bool,
		suppressingPluginMessages lineNumbersToSuppress: Set<String> = []
	) {
		guard results.isEmpty == false else {
			return
		}
		var pluginObjects: [PluginPostedMessage] = []
		let channel = associatedChannel
		for result in results {
			if let pluginMessage = result.pluginMessage,
			   lineNumbersToSuppress.contains(result.lineNumber) == false
			{
				pluginObjects.append(pluginMessage.makeObject(resolvingMembersIn: channel))
			}
			if result.isHighlight, highlightedLineNumbers.contains(result.lineNumber) == false {
				highlightedLineNumbers.append(result.lineNumber)
			}
		}
		let lines = results.map(\.transcriptLine)
		if isReload {
			backingView?.appendLines(lines)
		} else {
			backingView?.replaceLines(lines)
		}
		for var pluginObject in pluginObjects {
			pluginObject.isProcessedInBulk = true
			PluginDispatcher.enqueueDidPostNewMessage(pluginObject)
		}
		for result in results where lineNumbersToSuppress.contains(result.lineNumber) == false {
			PluginDispatcher.dequeueDidPostNewMessage(withLineNumber: result.lineNumber, forViewController: self)
		}
		for result in results where result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: result.lineNumber)
		}
	}

	private func maybeReloadHistory() {
		guard viewIsLoaded, !historyLoaded, !reloadingHistory else {
			return
		}
		reloadHistory()
	}

	private func reloadHistory() {
		guard !terminating, !reloadingHistory else {
			return
		}
		let firstLoad = !historyLoadedForFirstTime
		let channel = associatedChannel
		let includeStoredHistory = !(firstLoad && !Preferences.Logging.reloadScrollbackOnLaunch.value ||
			channel?.isUtility == true ||
			channel?.isDirectChat == true ||
			(firstLoad && channel?.isPrivateMessage == true && !Preferences.Appearance.rememberQueryStates.value))
		if Preferences.Logging.loadHistoryLazily.value, !viewIsVisible {
			return
		}

		reloadingHistory = true
		fetchHistory(firstLoad: firstLoad, includeStoredHistory: includeStoredHistory)
	}

	private func fetchHistory(firstLoad: Bool, includeStoredHistory: Bool) {
		guard let associatedItem else {
			return
		}
		let viewIdentifier = associatedItem.uniqueIdentifier
		let replay = transcriptProjection.beginReplay()
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
			let xpcEntries = includeStoredHistory
				? await HistoricLogClient.shared.fetchEntries(request)
				: []
			let historicEntries = Array(HistoricLogClient.logLines(from: xpcEntries).reversed())
			let entries = TranscriptProjectionState.merging(
				historic: historicEntries,
				replay: replay.lines
			)
			let snapshots = Self.applyingMessageRenderers(
				to: entries.map { LogLineSnapshot($0, in: context) },
				for: viewController
			)
			let results = Self.renderJob(snapshots, context: context)
			return TranscriptHistoryRenderOutput(
				historicEntries: historicEntries,
				entries: entries,
				results: results
			)
		} apply: { [weak self] (loaded: TranscriptHistoryRenderOutput) in
			self?.applyReloadedHistory(
				loaded.historicEntries,
				loaded.entries,
				results: loaded.results,
				forView: viewIdentifier,
				firstLoad: firstLoad,
				replayedLineNumbers: replay.lineNumbers
			)
		}
	}

	private func applyReloadedHistory(
		_ historicEntries: [LogLine],
		_ entries: [LogLine],
		results inputResults: [LogLineRenderResult],
		forView viewIdentifier: String,
		firstLoad: Bool,
		replayedLineNumbers: Set<String>
	) {
		var results = inputResults
		LogControllerHistoricLogFile.shared().indexLogLines(historicEntries, forView: viewIdentifier)
		if lastLineStorage == nil {
			lastLineStorage = entries.last
		}
		noteOldestLineCandidate(entries.first)
		oldestLineNumber = entries.first?.uniqueIdentifier ?? oldestLineNumber
		if firstLoad {
			let markerLineNumber = transcriptSessionBoundary.prepareInitialHistory(
				historicEntries,
				renderedLines: results
			)
			newestLineNumberFromPreviousSession = transcriptSessionBoundary
				.newestPreviousSessionLineNumber
			if let markerLineNumber,
			   let markerIndex = results.firstIndex(where: { $0.lineNumber == markerLineNumber })
			{
				results[markerIndex].transcriptLine.markers.insert(
					.currentSession(MainWindowStrings.Conversation.currentSession),
					at: 0
				)
			}
		}
		applyReloadedLines(
			results,
			isReload: !firstLoad,
			suppressingPluginMessages: replayedLineNumbers
		)
		var pending = transcriptProjection.finishReplay(displaying: Set(results.map(\.lineNumber)))
		if let pendingIndex = pending.firstIndex(where: { transcriptSessionBoundary.consumePendingMarker(for: $0) }) {
			pending[pendingIndex].transcriptLine.markers.insert(
				.currentSession(MainWindowStrings.Conversation.currentSession),
				at: 0
			)
		}
		applyReloadedLines(
			pending,
			isReload: true,
			suppressingPluginMessages: Set(pending.map(\.lineNumber))
		)
		restoreTranscriptProjectionState()
		reloadingHistory = false
		historyLoaded = true
		historyLoadedForFirstTime = true
	}

	private func restoreTranscriptProjectionState() {
		for update in transcriptProjection.deliveryUpdates.values {
			backingView?.updateDelivery(update)
		}
		for (identifier, reactions) in reactionsByMessageIdentifier {
			backingView?.updateReactions(reactions, messageIdentifier: identifier)
		}
		switch transcriptProjection.mark {
		case .none:
			break
		case .latest:
			backingView?.setUnreadMarker(.latest)
		case let .after(date):
			backingView?.setUnreadMarker(.after(date))
		}
	}
}

public extension LogController {
	func reloadTheme() {
		reloadThemeNow()
	}

	private func reloadThemeNow() {
		guard !terminating else {
			return
		}
		backingView?.applyTheme()
	}

	func jumpToCurrentSession() {
		guard let lineNumber = transcriptSessionBoundary.firstCurrentSessionLineNumber
			?? newestLineNumberFromPreviousSession
			?? oldestLineNumber
		else {
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
		highlightedLineNumbers.removeAll { lineNumbers.contains($0) }
	}

	private func processInlineMedia(_ links: [LinkParserResult], atLineNumber lineNumber: String) {
		for link in links {
			processInlineMediaAtAddress(
				link.stringValue,
				withUniqueIdentifier: link.uniqueIdentifier,
				atLineNumber: lineNumber
			)
		}
	}

	func processInlineMediaAtAddress(
		_ address: String,
		withUniqueIdentifier uniqueIdentifier: String,
		atLineNumber lineNumber: String
	) {
		/* The link parser's scheme set is user-extensible, so an address that
		 became clickable is not necessarily one the inline-content service can
		 handle. It only ever fetches over HTTP, and aborts on a file: URL. */
		guard let scheme = URL(string: address)?.scheme?.lowercased(),
		      scheme == "http" || scheme == "https"
		else {
			return
		}

		NativeInlineImageLoader.shared.load(
			url: URL(string: address)!,
			lineNumber: lineNumber,
			linkIdentifier: uniqueIdentifier
		) { [weak self] result in
			switch result {
			case let .success(image): self?.backingView?.addInlineImage(image)
			case let .failure(error):
				logControllerLogger.error(
					"Inline image request failed for '\(address, privacy: .public)': \(error.localizedDescription, privacy: .public)"
				)
			}
		}
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
			transcriptProjection.reset()
			transcriptSessionBoundary.reset()
		} else {
			transcriptProjection.becomeDormant()
		}
		highlightedLineNumbers.removeAll()
		lastVisitedHighlight = nil
		oldestLineNumber = nil
		newestLineNumber = nil
		lastLineStorage = nil
		oldestLineStorage = nil
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

	func loadOlderHistory() {
		guard !loadingOlderHistory,
		      let associatedItem,
		      let oldestDisplayedLineNumber = oldestLineNumber
		else { return }
		loadingOlderHistory = true
		let viewIdentifier = associatedItem.uniqueIdentifier
		let request = HistoricLogFetchRequest(
			viewIdentifier: viewIdentifier,
			kind: .before(uniqueIdentifier: oldestDisplayedLineNumber, fetchLimit: 100, limitToDate: nil)
		)
		Task { @MainActor [weak self] in
			let xpcEntries = await HistoricLogClient.shared.fetchEntries(request)
			guard let self else { return }
			let entries = LogControllerHistoricLogFile.shared()
				.decodeAndIndex(xpcEntries, forView: viewIdentifier)
			loadingOlderHistory = false
			guard entries.isEmpty == false else {
				noteLocalScrollbackExhausted()
				return
			}
			oldestLineNumber = entries.first?.uniqueIdentifier
			prependHistoricLogLines(entries)
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
		LogControllerHistoricLogFile.shared().indexLogLines(logLines, forView: associatedItem.uniqueIdentifier)
		noteOldestLineCandidate(logLines.first)
		let context = makeRenderContext()
		let lines = logLines.map { LogLineSnapshot($0, in: context) }
		enqueueRenderJob { [weak self] in
			guard let viewController = self else {
				return nil
			}
			let snapshots = Self.applyingMessageRenderers(to: lines, for: viewController)
			let results = Self.renderJob(snapshots, context: context)
			guard results.isEmpty == false else {
				return nil
			}
			return results.map(\.transcriptLine)
		} apply: { [weak self] (prepended: [TranscriptLine]) in
			self?.backingView?.prependLines(prepended)
		}
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
			guard let result = Self.renderJob(request) else {
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
		let projectionAction = transcriptProjection.record(logLine, rendered: result)
		if let pluginMessage = result.pluginMessage {
			let messageObject = pluginMessage.makeObject(resolvingMembersIn: channel)
			if case .append = projectionAction {
				PluginDispatcher.enqueueDidPostNewMessage(messageObject)
			} else {
				PluginDispatcher.dispatchDidPostNewMessage(messageObject)
			}
		}
		if case .append = projectionAction {
			var displayedLine = result.transcriptLine
			if transcriptSessionBoundary.consumePendingMarker(for: result) {
				displayedLine.markers.insert(
					.currentSession(MainWindowStrings.Conversation.currentSession),
					at: 0
				)
			}
			backingView?.appendLines([displayedLine])
			PluginDispatcher.dequeueDidPostNewMessage(withLineNumber: lineNumber, forViewController: self)
			if result.processesInlineMedia {
				processInlineMedia(result.links, atLineNumber: lineNumber)
			}
		}
		LogControllerHistoricLogFile.shared().writeNewEntry(with: logLine, forView: associatedItem.uniqueIdentifier)
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
		enqueueMainActorWork { [weak self] in self?.backingView?.updateDelivery(update) }
	}

	func reactionsForMessageIdentifier(_ messageIdentifier: String) -> [String: [String]]? {
		guard let reactions = reactionsByMessageIdentifier[messageIdentifier], !reactions.isEmpty else {
			return nil
		}
		return reactions
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
			NotificationCenter.default.post(name: .logControllerViewFinishedLoading, object: self)
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
