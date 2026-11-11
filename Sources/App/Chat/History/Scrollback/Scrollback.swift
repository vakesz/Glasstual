// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The main-actor facade for scrollback history.

 What the process knows about the lines already stored lives in ``duplicates``,
 and the two-phase save termination performs in ``ScrollbackTermination``; this
 type owns neither, it only drives them. Storage work goes to
 ``ScrollbackSession``, which runs it in the order it was asked for. */
@MainActor
final class Scrollback {
	/// What every view has stored, as far as this process knows. Read
	/// synchronously by the IRC layer when it decides whether a replayed history
	/// line is one it already has.
	let duplicates = ScrollbackDuplicateIndex()
	private let session: ScrollbackSession
	let recovery = ScrollbackStorageRecovery()

	private let termination = ScrollbackTermination()
	private let notifications = NotificationSubscriptions()

	init(session: ScrollbackSession = .shared) {
		self.session = session

		/* The stored-line ceiling is this type's, so it answers the setting
		 itself. Nothing is missed while no scrollback exists yet: the session
		 reads the ceiling again whenever it opens the database. */
		notifications.observeSynchronously(SettingsReloadRequest.self) { [weak self] request in
			guard request.action.contains(.scrollbackSaveLimit) else { return }
			self?.resetMaximumLineCount()
		}
	}

	// MARK: - Process life cycle

	func resetMaximumLineCount() {
		session.enqueueMaximumLineCountUpdate()
	}

	func prepareForApplicationTermination(
		completionBlock: (@MainActor @Sendable () -> Void)? = nil
	) {
		guard termination.addCompletion(completionBlock) else { return }
		termination.save { [self] in
			await session.drain()
			if case let .failed(reason) = await session.prepareForTermination() {
				recovery.storageFailure = reason
				return
			}
			termination.complete()
		}
	}

