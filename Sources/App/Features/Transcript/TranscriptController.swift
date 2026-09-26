// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Foundation
import os

private nonisolated let transcriptControllerLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "TranscriptController"
)

/// What a print's render job hands back: the row to draw, and the line already
/// archived for the view's store.
private nonisolated struct PrintedLineRender: Sendable {
	let result: TranscriptRenderResult
	let scrollbackEntry: ScrollbackEntry?
}

@MainActor
final class TranscriptController: ChatItemPresenting, ServerHistoryPresenting {
	private(set) var backingView: TranscriptView?
	/// Where the commands the reader raises in this transcript are carried out.
	let commandSink: TranscriptCommandSink
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
	 `TranscriptController+HistoryLoading.swift`: the initial replay, the scrollback
	 pages and the server-history handshake. Local load status lives in
	 ``historyRecovery``; the server handshake remains separate. */
	var olderHistoryTask: Task<Void, Never>?
	var locallyExhaustedBefore: String?
	/// Where this transcript stands with the server's own history. None of it is
	/// observable, so every change to it is mirrored into the banner state here.
	var serverHistory = ServerHistoryHandshake() {
		didSet {
			historyRecovery.serverFailed = serverHistory.failed
			historyRecovery.serverFailureReason = serverHistory.failed ? serverHistory.failureReason : nil
			refreshServerRetryAvailability()
		}
	}

	let historyRecovery = TranscriptHistoryRecovery()
	/// The process-wide storage failures, which the banner composes with this
	/// view's own. Owned by the scrollback facade, not by any one transcript.
	var storageRecovery: ScrollbackStorageRecovery {
		scrollback.recovery
	}

	var historyRetryTask: Task<Void, Never>?
	var olderHistoryFailed: Bool {
		historyRecovery.olderFailure != nil
	}

	var historyPageFetcher: @Sendable @concurrent (ScrollbackFetchRequest) async
		-> ScrollbackFetchOutcome
	/** Whether the first history read waits until the view becomes visible.

	 A closure rather than a direct read so a test can pin the decision for one
	 controller; writing `SettingsKeys.Logging.loadHistoryLazily` instead would
	 change what every other suite running beside it sees. Read on each reload,
	 so a setting change still takes effect at once. */
	var loadsHistoryLazily: @MainActor () -> Bool = { SettingsKeys.Logging.loadHistoryLazily.value }

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

	/** The reactions that arrived this session, by the message they answer.

	 Only for messages this controller still holds, in the view or in its
	 projection, or is about to: a reaction for anything else has no row to be
	 drawn on. Retired with the last row of their message. */
	private(set) var reactions = TranscriptReactionLedger()
	private(set) var viewLoadedTimestamp: TimeInterval = 0
	var lastLineStorage: ChatLine?
	/** The lines handed to `print` that have not been applied to the view yet.

	 Rendering continues off the main actor, so `displayedLines` is empty for a
	 line printed in this turn. The read marker a server sends arrives in the same
	 turn as the burst it refers to, and answering it from the view alone would
	 miss every line of that burst.

	 The invariant is that what the pipeline drops, the seams forget: a line
	 leaves this list when it is applied, when the queued jobs are cancelled, and
	 when the view is torn down, so nothing here is ever a line the view will
	 never show. Single-purpose: the two conversation seams of
	 ``ChatItemPresenting`` — `newestConversationLineDate()` and
	 `conversationLineCount(after:)` — and `holdsMessage(withIdentifier:)` are the
	 only readers. */
	var linesAwaitingRender: ArraySlice<ChatLine> {
		awaitingRender.lines
	}

	private var awaitingRender = PendingLineQueue()
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

	 Both references are weak, and both are optional to read. The chat session owns
	 the server sessions and each session owns its conversations; the window's
	 registry owns the controllers and drops them by identifier, so a controller
	 can still be reached for as long as the removal is in flight -- which is why
	 every read here is a `guard let`. The session used to be declared implicitly
	 unwrapped, which promised the opposite of what those guards say and left an
	 unwrap in reach that would have trapped exactly when the guards were right. */
	private(set) weak var associatedSession: ServerSession?
	private(set) weak var associatedConversation: Conversation?
	/// The item's identifier, which never changes once the controller is attached.
	private(set) var uniqueIdentifier = ""

