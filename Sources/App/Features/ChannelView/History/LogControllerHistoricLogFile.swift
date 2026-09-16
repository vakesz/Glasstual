/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

/** What the app knows about the lines of one view, kept in memory so that chat
 history replayed by the server can be checked against the local scrollback.
 The index is filled from every line written and every line fetched, and
 withdrawn again when the store prunes the row behind it — otherwise it would
 hold a second copy of every message the process has ever seen.

 The two lookups are counted rather than set-valued: two lines can carry the
 same body at the same second from the same nickname, and dropping one of them
 must not make the other invisible to the duplicate check.

 The index itself is a value with no reference-typed state; the facade below
 owns the only copies and keeps them on the main actor. */
private nonisolated struct HistoricLogViewIndex: Sendable { // nonisolated: value
	/// What one indexed line contributed, so the contribution can be withdrawn
	/// when the line goes. `nil` where the line carried no such value.
	struct Contribution: Sendable {
		var messageIdentifier: String?
		var fallbackKey: String?
		var receivedAt: Date
		var isConversation: Bool
	}

	private struct Entry: Sendable {
		let contribution: Contribution
		let generation: UUID
	}

	private(set) var messageIdentifiers: [String: Int] = [:]
	private(set) var fallbackKeys: [String: Int] = [:]
	private var contributions: [String: Entry] = [:]
	private var generation = UUID()
	private(set) var newestDate: Date?
	/** The newest line a person wrote, as opposed to one the client narrated.

	 A read marker is answered against this rather than `newestDate`: joining a
	 channel prints a topic, a mode and a join line stamped now, and none of them
	 is news the badge should count. */
	private(set) var newestConversationDate: Date?

	/// Records what `uniqueIdentifier` contributes, and reports whether this
	/// call added it. A line the index already holds is left alone: the same
	/// row is indexed again on every fetch.
	@discardableResult
	mutating func add(
		_ contribution: Contribution,
		for uniqueIdentifier: String
	) -> Bool {
		guard uniqueIdentifier.isEmpty == false else {
			retain(contribution)
			return false
		}
		guard contributions[uniqueIdentifier] == nil else { return false }
		contributions[uniqueIdentifier] = Entry(contribution: contribution, generation: generation)
		retain(contribution)
		newestDate = max(newestDate ?? contribution.receivedAt, contribution.receivedAt)
		if contribution.isConversation {
			newestConversationDate = max(newestConversationDate ?? contribution.receivedAt, contribution.receivedAt)
		}
		return true
	}

	/// Later writes belong to a new generation. A successful deletion only
	/// withdraws the generations that existed when it was requested.
	mutating func beginRemoval() -> Set<UUID> {
		let removed = Set(contributions.values.map(\.generation))
		generation = UUID()
		return removed
	}

	mutating func remove(generations: Set<UUID>) {
		let identifiers = contributions.filter { generations.contains($0.value.generation) }.map(\.key)
		for identifier in identifiers {
			remove(identifier, updateDates: false)
		}
		refreshDates()
	}

	/// Withdraws what a pruned line contributed.
	mutating func remove(_ uniqueIdentifier: String, updateDates: Bool = true) {
		guard let contribution = contributions.removeValue(forKey: uniqueIdentifier)?.contribution else { return }
		Self.release(contribution.messageIdentifier, from: &messageIdentifiers)
		Self.release(contribution.fallbackKey, from: &fallbackKeys)
		if updateDates, contribution.receivedAt == newestDate || contribution.receivedAt == newestConversationDate {
			refreshDates()
		}
	}

	private mutating func refreshDates() {
		newestDate = contributions.values.map(\.contribution.receivedAt).max()
		newestConversationDate = contributions.values.filter(\.contribution.isConversation)
			.map(\.contribution.receivedAt).max()
	}

	private mutating func retain(_ contribution: Contribution) {
		if let messageIdentifier = contribution.messageIdentifier {
			messageIdentifiers[messageIdentifier, default: 0] += 1
		}
		if let fallbackKey = contribution.fallbackKey {
			fallbackKeys[fallbackKey, default: 0] += 1
		}
	}

	private static func release(_ key: String?, from counts: inout [String: Int]) {
		guard let key, let count = counts[key] else { return }
		if count <= 1 {
			counts.removeValue(forKey: key)
		} else {
			counts[key] = count - 1
		}
	}
}