	/** The store is about to drop these lines, so the duplicate index withdraws
	 what they contributed. Storage's own bookkeeping and nothing else: the
	 transcript retires its cursors when the rows leave the document, which is
	 the only place a line the reader can still address goes. */
	static func noteWillDeleteLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		shared.duplicates.forgetLines(uniqueIdentifiers, inView: viewIdentifier)
	}

	/// A save the store made on its own did not land. Reported as a failed write
	/// is: the reason is what the recovery banner shows.
	static func noteSaveFailure(_ reason: String) {
		shared.recovery.storageFailure = reason
	}

	// MARK: - Writing

	/** Queues an archived line for storage.

	 The entry is the line archived for its view, which a caller that renders
	 off the main actor has already done there. The line is indexed now rather
	 than once the store accepts it: the next line from the same burst is
	 checked against the index in the same turn, before any write could have
	 finished. A write that fails withdraws what it added. */
	func writeNewEntry(_ entry: ScrollbackEntry, for chatLine: ChatLine) {
		let viewIdentifier = entry.viewIdentifier
		let indexed = duplicates.indexChatLine(chatLine, forView: viewIdentifier)
		defer { applyPendingRedaction(to: chatLine, inView: viewIdentifier) }
		session.write(entry) { [weak self] outcome in
			guard let self else { return }
			if case .accepted = outcome {
				// A preceding clear may have removed an earlier contribution
				// with this identity while the replacement write was queued.
				duplicates.indexChatLine(chatLine, forView: viewIdentifier)
				return
			}
			if indexed {
				duplicates.forgetLines([chatLine.uniqueIdentifier], inView: viewIdentifier)
			}
			recovery.storageFailure = switch outcome {
			case let .failed(reason): reason
			case .accepted, .unavailable: PromptStrings.Logging.scrollbackFailureBody
			}
		}
	}

	/// Updates a confirmed outgoing message without inserting a second history row.
	func replaceEntry(_ entry: ScrollbackEntry, for line: ChatLine) {
		duplicates.replaceChatLine(line, forView: entry.viewIdentifier)
		session.replace(entry) { [weak self] outcome in
			guard let self else { return }
			switch outcome {
			case .replaced, .missing: break
			case .unavailable: recovery.storageFailure = PromptStrings.Logging.scrollbackFailureBody
			case let .failed(reason): recovery.storageFailure = reason
			}
		}
	}

	/** Overwrites the stored line a redaction names, so the deleted text is
	 gone from history and not only from the screen.

	 A redaction can arrive before the line it names has been stored, as a
	 history replay or a line still rendering. The identifier is then kept and
	 applied the moment such a line is written, so the text is never stored
	 after it was deleted. */
	func redactMessage(withIdentifier messageIdentifier: String, inView viewIdentifier: String) {
		guard messageIdentifier.isEmpty == false else { return }
		session.redact(messageIdentifier: messageIdentifier, inView: viewIdentifier) { [weak self] outcome in
			guard let self else { return }
			switch outcome {
			case let .redacted(line):
				duplicates.replaceChatLine(line, forView: viewIdentifier)
				pendingRedactions[viewIdentifier]?.remove(MessageIdentifierKey(messageIdentifier))
				if pendingRedactions[viewIdentifier]?.isEmpty == true {
					pendingRedactions.removeValue(forKey: viewIdentifier)
				}
			case .missing:
				rememberPendingRedaction(messageIdentifier, inView: viewIdentifier)
			case .unavailable:
				recovery.storageFailure = PromptStrings.Logging.scrollbackFailureBody
			case let .failed(reason):
				recovery.storageFailure = reason
			}
		}
	}

	/// Message identifiers redacted before their line was stored, per view.
	/// Bounded: an identifier is dropped when it is applied, the oldest are
	/// dropped first beyond the ceiling, and a forgotten view drops them all.
	private var pendingRedactions: [String: ScrollbackPendingRedactions] = [:]
	private static let pendingRedactionLimit = 512

	private func rememberPendingRedaction(_ messageIdentifier: String, inView viewIdentifier: String) {
		pendingRedactions[viewIdentifier, default: ScrollbackPendingRedactions(limit: Self.pendingRedactionLimit)]
			.insert(MessageIdentifierKey(messageIdentifier))
	}

	/// Whether a redaction of `messageIdentifier` waits for its line in the view.
	func hasPendingRedaction(_ messageIdentifier: String, inView viewIdentifier: String) -> Bool {
		pendingRedactions[viewIdentifier]?.contains(MessageIdentifierKey(messageIdentifier)) == true
	}

	/// Whether a line about to be stored was already redacted, in which case
	/// the redaction is queued behind its write.
	private func applyPendingRedaction(to chatLine: ChatLine, inView viewIdentifier: String) {
		guard let identifier = chatLine.messageIdentifier, identifier.isEmpty == false,
		      pendingRedactions[viewIdentifier]?.contains(MessageIdentifierKey(identifier)) == true
		else { return }
		redactMessage(withIdentifier: identifier, inView: viewIdentifier)
	}

	/// Drops a view's history. `forget` also drops what the store remembers
	/// about the view itself, which is what a conversation being removed asks for;
	/// clearing a conversation the reader is still in does not.
	/// The returned task finishes when the removal has run, for a caller that
	/// has to know; the removal itself takes its turn behind the view's queued
	/// writes either way.
	@discardableResult
	func removeHistory(forView viewIdentifier: String, forget: Bool) -> Task<Void, Never> {
		let removedGenerations = duplicates.beginRemoval(inView: viewIdentifier)
		let (finished, finish) = AsyncStream<Void>.makeStream()
		let queued = session.removeHistory(forView: viewIdentifier, forget: forget) { [weak self] outcome in
			defer { finish.finish() }
			guard let self else { return }
			switch outcome {
			case .deleted:
				duplicates.removeGenerations(removedGenerations, inView: viewIdentifier)
				if forget {
					duplicates.forgetViewIfEmpty(viewIdentifier)
					/* A conversation that is gone has no line left in flight. A
					 reset keeps them: the reader is still in the view, and a
					 line still rendering there must be redacted when it lands. */
					pendingRedactions.removeValue(forKey: viewIdentifier)
				}
				recovery.deletionFailures.removeValue(forKey: viewIdentifier)
			case let .failed(reason): recovery.deletionFailures[viewIdentifier] = reason
			case .unavailable: recovery.deletionFailures[viewIdentifier] = PromptStrings.Logging.scrollbackFailureBody
			}
		}
		if queued == false {
			finish.finish()
		}
		return Task {
			for await _ in finished {}
		}
	}

	func retryLoading() async -> Bool {
		await termination.waitForSave()
		await session.drain()
		guard await session.retryLoading() else { return false }
		switch await session.saveData() {
		case .saved:
			if termination.isPending {
				if case let .failed(reason) = await session.prepareForTermination() {
					recovery.storageFailure = reason
					return false
				}
				recovery.storageFailure = nil
				termination.complete()
			} else {
				recovery.storageFailure = nil
			}
			return true
		case let .failed(reason): recovery.storageFailure = reason; return false
		}
	}

	func fetchOutcome(_ request: ScrollbackFetchRequest) async -> ScrollbackFetchOutcome {
		await session.fetchOutcome(request)
	}

	/// Searches the stored text of the views the query names.
	func search(_ query: ScrollbackSearchQuery) async -> ScrollbackSearchOutcome {
		await session.search(query)
	}
}