	var associatedItem: ChatItem? {
		associatedConversation ?? associatedSession
	}

	var numberOfLines: UInt {
		UInt(backingView?.displayedBounds.count ?? transcriptProjection.lineCount)
	}

	var inlineMediaEnabledForView: Bool {
		guard let conversation = associatedConversation else {
			return false
		}
		let config = conversation.config
		return SettingsKeys.Messages.showInlineMedia.detachedValue ? !config.inlineMediaDisabled : config
			.inlineMediaEnabled
	}

	var viewIsVisible: Bool {
		guard let attachedWindow else {
			return false
		}
		if let associatedConversation {
			return attachedWindow.isItemVisible(associatedConversation)
		}
		guard let associatedSession else {
			return false
		}
		return attachedWindow.isItemVisible(associatedSession)
	}

	convenience init(session: ServerSession, in window: MainWindow, commands: TranscriptCommandSink = .menuController()) {
		self.init(session: session, in: window, inlineImageLoader: .shared, commands: commands)
	}

	init(
		session: ServerSession, in window: MainWindow, inlineImageLoader: InlineImageLoader,
		scrollback: Scrollback = .shared, commands: TranscriptCommandSink = .menuController()
	) {
		self.inlineImageLoader = inlineImageLoader
		self.scrollback = scrollback
		commandSink = commands
		historyPageFetcher = { await scrollback.fetchOutcome($0) }
		associatedSession = session
		uniqueIdentifier = session.uniqueIdentifier
		attachedWindow = window
		setUp()
	}

	init(conversation: Conversation, in window: MainWindow, commands: TranscriptCommandSink = .menuController()) {
		inlineImageLoader = .shared
		scrollback = .shared
		commandSink = commands
		let storage = scrollback
		historyPageFetcher = { await storage.fetchOutcome($0) }
		associatedSession = conversation.associatedSession
		associatedConversation = conversation
		uniqueIdentifier = conversation.uniqueIdentifier
		attachedWindow = window
		setUp()
	}

	private func setUp() {
		transcriptProjection.setCapacity(bufferPolicy.hardLimit)
		startPipeline()
	}

	isolated deinit {
		associatedSession?.renderAdmission.retire(view: uniqueIdentifier)
		historyRetryTask?.cancel()
		pipelineTask?.cancel()
		olderHistoryTask?.cancel()
		applicationTask?.cancel()
		backingView?.clearLines()
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
	}

	var bufferPolicy: TranscriptBufferLimits {
		TranscriptBufferLimits(setting: SettingsKeys.Logging.scrollbackVisibleLimit.value)
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
		associatedSession?.renderAdmission.retire(view: uniqueIdentifier)
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
		awaitingRender.removeAll()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		/* The dropped jobs include whatever was going to finish the replay, so
		 the latch has to be released here rather than waiting for a completion
		 that is never going to arrive. */
		historyRecovery.cancelReload()
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
		historyRecovery.endOlderPage()
		locallyExhaustedBefore = nil
		if let retiredRequest = serverHistory.reset() {
			associatedSession?.cancelServerHistoryRequest(retiredRequest)
		}
		historyRecovery.olderFailure = nil
	}

	func acceptsRenderGeneration(_ generation: Int) -> Bool {
		renderGeneration == generation && !terminating
	}

	private func forgetScrollback() {
		guard let associatedItem else {
			return
		}
		scrollbackMutationTask = scrollback.removeHistory(forView: associatedItem.uniqueIdentifier, forget: true)
	}

	private func resetScrollback() {
		guard let associatedItem else {
			return
		}
		scrollbackMutationTask = scrollback.removeHistory(forView: associatedItem.uniqueIdentifier, forget: false)
	}

