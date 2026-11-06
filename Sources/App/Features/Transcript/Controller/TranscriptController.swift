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
	let highlightExpressions: TranscriptHighlightExpressions
	let scrollback: Scrollback
	private(set) var scrollbackMutationTask: Task<Void, Never>?

	var highlightCursor = TranscriptHighlightCursor()
	/// Whether any line on screen is a highlight. Cheap: the transcript counts
	/// them as it is edited, and menu validation asks for this on every pass.
	var hasHighlightedLines: Bool {
		backingView?.hasHighlightedLines == true
	}

	/** The reactions that arrived this session, by the message they answer.

	 Only for messages this controller still holds, in the view or in its
	 projection, or is about to: a reaction for anything else has no row to be
	 drawn on. Retired with the last row of their message. */
	var reactions = TranscriptReactionLedger()
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
	var awaitingRender = PendingLineQueue()
	var transcriptProjection = TranscriptProjectionState()
	var transcriptSessionBoundary = TranscriptSessionBoundaryState()

	/// This view's render pipeline and the applications it hands back.
	let renderScheduler = TranscriptRenderScheduler()

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
		highlightExpressions: TranscriptHighlightExpressions = .shared,
		scrollback: Scrollback = .shared, commands: TranscriptCommandSink = .menuController()
	) {
		self.inlineImageLoader = inlineImageLoader
		self.highlightExpressions = highlightExpressions
		self.scrollback = scrollback
		commandSink = commands
		historyPageFetcher = { await scrollback.fetchOutcome($0) }
		associatedSession = session
		uniqueIdentifier = session.uniqueIdentifier
		attachedWindow = window
		setUp()
	}

	init(conversation: Conversation, in window: MainWindow,
	     highlightExpressions: TranscriptHighlightExpressions = .shared,
	     scrollback: Scrollback = .shared, commands: TranscriptCommandSink = .menuController())
	{
		inlineImageLoader = .shared
		self.highlightExpressions = highlightExpressions
		self.scrollback = scrollback
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
		renderScheduler.start { [weak self] edits in
			if let backingView = self?.backingView {
				backingView.performEditingBatch(edits)
			} else {
				edits()
			}
		}
	}

	isolated deinit {
		associatedSession?.renderAdmission.retire(view: uniqueIdentifier)
		historyRetryTask?.cancel()
		olderHistoryTask?.cancel()
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

	/** Drops everything this view has queued and starts a fresh pipeline.

	 Invalidating first is what makes the cancellation take effect immediately:
	 a job that is already rendering finds its generation stale and applies
	 nothing, including one the history cancellation below answers. */
	private func cancelRenderJobs() {
		guard terminating == false else {
			return
		}
		renderScheduler.invalidate()
		cancelOlderHistory()
		awaitingRender.removeAll()
		/* The dropped jobs include whatever was going to finish the replay, so
		 the latch has to be released here rather than waiting for a completion
		 that is never going to arrive. */
		historyRecovery.cancelReload()
		associatedSession?.renderAdmission.retire(view: uniqueIdentifier)
		renderScheduler.restart()
	}

	func drainRenderJobs() async {
		await olderHistoryTask?.value
		await renderScheduler.drain()
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
		renderScheduler.generation == generation && !terminating
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
		renderScheduler.invalidate()
		terminating = true
		awaitingRender.removeAll()
		refreshServerRetryAvailability()
		cancelOlderHistory()
		renderScheduler.stop()
		viewIsLoaded = false
		reactions.removeAll()
		backingView?.clearLines()
		backingView = nil
		inlineImageLoader.cancelLoads(forView: uniqueIdentifier)
		associatedSession?.renderAdmission.retire(view: uniqueIdentifier)
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
		let generation = renderScheduler.generation
		let admission = associatedSession?.renderAdmission
		let ticket = admission?.submit(for: uniqueIdentifier)
		renderScheduler.submit(isStandalone: isStandalone) { [weak self] in
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
		}
		return true
	}

	/** Queues one finished render for application.

	 The generation is checked once more where it can have moved: the queued work
	 runs after a `Task.yield`, and the check the caller made ran before it. */
	private func queueApplication(generation: Int, _ apply: @escaping @MainActor () -> Void) {
		renderScheduler.enqueue { [weak self] in
			guard let self, acceptsRenderGeneration(generation) else { return }
			apply()
		}
	}

	/// Convenience for work that has nothing to do off the main actor. It still
	/// takes its turn in the pipeline, which is what keeps it in order.
	func enqueueMainActorWork(
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
			sessionReactions: reactions.all,
			highlightExpressions: highlightExpressions
		)
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
		highlightCursor.reset()
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
			line = update.applying(to: line)
		}
		if let identifier = line.messageIdentifier, let delta = reactions.reactions(forMessage: identifier) {
			line.mergeReactions(delta)
		}
		return line
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
			setTopic(associatedConversation?.topic)
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