/** The message identifiers one view was asked to redact before their lines
 were stored, oldest first.

 Kept in the order they arrived so the ceiling evicts the one that has waited
 longest, the least likely still to be in flight, rather than whichever a hash
 happens to put first. There is no expiry by age: a line can legitimately
 arrive much later, in a history page fetched after the redaction. */
struct ScrollbackPendingRedactions {
	let limit: Int
	private var order: [MessageIdentifierKey] = []
	private var members: Set<MessageIdentifierKey> = []

	init(limit: Int) {
		self.limit = max(1, limit)
	}

	var isEmpty: Bool {
		members.isEmpty
	}

	var count: Int {
		members.count
	}

	func contains(_ identifier: MessageIdentifierKey) -> Bool {
		members.contains(identifier)
	}

	/// Adds `identifier` as the newest, unless it is already waiting, and
	/// drops the oldest past the limit.
	mutating func insert(_ identifier: MessageIdentifierKey) {
		guard members.insert(identifier).inserted else { return }
		order.append(identifier)
		while order.count > limit {
			members.remove(order.removeFirst())
		}
	}

	mutating func remove(_ identifier: MessageIdentifierKey) {
		guard members.remove(identifier) != nil, let index = order.firstIndex(of: identifier) else { return }
		order.remove(at: index)
	}
}

/** The callers waiting on the save that application termination asked for.

 Termination asks once and may ask again before the save has finished, so the
 asks accumulate into one batch rather than starting a second save. The batch
 runs when a save succeeds — either the one termination started, or a later
 retry after the reader repaired the database — and a failed save leaves it
 waiting, which is what keeps the app alive long enough to try again. */
@MainActor
private final class ScrollbackTermination {
	private var pendingCompletions: [@MainActor @Sendable () -> Void]?
	private var task: Task<Void, Never>?

	isolated deinit {
		task?.cancel()
	}

	/// Whether a save has been asked for and its callers have not run yet.
	var isPending: Bool {
		pendingCompletions != nil
	}

	/// Adds `completionBlock` to the batch and reports whether this is the ask
	/// that has to start the save; a later ask joins the one already running.
	func addCompletion(_ completionBlock: (@MainActor @Sendable () -> Void)?) -> Bool {
		guard var completions = pendingCompletions else {
			pendingCompletions = completionBlock.map { [$0] } ?? []
			return true
		}
		if let completionBlock {
			completions.append(completionBlock)
			pendingCompletions = completions
		}
		return false
	}

	/// Runs the save on the main actor, replacing any earlier one.
	func save(_ operation: @escaping @MainActor @Sendable () async -> Void) {
		task?.cancel()
		task = Task { @MainActor in
			await operation()
		}
	}

	/// Returns once the save in flight has finished, if there is one.
	func waitForSave() async {
		await task?.value
	}

	/// Lets the batch go, now that the database is closed.
	func complete() {
		guard let completions = pendingCompletions else { return }
		pendingCompletions = nil
		for completion in completions {
			completion()
		}
	}
}