/** The main-actor facade for scrollback history.

 It owns the duplicate index — main-actor state, read synchronously by the IRC
 layer when it decides whether a replayed history line is one it already has —
 and forwards storage work to `HistoricLogClient`. */
@MainActor
public final class LogControllerHistoricLogFile {
	public static let shared = LogControllerHistoricLogFile()

	/// One storage operation, run on the main actor in its view's order.
	typealias Operation = @MainActor @Sendable () async -> Void

	/** One view's writes and removals, in the order they were asked for.

	 A serial lane per view rather than one for the whole process: a write
	 must land before a later removal of the same view, and a fetch has to see
	 the writes queued ahead of it, but nothing about one conversation waits on
	 another's. The store serializes the transactions themselves. */
	private struct Lane {
		let identifier = UUID()
		let operations: AsyncStream<Operation>.Continuation
		let pump: Task<Void, Never>
		var pendingOperations = 0
		var retiresWhenIdle = false
	}

	private var viewIndexes: [String: HistoricLogViewIndex] = [:]
	private let client: HistoricLogClient
	let recovery = TranscriptHistoryRecoveryState()
	private var lanes: [String: Lane] = [:]
	var activeLaneCount: Int {
		lanes.count
	}

	private var terminationTask: Task<Void, Never>?
	private enum Termination {
		case none
		case pending([@MainActor @Sendable () -> Void])
	}

	private var termination = Termination.none

	init(client: HistoricLogClient = .shared) {
		self.client = client
	}

	isolated deinit {
		for lane in lanes.values {
			lane.operations.finish()
			lane.pump.cancel()
		}
		terminationTask?.cancel()
	}

	private func lane(for viewIdentifier: String) -> Lane {
		if let lane = lanes[viewIdentifier] {
			return lane
		}
		let (stream, continuation) = AsyncStream<Operation>.makeStream()
		let lane = Lane(operations: continuation, pump: Task {
			for await operation in stream {
				await operation()
			}
		})
		lanes[viewIdentifier] = lane
		return lane
	}

	/// Queues `operation` behind the view's earlier ones, and reports whether
	/// the lane took it.
	@discardableResult
	private func enqueue(_ operation: @escaping Operation, forView viewIdentifier: String) -> Bool {
		let lane = lane(for: viewIdentifier)
		lanes[viewIdentifier]?.pendingOperations += 1
		if case .terminated = lane.operations.yield({ [weak self] in
			await operation()
			self?.completedOperation(forView: viewIdentifier, laneIdentifier: lane.identifier)
		}) {
			completedOperation(forView: viewIdentifier, laneIdentifier: lane.identifier)
			return false
		}
		return true
	}

	private func completedOperation(forView viewIdentifier: String, laneIdentifier: UUID) {
		guard lanes[viewIdentifier]?.identifier == laneIdentifier else { return }
		lanes[viewIdentifier]?.pendingOperations -= 1
		if let lane = lanes[viewIdentifier], lane.retiresWhenIdle, lane.pendingOperations == 0 {
			lanes.removeValue(forKey: viewIdentifier)
			lane.operations.finish()
		}
	}

