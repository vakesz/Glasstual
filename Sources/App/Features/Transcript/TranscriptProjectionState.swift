// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Where the transcript draws the line that says "you had read this far".

 One marker per transcript, and `none` is a real answer: a transcript the reader
 has never left has nothing to mark. */
nonisolated enum UnreadMarker: Equatable, Sendable {
	case none
	case latest
	case line(String)
	case after(Date)
}

nonisolated struct TranscriptDeliveryUpdate: Equatable, Sendable {
	let lineNumber: String
	let state: ChatLineDeliveryState
	let messageIdentifier: String?
	let reason: String?
}

/** Owns the bounded transcript while its native view does not exist or is
 rebuilding.

 What it stores is the rendered rows: a ``TranscriptRow`` is already the
 semantic form a theme change re-renders from, so keeping the archives beside
 them was a second copy of the same conversation under a second ceiling. */
nonisolated struct TranscriptProjectionState: Sendable {
	enum Phase: Equatable, Sendable {
		case dormant
		case loading
		case active
	}

	enum LiveLineAction: Sendable {
		case append
		case buffered
	}

	private(set) var phase: Phase = .dormant
	private(set) var mark: UnreadMarker = .none
	private(set) var deliveryUpdates: [String: TranscriptDeliveryUpdate] = [:]

	private var capacity: Int
	/// The retained rows, oldest first.
	private var recentResults: [TranscriptRenderResult] = []
	/// What ``recentResults`` holds, so a duplicate check is an answer rather
	/// than a walk.
	private var recentLineNumbers: Set<String> = []
	/// How many retained rows carry each message identifier.
	private var recentMessageIdentifiers: [String: Int] = [:]
	/// Message identifiers no retained row carries any longer, since the owner
	/// last took them.
	private var retiredMessageIdentifiers: [String] = []
	private var pendingResults: [TranscriptRenderResult] = []

	func containsLine(withIdentifier identifier: String) -> Bool {
		recentLineNumbers.contains(identifier)
	}

	/// Whether a retained row carries `identifier` as its message identifier.
	func containsMessage(withIdentifier identifier: String) -> Bool {
		recentMessageIdentifiers[identifier] != nil
	}

	/// The message identifiers that left with trimmed rows, for state kept per
	/// message that has nothing left to belong to.
	mutating func takeRetiredMessageIdentifiers() -> [String] {
		defer { retiredMessageIdentifiers.removeAll() }
		return retiredMessageIdentifiers
	}

	var lineCount: Int {
		recentResults.count
	}

	init(capacity: Int = TranscriptBufferLimits.defaultHardLimit) {
		self.capacity = max(capacity, 1)
	}

	mutating func setCapacity(_ capacity: Int) {
		self.capacity = max(capacity, 1)
		trimToCapacity()
	}

	mutating func record(_ result: TranscriptRenderResult) -> LiveLineAction {
		/* A line printed a second time moves to the end rather than appearing
		 twice. It is rare enough to be worth a walk when it happens, and the
		 set above is what keeps the common case from walking at all. */
		if recentLineNumbers.contains(result.lineNumber) {
			for retired in recentResults where retired.lineNumber == result.lineNumber {
				releaseMessage(of: retired)
			}
			recentResults.removeAll { $0.lineNumber == result.lineNumber }
		}
		recentResults.append(result)
		recentLineNumbers.insert(result.lineNumber)
		if let identifier = result.transcriptLine.messageIdentifier {
			retainMessage(identifier)
		}
		trimToCapacity()

		switch phase {
		case .active:
			return .append
		case .loading:
			pendingResults.append(result)
			if pendingResults.count > capacity {
				pendingResults.removeFirst(pendingResults.count - capacity)
			}
			return .buffered
		case .dormant:
			return .buffered
		}
	}

	/// The rows the projection is holding, which the replay re-draws instead of
	/// rendering them a second time.
	mutating func beginReplay() -> [TranscriptRenderResult] {
		phase = .loading
		pendingResults.removeAll(keepingCapacity: true)
		return recentResults
	}

	mutating func finishReplay(displaying lineNumbers: Set<String>) -> [TranscriptRenderResult] {
		let pending = takePendingResults(displaying: lineNumbers)
		phase = .active
		return pending
	}

	mutating func takePendingResults(displaying lineNumbers: Set<String>) -> [TranscriptRenderResult] {
		let pending = pendingResults.filter { !lineNumbers.contains($0.lineNumber) }
		pendingResults.removeAll(keepingCapacity: true)
		return pending
	}

	mutating func reset() {
		phase = .dormant
		mark = .none
		deliveryUpdates.removeAll()
		recentResults.removeAll()
		recentLineNumbers.removeAll()
		recentMessageIdentifiers.removeAll()
		retiredMessageIdentifiers.removeAll()
		pendingResults.removeAll()
	}

	mutating func setMark(_ mark: UnreadMarker) {
		self.mark = mark
	}

	mutating func updateDelivery(
		lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?
	) {
		let update = TranscriptDeliveryUpdate(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: messageIdentifier,
			reason: reason
		)
		/* An ack can arrive after its line has been trimmed away. Recording one
		 for a line the state no longer holds would keep it for the session:
		 only lines it still holds are ever trimmed from here. The row itself is
		 not rewritten -- `applyingCurrentState(to:)` folds the update in when
		 the row is drawn, which is what a replayed row needs anyway. */
		guard recentLineNumbers.contains(lineNumber) else {
			return
		}
		/* An acknowledgement is where an outgoing line first learns its
		 message identifier, so the identifier the update names counts as one
		 the row carries. */
		let previous = deliveryUpdates[lineNumber]?.messageIdentifier
		deliveryUpdates[lineNumber] = update
		if let messageIdentifier, messageIdentifier != previous {
			retainMessage(messageIdentifier)
			if let previous {
				releaseMessage(previous)
			}
		}
	}

	private mutating func trimToCapacity() {
		guard recentResults.count > capacity else {
			return
		}
		let removalCount = recentResults.count - capacity
		let removed = recentResults.prefix(removalCount)
		for result in removed {
			recentLineNumbers.remove(result.lineNumber)
			if let acknowledged = deliveryUpdates.removeValue(forKey: result.lineNumber)?.messageIdentifier {
				releaseMessage(acknowledged)
			}
			releaseMessage(of: result)
		}
		recentResults.removeFirst(removalCount)
	}

	private mutating func releaseMessage(of result: TranscriptRenderResult) {
		if let identifier = result.transcriptLine.messageIdentifier {
			releaseMessage(identifier)
		}
	}

	private mutating func retainMessage(_ identifier: String) {
		recentMessageIdentifiers[identifier, default: 0] += 1
	}

	private mutating func releaseMessage(_ identifier: String) {
		guard let count = recentMessageIdentifiers[identifier] else { return }
		if count <= 1 {
			recentMessageIdentifiers.removeValue(forKey: identifier)
			retiredMessageIdentifiers.append(identifier)
		} else {
			recentMessageIdentifiers[identifier] = count - 1
		}
	}
}
