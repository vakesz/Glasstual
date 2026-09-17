// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import os

typealias PrintedLineCompletion = (PrintedLineContext) -> Void

private nonisolated let transcriptControllerLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "LogController"
)

/// What a print's render job hands back: the row to draw, and the line already
/// archived for the view's store.
private nonisolated struct PrintedLineRender: Sendable {
	let result: TranscriptRenderResult
	let historicEntry: ScrollbackEntry?
}

@MainActor
final class TranscriptController: ServerHistoryPresentation {
	private(set) var backingView: TranscriptView?
	private(set) var viewIsLoaded = false
	private(set) weak var attachedWindow: MainWindow?
	var newestLineNumberFromPreviousSession: String?
	var oldestLineNumber: String? {
		backingView?.displayedBounds.oldest
	}

	var newestLineNumber: String? {
		backingView?.displayedBounds.newest
	}

	private(set) var terminating = false
	/* Loading history is the other half of this controller, and it lives in
	 `TranscriptControllerHistoryLoading.swift`: the initial replay, the scrollback
	 pages and the server-history handshake. The state the two halves share is
	 declared here and reaches no further than this feature. */
	var historyLoadedForFirstTime = false
	var reloadingHistory = false
	var historyLoaded = false
	var historyLoadFailure: ScrollbackFetchFailure? {
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

	var olderHistoryFailure: ScrollbackFetchFailure? {
		didSet { historyRecovery.olderFailure = olderHistoryFailure }
	}

	let historyRecovery = TranscriptHistoryRecoveryState()
	var historyStorageRecovery: TranscriptHistoryRecoveryState {
		scrollback.recovery
	}

	var historyRetryTask: Task<Void, Never>?
	var olderHistoryFailed: Bool {
		olderHistoryFailure != nil
	}

	var historyPageFetcher: @Sendable @concurrent (ScrollbackFetchRequest) async
		-> ScrollbackFetchOutcome
	/** Whether the first history read waits until the view becomes visible.

	 A closure rather than a direct read so a test can pin the decision for one
	 controller; writing `Preferences.Logging.loadHistoryLazily` instead would
	 change what every other suite running beside it sees. Read on each reload,
	 so a preference change still takes effect at once. */
	var loadsHistoryLazily: @MainActor () -> Bool = { Preferences.Logging.loadHistoryLazily.value }

	private let memberRenderCache = TranscriptMemberDirectoryCache()
	let inlineImageLoader: InlineImageLoader
	let scrollback: Scrollback
	private(set) var scrollbackMutationTask: Task<Void, Never>?

	private var lastVisitedHighlight: String?
	/// Whether any line on screen is a highlight. Cheap: the transcript counts
	/// them as it is edited, and menu validation asks for this on every pass.
	var hasHighlightedLines: Bool {
		backingView?.hasHighlightedLines == true
	}

	/// The highlights in the order they are drawn, for the commands that step
	/// through them. Walked on demand, once per keystroke.
	private var highlightedLineNumbers: [String] {
		backingView?.displayedLines.compactMap { $0.body.isHighlight ? $0.lineNumber : nil } ?? []
	}

	/** Reactions that arrived this session, by the message they answer.

	 Only for messages this controller still holds, in the view or in its
	 projection, or is about to: a reaction for anything else has no row to be
	 drawn on, and keeping every one the connection ever carried grew for as
	 long as the process ran. Retired with the last row of their message. */
	private(set) var reactionsByMessageIdentifier: [String: [String: [String]]] = [:]

	/// The longest reaction kept, in UTF-16 units. A reaction is an emoji, and
	/// the longest sequences in use are a few dozen units.
	static let maximumReactionLength = 64
	/// How many people one reaction on one message records.
	static let maximumReactorsPerReaction = 256
	private(set) var viewLoadedTimestamp: TimeInterval = 0
	var lastLineStorage: LogLine?
	/** The lines handed to `print` that have not been applied to the view yet.

	 Rendering continues off the main actor, so `displayedLines` is empty for a
	 line printed in this turn. The read marker a server sends arrives in the same
	 turn as the burst it refers to, and answering it from the view alone would
	 miss every line of that burst.

	 The invariant is that what the pipeline drops, the seams forget: a line
	 leaves this list when it is applied, when the queued jobs are cancelled, and
	 when the view is torn down, so nothing here is ever a line the view will
	 never show. Single-purpose: the two conversation seams in
	 `MainWindow+ClientDirectorySeams` are the only readers. */
	var linesAwaitingRender: ArraySlice<LogLine> {
		awaitingRender[awaitingRenderHead...]
	}

	/** The storage behind ``linesAwaitingRender``. Lines are applied in the order
	 they were printed, so the one applied is almost always the first still
	 waiting: withdrawing it moves a head instead of shifting every line behind
	 it, and the storage is compacted once the head is past half of it. */
	private var awaitingRender: [LogLine] = []
	private var awaitingRenderHead = 0
	var transcriptProjection = TranscriptProjectionState()
	var transcriptSessionBoundary = TranscriptSessionBoundaryState()

	/** This view's render pipeline, and the task that drains it. Replaced
	 wholesale when the view is cleared: dropping the stream is how queued work
	 is cancelled. */
	private var pipeline = TranscriptRenderPipeline()
	private var pipelineTask: Task<Void, Never>?
	/** Bumped whenever queued work is cancelled. A job that was already
	 rendering checks it before it applies, which is the synchronous half of
	 cancellation — the pipeline drops the rest asynchronously. */
	private(set) var renderGeneration = 0
	var pendingApplications: [@MainActor () -> Void] = []
	var deferredPrepends: [@MainActor () -> Void] = []
	private var applicationTask: Task<Void, Never>?

	/** The item this view draws, fixed when the controller is made.

	 Both references are weak, and both are optional to read. The world owns the
	 client and the channel; the window's registry owns the controllers and
	 drops them by identifier, so a controller can still be reached for as long
	 as the removal is in flight -- which is why every read here is a `guard
	 let`. The client used to be declared implicitly unwrapped, which promised
	 the opposite of what those guards say and left an unwrap in reach that
	 would have trapped exactly when the guards were right. */
	private(set) weak var associatedClient: Client?
	private(set) weak var associatedChannel: Channel?
	/// The item's identifier, which never changes once the controller is attached.
	private(set) var uniqueIdentifier = ""

	var associatedItem: ChatItem? {
		associatedChannel ?? associatedClient
	}

	var numberOfLines: UInt {
		UInt(backingView?.displayedBounds.count ?? transcriptProjection.lineCount)
	}

	var inlineMediaEnabledForView: Bool {
		guard let channel = associatedChannel else {
			return false
		}
		let config = channel.config
		return Preferences.Messages.showInlineMedia.detachedValue ? !config.inlineMediaDisabled : config
			.inlineMediaEnabled
	}

	var viewIsVisible: Bool {
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

	convenience init(client: Client, in window: MainWindow) {
		self.init(client: client, in: window, inlineImageLoader: .shared)
	}

	init(
		client: Client, in window: MainWindow, inlineImageLoader: InlineImageLoader,
		scrollback: Scrollback = .shared
	) {
		self.inlineImageLoader = inlineImageLoader
		self.scrollback = scrollback
		historyPageFetcher = { await scrollback.fetchOutcome($0) }
		associatedClient = client
		uniqueIdentifier = client.uniqueIdentifier
		attachedWindow = window
		setUp()
	}

	init(channel: Channel, in window: MainWindow) {
		inlineImageLoader = .shared
		scrollback = .shared
		let storage = scrollback
		historyPageFetcher = { await storage.fetchOutcome($0) }
		associatedClient = channel.associatedClient
		associatedChannel = channel
		uniqueIdentifier = channel.uniqueIdentifier
		attachedWindow = window
		setUp()
	}

	private func setUp() {
		transcriptProjection.setCapacity(bufferPolicy.hardLimit)
		startPipeline()
	}

	isolated deinit {
		associatedClient?.renderAdmission.retire(view: uniqueIdentifier)
		historyRetryTask?.cancel()
		pipelineTask?.cancel()
		olderHistoryTask?.cancel()
		applicationTask?.cancel()
		backingView?.clearLines()
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
	}

	var bufferPolicy: TranscriptBufferPolicy {
		TranscriptBufferPolicy(preference: Preferences.Logging.scrollbackVisibleLimit.value)
	}

	/// Makes the native AppKit transcript on first visibility. The controller
	/// itself stays live from registration so background transcript work does
	/// not depend on a view hierarchy.
	@discardableResult
	func ensureBackingView() -> TranscriptView {
		if let backingView {
			return backingView
		}
		let view = TranscriptView(viewController: self)
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
		associatedClient?.renderAdmission.retire(view: uniqueIdentifier)
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
		forgetLinesAwaitingRender()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		/* The dropped jobs include whatever was going to finish the replay, so
		 the latch has to be released here rather than waiting for a completion
		 that is never going to arrive. */
		reloadingHistory = false
		stopPipeline()
		pipeline = TranscriptRenderPipeline()
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

	private func scrollbackForgetChannel() {
		guard let associatedItem else {
			return
		}
		scrollbackMutationTask = scrollback.removeHistory(forView: associatedItem.uniqueIdentifier, forget: true)
	}

	private func scrollbackResetChannel() {
		guard let associatedItem else {
			return
		}
		scrollbackMutationTask = scrollback.removeHistory(forView: associatedItem.uniqueIdentifier, forget: false)
	}

	private func closeScrollback() {
		let channel = associatedChannel
		if !Preferences.Logging.reloadScrollbackOnLaunch.value || channel?.isUtility == true || channel?
			.isDirectChat == true ||
			(channel?.isPrivateMessage == true && !Preferences.Appearance.rememberQueryStates.value)
		{
			scrollbackResetChannel()
		}
	}

	func tearDown(_ reason: ChatItemTeardown) {
		guard !terminating else { return }
		if reason == .applicationTermination {
			/* Bound to a local because the log message is an autoclosure, where
			 `self.` would be required and SwiftFormat would strip it. */
			let identifier = uniqueIdentifier
			transcriptControllerLogger.debug("Preparing view controller: \(identifier, privacy: .public)")
		}
		renderGeneration += 1
		terminating = true
		forgetLinesAwaitingRender()
		refreshServerRetryAvailability()
		cancelOlderHistory()
		pendingApplications.removeAll()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		viewIsLoaded = false
		reactionsByMessageIdentifier.removeAll()
		backingView?.clearLines()
		backingView = nil
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		stopPipeline()
		switch reason {
		case .applicationTermination: closeScrollback()
		case .permanentRemoval: scrollbackForgetChannel()
		case .preservingRemoval: break
		}
	}

	/// Whether this view still has a pipeline to submit to. A retired view, or
	/// one whose application is on its way out, silently drops every job.
	var acceptsRenderJobs: Bool {
		terminating == false && AppServices.delegate.applicationIsTerminating == false
	}

	/** Submits one render job to this view's pipeline.

	 `render` runs off the main actor and produces the value `apply` then acts on,
	 on the main actor, in the order the jobs were submitted. That split is what
	 replaced the printing operation: `render` may only capture what can cross
	 isolation, while `apply` is written here, on the main actor, and so may
	 capture a `LogLine`, a caller's completion block or anything else the view
	 needs. Returning `nil` from `render` drops the job. Render outputs are
	 Sendable values; AppKit presentation is constructed only during application. */
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
		let admission = associatedClient?.renderAdmission
		let ticket = admission?.submit(for: uniqueIdentifier)
		pipeline.submissions.yield(TranscriptRenderSubmission(isStandalone: isStandalone) { [weak self] in
			let output = await render()
			return {
				guard let self, let output, self.acceptsRenderGeneration(generation) else {
					if let ticket {
						admission?.finish(ticket)
					}
					return
				}
				self.applyRenderOutput(output, generation: generation) { value in
					defer {
						if let ticket {
							admission?.finish(ticket)
						}
					}
					apply(value)
				}
			}
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

	/** Snapshot of the main-actor state that rendering needs.

	 The members are only needed to find the mentions in a message, and
	 building them is a walk of the channel after every join or part: a line
	 that is not a message leaves them out, and its sender's mark is looked up
	 by the caller instead. */
	func makeRenderContext(includingMembers: Bool = true) -> TranscriptRenderContext {
		let channel = associatedChannel
		return TranscriptRenderContext(
			inlineMediaEnabled: inlineMediaEnabledForView,
			isChannel: channel?.isChannel == true,
			showsDateChanges: Preferences.Messages.showDateChanges.value,
			textPolicy: .current(),
			members: includingMembers ? memberRenderCache.members(in: channel) : [],
			caseMapping: associatedClient?.supportInfo.caseMapping ?? .rfc1459,
			sessionReactions: reactionsByMessageIdentifier
		)
	}

	private func setInitialTopic() {
		setTopicNow(associatedChannel?.topic)
	}

	func setTopic(_ topic: String?) {
		setTopicNow(topic)
	}

	private func setTopicNow(_ topic: String?) {
		guard !terminating else { return }
		backingView?.setTopic(topic?.isEmpty == false ? topic : nil)
	}

	/** Redraws the topic bar's mode caption from the channel as it stands now.

	 The modes are not pushed to the view the way the topic is: nothing in the
	 IRC layer addresses one transcript when they change. The bar is refreshed
	 where the change already surfaces — the mode line landing in this view, the
	 view coming back on screen, and the window retitling this item. */
	func refreshTopicBar() {
		guard !terminating else { return }
		backingView?.refreshTopicBar()
	}

	func mark() {
		let mark = (newestLineNumber ?? lastLineStorage?.uniqueIdentifier).map(TranscriptScrollbackMark.line) ?? .latest
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	func mark(at date: Date) {
		transcriptProjection.setMark(.after(date))
		backingView?.setUnreadMarker(.after(date))
	}

	func unmark() {
		transcriptProjection.setMark(.none)
		backingView?.setUnreadMarker(.none)
	}

	func goToMark() {
		switch transcriptProjection.mark {
		case .none: break
		case .latest: jumpToPresent()
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

	func applyReloadedLines(_ results: [TranscriptRenderResult], isReload: Bool) {
		guard results.isEmpty == false else {
			return
		}
		let lines = results.map { applyingCurrentState(to: $0.transcriptLine) }
		if isReload {
			backingView?.appendLines(lines)
		} else {
			backingView?.replaceLines(lines)
		}
		for result in results where result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: result.lineNumber)
		}
	}
}

extension TranscriptController {
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
		backingView?.scrollToBottom()
	}

	func jump(toLine lineNumber: String, completionHandler: ((Bool) -> Void)? = nil) {
		let successful = backingView?.jump(to: lineNumber) == true
		completionHandler?(successful)
	}

	func notifyDidBecomeVisible() {
		refreshTopicBar()
		maybeReloadHistory()
	}

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
		forgetRetiredProjectionMessages()
	}

	func notifyScrollbackWillDeleteLines(_ lineNumbers: [String]) {
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

		guard backingView?.containsLine(identifier: lineNumber) == true else { return nil }
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
				let reason = (error as? InlineImageError)?.logDescription ?? error.localizedDescription
				transcriptControllerLogger.error(
					"Inline image request failed for '\(address, privacy: .public)': \(reason, privacy: .public)"
				)
			}
		}
		return requestIdentifier
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
		let highlights = highlightedLineNumbers
		guard highlights.isEmpty == false else { return }
		let current = lastVisitedHighlight.flatMap(highlights.firstIndex(of:))
		let index = current.map { ($0 + offset + highlights.count) % highlights.count }
			?? (offset > 0 ? 0 : highlights.count - 1)
		let target = highlights[index]
		lastVisitedHighlight = target
		jump(toLine: target)
	}

	/// Empties the transcript and the history behind it, and starts the view
	/// over from an empty store.
	func clear() {
		guard !terminating else {
			return
		}
		cancelRenderJobs()
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		scrollbackResetChannel()
		transcriptProjection.reset()
		transcriptSessionBoundary.reset()
		newestLineNumberFromPreviousSession = nil
		reactionsByMessageIdentifier.removeAll()
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
}

extension TranscriptController {
	/// The row as it should be drawn now: the delivery and reaction updates
	/// that arrived after it rendered are folded in at the last moment, so a
	/// line re-applied by a replay or a theme change carries them too.
	func applyingCurrentState(to input: TranscriptRow) -> TranscriptRow {
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

extension TranscriptController {
	func print(_ logLine: LogLine) {
		print(logLine, completionBlock: nil)
	}

	func print(
		_ logLine: LogLine,
		completionBlock postPrintBlock: PrintedLineCompletion?
	) {
		guard !terminating else {
			return
		}
		if logLine.lineType == .mode {
			refreshTopicBar()
		}
		lastLineStorage = logLine
		let context = makeRenderContext(includingMembers: logLine.lineType.mentionsMembers)
		let channel = associatedChannel
		let senderMark = channel?.isChannel == true
			? logLine.nickname.flatMap { channel?.findMember($0)?.mark } ?? ""
			: ""
		let line = LogLineSnapshot(logLine, in: context, modeSymbol: senderMark)
		let viewIdentifier = associatedItem?.uniqueIdentifier
		let enqueued = enqueueRenderJob {
			/* Archived here, beside the render, so the main actor that applies
			 the line only hands the store a finished entry. */
			PrintedLineRender(
				result: Self.renderJob(TranscriptRenderRequest(line: line, context: context)),
				historicEntry: viewIdentifier.map { logLine.historicEntry(forView: $0) }
			)
		} apply: { [weak self] (rendered: PrintedLineRender) in
			self?.applyPrintedLine(logLine, rendered: rendered, completionBlock: postPrintBlock)
		}
		/* Only a line the pipeline took can be applied, and only an applied line
		 is withdrawn again: a job refused because the application is quitting
		 would otherwise stay awaiting a render that never comes. */
		if enqueued {
			awaitingRender.append(logLine)
		}
	}

	/// Drops every line still waiting for its render, when the jobs that would
	/// have applied them are gone.
	private func forgetLinesAwaitingRender() {
		awaitingRender.removeAll()
		awaitingRenderHead = 0
	}

	private func withdrawLineAwaitingRender(_ logLine: LogLine) {
		if awaitingRenderHead < awaitingRender.count,
		   awaitingRender[awaitingRenderHead].uniqueIdentifier == logLine.uniqueIdentifier
		{
			awaitingRenderHead += 1
			if awaitingRenderHead * 2 >= awaitingRender.count {
				awaitingRender.removeFirst(awaitingRenderHead)
				awaitingRenderHead = 0
			}
			return
		}
		awaitingRender.removeFirst(awaitingRenderHead)
		awaitingRenderHead = 0
		awaitingRender.removeAll { $0.uniqueIdentifier == logLine.uniqueIdentifier }
	}

	private func applyPrintedLine(
		_ logLine: LogLine,
		rendered: PrintedLineRender,
		completionBlock postPrintBlock: PrintedLineCompletion?
	) {
		let result = rendered.result
		/* Withdrawn before any guard below, so a line one of them drops is not
		 left counted as a line that is still on its way to the view. */
		withdrawLineAwaitingRender(logLine)
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
		let alreadyDisplayed = backingView?.containsLine(identifier: lineNumber) == true
		/* The same line printed again, as opposed to a different line carrying
		 a message identifier the view has already seen. It was stored when it
		 was first printed, and a second row under one line identifier is a
		 cursor history can no longer page from. */
		let alreadyPrinted = alreadyDisplayed || transcriptProjection
			.containsLine(withIdentifier: logLine.uniqueIdentifier)
		let isDuplicate = alreadyPrinted
			|| logLine.messageIdentifier.map { scrollback.containsMessageIdentifier(
				$0,
				forView: associatedItem.uniqueIdentifier
			) } == true
		if result.isHighlight, !isDuplicate {
			if let channel {
				client.cacheHighlight(in: channel, with: logLine)
			}
		}
		let projectionAction = transcriptProjection.record(result)
		forgetRetiredProjectionMessages()
		if case .append = projectionAction, !alreadyDisplayed {
			var displayedLine = applyingCurrentState(to: result.transcriptLine)
			if transcriptSessionBoundary.consumePendingMarker(for: result) {
				displayedLine.markers.insert(
					.currentSession(String(localized: .MainWindow.currentSession)),
					at: 0
				)
			}
			backingView?.appendLines([displayedLine])
		}
		if case .append = projectionAction, !alreadyDisplayed, result.processesInlineMedia {
			processInlineMedia(result.links, atLineNumber: lineNumber)
		}
		if alreadyPrinted == false {
			scrollback.writeNewEntry(
				rendered.historicEntry ?? logLine.historicEntry(forView: associatedItem.uniqueIdentifier),
				for: logLine
			)
		}
		/* The body was scanned against the member snapshot the line rendered
		 with; the conversation weight belongs to whoever is in the channel now. */
		if let channel {
			let direction: ChannelConversationDirection = logLine.memberType == .localUser ? .outgoing : .mention
			for nickname in result.mentionedNicknames where channel.findMember(nickname) != nil {
				channel.recordConversation(with: nickname, direction: direction)
			}
		}
		var context = PrintedLineContext(
			client: client,
			channel: channel,
			highlight: result.isHighlight,
			logLine: logLine,
			lineNumber: lineNumber
		)
		context.isDuplicate = isDuplicate
		context.isDisplayed = alreadyDisplayed || backingView?.displayedLines.last?
			.matches(identifier: lineNumber) == true
		postPrintBlock?(context)
	}

	func noteReaction(
		_ wireEmoji: String,
		fromNickname nickname: String,
		toMessageIdentifier messageIdentifier: String
	) {
		let emoji = TranscriptTextSanitizer.singleLine(wireEmoji)
		guard !emoji.isEmpty, emoji.utf16.count <= Self.maximumReactionLength,
		      !nickname.isEmpty, !messageIdentifier.isEmpty,
		      holdsMessage(withIdentifier: messageIdentifier)
		else {
			return
		}
		var reactions = reactionsByMessageIdentifier[messageIdentifier] ?? [:]
		var nicknames = reactions[emoji] ?? []
		guard nicknames.count < Self.maximumReactorsPerReaction || nicknames.contains(nickname) else { return }
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

	/** Whether a reaction to `identifier` has a row to be drawn on, now or once
	 what is on its way arrives: a row the view shows or the projection keeps,
	 a printed line still rendering, or a replay that is still loading. */
	private func holdsMessage(withIdentifier identifier: String) -> Bool {
		transcriptProjection.phase != .active
			|| backingView?.document.ordinals(ofMessage: identifier) != nil
			|| transcriptProjection.containsMessage(withIdentifier: identifier)
			|| linesAwaitingRender.contains { $0.messageIdentifier == identifier }
	}

	/// The view trimmed the last rows of these messages.
	func transcriptDidRetireMessages(_ identifiers: [String]) {
		forgetReactions(for: identifiers)
	}

	private func forgetRetiredProjectionMessages() {
		forgetReactions(for: transcriptProjection.takeRetiredMessageIdentifiers())
	}

	private func forgetReactions(for identifiers: [String]) {
		for identifier in identifiers where reactionsByMessageIdentifier[identifier] != nil {
			guard backingView?.document.ordinals(ofMessage: identifier) == nil,
			      transcriptProjection.containsMessage(withIdentifier: identifier) == false
			else { continue }
			reactionsByMessageIdentifier.removeValue(forKey: identifier)
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
		forgetRetiredProjectionMessages()
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

extension TranscriptController {
	private func finishLoading(_ view: TranscriptView) {
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

	func transcriptViewKeyDown(_ event: NSEvent) {
		attachedWindow?.redirectKeyDown(event)
	}

	func transcriptViewReceivedDrop(withFile filename: String) {
		AppServices.delegate.menuController?.sendDroppedFilesToSelectedChannel([filename])
	}

	/// The newest line this view printed. The IRC layer consults it when it
	/// decides what history to ask the server for.
	func lastLine() -> LogLine? {
		lastLineStorage
	}
}

/** What a caller's completion block is told about the line it printed.

 A value, and only ever read: the client and the channel are weak because the
 completion may run after either has been torn down, and everything else is the
 rendered outcome the caller asked to hear about. */
struct PrintedLineContext {
	private(set) weak var client: Client?
	private(set) weak var channel: Channel?
	let isHighlight: Bool
	let logLine: LogLine
	let lineNumber: String
	var isDuplicate = false
	var isDisplayed = true

	init(client: Client, channel: Channel?, highlight: Bool, logLine: LogLine, lineNumber: String) {
		self.client = client
		self.channel = channel
		isHighlight = highlight
		self.logLine = logLine
		self.lineNumber = lineNumber
	}
}