	/// Returns once everything already queued for the view has run.
	private func drain(view viewIdentifier: String) async {
		guard lanes[viewIdentifier] != nil else { return }
		await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
			if !enqueue({ continuation.resume() }, forView: viewIdentifier) {
				continuation.resume()
			}
		}
	}

	/// Returns once every view's queued operations have run.
	private func drainAllViews() async {
		for viewIdentifier in Array(lanes.keys) {
			await drain(view: viewIdentifier)
		}
	}

	// MARK: - Process life cycle

	public func resetMaximumLineCount() {
		Task { await client.applyMaximumLineCount() }
	}

	public func prepareForApplicationTermination(
		completionBlock: (@MainActor @Sendable () -> Void)? = nil
	) {
		if case var .pending(completions) = termination {
			if let completionBlock {
				completions.append(completionBlock)
			}
			termination = .pending(completions)
			return
		}
		termination = .pending(completionBlock.map { [$0] } ?? [])
		terminationTask = Task { @MainActor in
			await drainAllViews()
			let result = await client.prepareForTermination()
			if case let .failed(reason) = result {
				recovery.storageFailure = reason
				return
			}
			if case let .pending(completions) = termination {
				termination = .none
				for completion in completions {
					completion()
				}
			}
		}
	}

	/// Raised when the store cannot open its database.
	static func reportConnectionFailure(_ message: String) {
		Alerts.alert(
			withMessage: message,
			title: PromptStrings.Logging.scrollbackFailureTitle,
			defaultButton: PromptStrings.Action.confirmation,
			alternateButton: nil
		)
	}

	/// The store is about to drop these lines. The duplicate index is pruned
	/// first, and unconditionally: it outlives any view controller.
	static func noteWillDeleteLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		shared.forgetLines(uniqueIdentifiers, inView: viewIdentifier)

		guard let item = AppController.shared.world?.findItem(withId: viewIdentifier) else {
			return
		}

		item.logController?.notifyHistoricLogWillDeleteLines(uniqueIdentifiers)
	}

	// MARK: - Duplicate index

	private static func fallbackKey(
		for date: Date?,
		nickname: String?,
		messageBody: String?
	) -> String? {
		guard let date, let messageBody else {
			return nil
		}

		/* Server timestamps carry millisecond precision. Rounding to the
		 millisecond keeps a value parsed twice from the same string equal.

		 A date so far from the epoch that its millisecond count leaves `Int64`
		 cannot have been written by anything that reads it back, so it gets no
		 fallback key rather than trapping the conversion. */
		guard let milliseconds = Int64(exactly: (date.timeIntervalSince1970 * 1000.0).rounded()) else {
			return nil
		}
		return String(format: "%lld\u{001f}%@\u{001f}%@", milliseconds, nickname ?? "", messageBody)
	}

	/// Indexes `logLine` for the duplicate checks, and reports whether this call
	/// added it rather than finding it already there.
	@discardableResult
	public func indexLogLine(_ logLine: LogLine, forView viewIdentifier: String) -> Bool {
		let messageIdentifier = logLine.messageIdentifier

		return viewIndexes[viewIdentifier, default: HistoricLogViewIndex()].add(
			HistoricLogViewIndex.Contribution(
				messageIdentifier: messageIdentifier?.isEmpty == false ? messageIdentifier : nil,
				fallbackKey: Self.fallbackKey(
					for: logLine.receivedAt,
					nickname: logLine.nickname,
					messageBody: logLine.messageBody
				),
				receivedAt: logLine.receivedAt,
				isConversation: logLine.lineType.isConversation
			),
			for: logLine.uniqueIdentifier
		)
	}

	public func indexLogLines(_ logLines: [LogLine], forView viewIdentifier: String) {
		for logLine in logLines {
			indexLogLine(logLine, forView: viewIdentifier)
		}
	}

	/// Withdraws the lines the store has pruned from the view's index.
	func forgetLines(_ uniqueIdentifiers: [String], inView viewIdentifier: String) {
		for uniqueIdentifier in uniqueIdentifiers {
			viewIndexes[viewIdentifier]?.remove(uniqueIdentifier)
		}
	}

	public func containsMessageIdentifier(_ messageIdentifier: String, forView viewIdentifier: String) -> Bool {
		viewIndexes[viewIdentifier]?.messageIdentifiers[messageIdentifier] != nil
	}

	public func containsLine(
		receivedAt: Date,
		nickname: String?,
		messageBody: String,
		forView viewIdentifier: String
	) -> Bool {
		guard let index = viewIndexes[viewIdentifier],
		      let fallbackKey = Self.fallbackKey(
		      	for: receivedAt,
		      	nickname: nickname,
		      	messageBody: messageBody
		      )
		else {
			return false
		}

		return index.fallbackKeys[fallbackKey] != nil
	}

	public func newestLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestDate
	}

	/// The newest stored line a person wrote. What a read marker is compared
	/// against; `newestLineDate` is what a history request asks from.
	public func newestConversationLineDate(forView viewIdentifier: String) -> Date? {
		viewIndexes[viewIdentifier]?.newestConversationDate
	}

	// MARK: - Writing

	public func writeNewEntry(with logLine: LogLine, forView viewIdentifier: String) {
		writeNewEntry(logLine.historicEntry(forView: viewIdentifier), for: logLine)
	}

	/** Queues an archived line for storage.

	 The entry is the line archived for its view, which a caller that renders
	 off the main actor has already done there. The line is indexed now rather
	 than once the store accepts it: the next line from the same burst is
	 checked against the index in the same turn, before any write could have
	 finished. A write that fails withdraws what it added. */
	func writeNewEntry(_ entry: HistoricLogEntry, for logLine: LogLine) {
		let viewIdentifier = entry.viewIdentifier
		let indexed = indexLogLine(logLine, forView: viewIdentifier)
		let client = client
		enqueue({ [weak self] in
			let outcome = await client.writeEntry(entry)
			guard let self else { return }
			if case .accepted = outcome {
				// A preceding clear may have removed an earlier contribution
				// with this identity while the replacement write was queued.
				indexLogLine(logLine, forView: viewIdentifier)
				return
			}
			if indexed {
				forgetLines([logLine.uniqueIdentifier], inView: viewIdentifier)
			}
			recovery.storageFailure = switch outcome {
			case let .failed(reason): reason
			case .accepted, .unavailable: PromptStrings.Logging.scrollbackFailureBody
			}
		}, forView: viewIdentifier)
	}

	/// Drops a view's history. `forget` also drops what the store remembers
	/// about the view itself, which is what a channel being removed asks for;
	/// clearing a conversation the reader is still in does not.
	/// The returned task finishes when the removal has run, for a caller that
	/// has to know; the removal itself takes its turn in the view's lane either
	/// way.
	@discardableResult
	public func removeHistory(forView viewIdentifier: String, forget: Bool) -> Task<Void, Never> {
		let client = client
		let removedGenerations = viewIndexes[viewIdentifier]?.beginRemoval() ?? []
		let (finished, finish) = AsyncStream<Void>.makeStream()
		let queued = enqueue({ [weak self] in
			defer { finish.finish() }
			let outcome = await client.removeHistory(viewIdentifier, forget: forget)
			guard let self else { return }
			switch outcome {
			case .deleted:
				viewIndexes[viewIdentifier]?.remove(generations: removedGenerations)
				if forget {
					lanes[viewIdentifier]?.retiresWhenIdle = true
					if viewIndexes[viewIdentifier]?.newestDate == nil {
						viewIndexes.removeValue(forKey: viewIdentifier)
					}
				}
				recovery.deletionFailures.removeValue(forKey: viewIdentifier)
			case let .failed(reason): recovery.deletionFailures[viewIdentifier] = reason
			case .unavailable: recovery.deletionFailures[viewIdentifier] = PromptStrings.Logging.scrollbackFailureBody
			}
		}, forView: viewIdentifier)
		if queued == false {
			finish.finish()
		}
		return Task {
			for await _ in finished {}
		}
	}

	func retryLoading() async -> Bool {
		await terminationTask?.value
		await drainAllViews()
		guard await client.retryLoading() else { return false }
		switch await client.saveData() {
		case .saved:
			if case let .pending(completions) = termination {
				if case let .failed(reason) = await client.prepareForTermination() {
					recovery.storageFailure = reason
					return false
				}
				termination = .none
				recovery.storageFailure = nil
				for completion in completions {
					completion()
				}
			} else {
				recovery.storageFailure = nil
			}
			return true
		case let .failed(reason): recovery.storageFailure = reason; return false
		}
	}

	func fetchOutcome(_ request: HistoricLogFetchRequest) async -> HistoricLogFetchOutcome {
		await drain(view: request.viewIdentifier)
		return await client.fetchOutcome(request)
	}
}