	private func closeScrollback() {
		let conversation = associatedConversation
		if !SettingsKeys.Logging.reloadScrollbackOnLaunch.value || conversation?.isConsole == true || conversation?
			.isDirectChat == true ||
			(conversation?.isDirect == true && !SettingsKeys.Appearance.rememberDirectConversations.value)
		{
			resetScrollback()
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
		awaitingRender.removeAll()
		refreshServerRetryAvailability()
		cancelOlderHistory()
		pendingApplications.removeAll()
		deferredPrepends.removeAll()
		applicationTask?.cancel()
		applicationTask = nil
		viewIsLoaded = false
		reactions.removeAll()
		backingView?.clearLines()
		backingView = nil
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		stopPipeline()
		switch reason {
		case .applicationTermination: closeScrollback()
		case .permanentRemoval: forgetScrollback()
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
	 capture a `ChatLine`, a caller's completion block or anything else the view
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
		let admission = associatedSession?.renderAdmission
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
				self.queueApplication(generation: generation) {
					defer {
						if let ticket {
							admission?.finish(ticket)
						}
					}
					apply(output)
				}
			}
		})
		return true
	}

	/** Queues one finished render for application, and starts the drain if it is
	 not already running.

	 The generation is checked once more where it can have moved: the queued work
	 runs after a `Task.yield`, and the check the caller made ran before it. */
	private func queueApplication(generation: Int, _ apply: @escaping @MainActor () -> Void) {
		pendingApplications.append { [weak self] in
			guard let self, acceptsRenderGeneration(generation) else { return }
			apply()
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
	 building them is a walk of the member list after every join or part: a line
	 that is not a message leaves them out, and its sender's mark is looked up
	 by the caller instead. */
	func makeRenderContext(includingMembers: Bool = true) -> TranscriptRenderContext {
		let conversation = associatedConversation
		return TranscriptRenderContext(
			inlineMediaEnabled: inlineMediaEnabledForView,
			isChannel: conversation?.isChannel == true,
			showsDateChanges: SettingsKeys.Messages.showDateChanges.value,
			textPolicy: .current(),
			members: includingMembers ? memberRenderCache.members(in: conversation) : [],
			caseMapping: associatedSession?.supportInfo.caseMapping ?? .rfc1459,
			sessionReactions: reactions.all
		)
	}

	private func setInitialTopic() {
		setTopicNow(associatedConversation?.topic)
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
		let mark = (newestLineNumber ?? lastLineStorage?.uniqueIdentifier).map(UnreadMarker.line) ?? .latest
		transcriptProjection.setMark(mark)
		backingView?.setUnreadMarker(mark)
	}

	func mark(at date: Date) {
		transcriptProjection.setMark(.after(date))
		backingView?.setUnreadMarker(.after(date))
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

	func updateTextScale() {
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

	/// The view dropped these lines. Only the highlight the reader last jumped
	/// to is addressed by line number, so it is the only cursor a removal can
	/// leave pointing at nothing.
	func notifyLinesWereRemoved(_ lineNumbers: [String]) {
		guard !terminating else {
			return
		}
		transcriptProjection.retireDisplayedLines(lineNumbers)
		forgetRetiredProjectionMessages()
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
		guard let url = URL(string: address), LinkSchemeRules.isWebURL(url)
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
		resetScrollback()
		transcriptProjection.reset()
		transcriptSessionBoundary.reset()
		newestLineNumberFromPreviousSession = nil
		reactions.removeAll()
		lastVisitedHighlight = nil
		lastLineStorage = nil
		historyRecovery.clearLoadedHistory()
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
		if let identifier = line.messageIdentifier, let delta = reactions.reactions(forMessage: identifier) {
			line.mergeReactions(delta)
		}
		return line
	}
}

extension TranscriptController {
	func print(
		_ chatLine: ChatLine,
		completionBlock postPrintBlock: PrintedLineCompletion? = nil
	) {
		guard !terminating else {
			return
		}
		if chatLine.lineType == .mode {
			refreshTopicBar()
		}
		lastLineStorage = chatLine
		let context = makeRenderContext(includingMembers: chatLine.lineType.mentionsMembers)
		let conversation = associatedConversation
		let senderMark = conversation?.isChannel == true
			? chatLine.nickname.flatMap { conversation?.findMember($0)?.mark } ?? ""
			: ""
		let line = ChatLineSnapshot(chatLine, in: context, modeSymbol: senderMark)
		let viewIdentifier = associatedItem?.uniqueIdentifier
		let enqueued = enqueueRenderJob {
			/* Archived here, beside the render, so the main actor that applies
			 the line only hands the store a finished entry. */
			PrintedLineRender(
				result: Self.renderJob(TranscriptRenderRequest(line: line, context: context)),
				scrollbackEntry: viewIdentifier.map { chatLine.scrollbackEntry(forView: $0) }
			)
		} apply: { [weak self] (rendered: PrintedLineRender) in
			self?.applyPrintedLine(chatLine, rendered: rendered, completionBlock: postPrintBlock)
		}
		/* Only a line the pipeline took can be applied, and only an applied line
		 is withdrawn again: a job refused because the application is quitting
		 would otherwise stay awaiting a render that never comes. */
		if enqueued {
			awaitingRender.append(chatLine)
		}
	}

	private func applyPrintedLine(
		_ chatLine: ChatLine,
		rendered: PrintedLineRender,
		completionBlock postPrintBlock: PrintedLineCompletion?
	) {
		let result = rendered.result
		/* Withdrawn before any guard below, so a line one of them drops is not
		 left counted as a line that is still on its way to the view. */
		awaitingRender.withdraw(chatLine)
		guard !terminating else {
			return
		}
		/* The session can be torn down between enqueueing the line and printing
		 it; there is nothing left to attribute the line to if it has been. */
		guard let session = associatedSession, let associatedItem else {
			return
		}
		let lineNumber = result.lineNumber
		let conversation = associatedConversation
		let alreadyDisplayed = backingView?.containsLine(identifier: lineNumber) == true
		/* The same line printed again, as opposed to a different line carrying
		 a message identifier the view has already seen. It was stored when it
		 was first printed, and a second row under one line identifier is a
		 cursor history can no longer page from. */
		let alreadyPrinted = alreadyDisplayed || transcriptProjection
			.containsLine(withIdentifier: chatLine.uniqueIdentifier)
		let isDuplicate = alreadyPrinted
			|| chatLine.messageIdentifier.map { scrollback.duplicates.containsMessageIdentifier(
				$0,
				forView: associatedItem.uniqueIdentifier
			) } == true
		if result.isHighlight, !isDuplicate {
			if let conversation {
				session.cacheHighlight(in: conversation, with: chatLine)
			}
		}
		let projectionAction = transcriptProjection.record(result)
		forgetRetiredProjectionMessages()
		if case .append = projectionAction, !alreadyDisplayed {
			var displayedLine = applyingCurrentState(to: result.transcriptLine)
			if transcriptSessionBoundary.consumePendingMarker(for: result) {
				displayedLine.markers.insert(
					.currentSession(String(localized: .Transcript.currentSession)),
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
				rendered.scrollbackEntry ?? chatLine.scrollbackEntry(forView: associatedItem.uniqueIdentifier),
				for: chatLine
			)
		}
		/* The body was scanned against the member snapshot the line rendered
		 with; the conversation weight belongs to whoever is in it now. */
		if let conversation {
			let direction: MemberConversationDirection = chatLine.memberType == .localUser ? .outgoing : .mention
			for nickname in result.mentionedNicknames where conversation.findMember(nickname) != nil {
				conversation.recordConversation(with: nickname, direction: direction)
			}
		}
		var context = PrintedLineContext(
			session: session,
			conversation: conversation,
			highlight: result.isHighlight,
			chatLine: chatLine,
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
		guard holdsMessage(withIdentifier: messageIdentifier),
		      let merged = reactions.record(wireEmoji, from: nickname, forMessage: messageIdentifier)
		else {
			return
		}
		/* A view that is still replaying history has not drawn the line yet; the
		 reactions are handed to it when the replay finishes. */
		guard transcriptProjection.phase == .active else {
			return
		}
		enqueueMainActorWork { [weak self] in
			self?.backingView?.updateReactions(merged, messageIdentifier: messageIdentifier)
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

	func forgetRetiredProjectionMessages() {
		forgetReactions(for: transcriptProjection.takeRetiredMessageIdentifiers())
	}

	private func forgetReactions(for identifiers: [String]) {
		reactions.forget(identifiers) { [self] identifier in
			backingView?.document.ordinals(ofMessage: identifier) != nil
				|| transcriptProjection.containsMessage(withIdentifier: identifier)
		}
	}

	func updateDeliveryState(
		forLineNumber lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		guard let update = transcriptProjection.updateDelivery(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason,
			isDisplayed: backingView?.containsLine(identifier: lineNumber) == true
		) else { return }
		forgetRetiredProjectionMessages()
		guard transcriptProjection.phase == .active else {
			return
		}
		enqueueMainActorWork { [weak self] in
			guard let self else { return }
			let previousIdentifier: String? = if let backingView, let index = backingView.document.index(ofLine: update.lineNumber) {
				backingView.document[index].messageIdentifier
			} else {
				nil
			}
			backingView?.updateDelivery(update)
			transcriptProjection.deliveryWasApplied(update)
			forgetRetiredProjectionMessages()
			if let previousIdentifier, previousIdentifier != update.messageIdentifier {
				forgetReactions(for: [previousIdentifier])
			}
			if let identifier = update.messageIdentifier,
			   let merged = reactions.reactions(forMessage: identifier)
			{
				backingView?.updateReactions(merged, messageIdentifier: identifier)
			}
		}
	}
}

extension TranscriptController {
	private func finishLoading(_ view: TranscriptView) {
		guard !viewIsLoaded,
		      let associatedSession,
		      let attachedWindow
		else {
			return
		}
		withExtendedLifetime((associatedSession, attachedWindow)) {
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
		commandSink.sendDroppedFiles([filename])
	}
}

/** What the IRC layer sees of a transcript. Every requirement is answered by
 the controller's own state; the protocol is what lets a chat item hold one
 without depending on the concrete `TranscriptController`. */
extension TranscriptController {
	var presentationIdentifier: String {
		uniqueIdentifier
	}

	/// The newest line this view printed. The IRC layer consults it when it
	/// decides what history to ask the server for.
	func lastPrintedLine() -> ChatLine? {
		lastLineStorage
	}

	func lastRenderedLineDate() -> Date? {
		backingView?.displayedLines.filter {
			ChatHistoryPolicy.marksReadPosition(lineType: $0.lineType, messageIdentifier: $0.messageIdentifier)
		}.map(\.receivedAt).max()
	}

	/** Both conversation seams answer from the union of what the view is showing
	 and what it has been handed but not applied yet. A line moves from the second
	 to the first synchronously on the main actor, so neither holds it twice.

	 Lines loaded from storage are in neither list, which is why
	 `newestKnownConversationLineDate(for:)` combines this with the scrollback's
	 duplicate index: history seeding fills that index synchronously, so it already
	 accounts for the scrollback. */
	func newestConversationLineDate() -> Date? {
		let displayed = backingView?.displayedLines.filter(\.lineType.isConversation).map(\.receivedAt) ?? []
		let awaiting = linesAwaitingRender.filter(\.lineType.isConversation).map(\.receivedAt)

		return (displayed + awaiting).max()
	}

	func conversationLineCount(after date: Date) -> Int {
		let displayed = backingView?.displayedLines
			.count { $0.lineType.isConversation && $0.receivedAt > date } ?? 0

		return displayed + linesAwaitingRender.count { $0.lineType.isConversation && $0.receivedAt > date }
	}
}
