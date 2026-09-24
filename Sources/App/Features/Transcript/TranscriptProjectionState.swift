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

/** Owns rendered rows until the native document can own them.

 Dormant and loading transcripts need a bounded bridge for live prints. Once
 replay has finished, the document is the row owner and this state keeps only
 unread-marker and in-flight delivery information. A later replay takes a
 temporary snapshot from the document; ordinary active prints never build a
 second semantic row buffer. */
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
	/// Rows awaiting a document, oldest first. Empty while active.
	private var recentResults: [TranscriptRenderResult] = []
	/// What ``recentResults`` holds, so a duplicate check is an answer rather
	/// than a walk.
	private var recentLineNumbers: Set<String> = []
	/// How many buffered rows or in-flight receipts carry each message identifier.
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
		guard phase != .active else { return .append }
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
			preconditionFailure("Active transcripts cannot retain projection rows")
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

	/// Snapshots the visible tail only for a new replay. Before the first view
	/// exists, the dormant rows are already here. After a completed replay the
	/// document supplies the only persistent semantic rows.
	mutating func beginReplay(displaying rows: [TranscriptRow] = []) -> [TranscriptRenderResult] {
		if phase == .active {
			recentResults = rows.suffix(capacity).map {
				TranscriptRenderResult(transcriptLine: $0, fromCurrentSession: false, processesInlineMedia: false)
			}
			recentLineNumbers = Set(recentResults.map(\.lineNumber))
			recentMessageIdentifiers.removeAll(keepingCapacity: true)
			for result in recentResults {
				if let identifier = result.transcriptLine.messageIdentifier {
					retainMessage(identifier)
				}
			}
		}
		phase = .loading
		pendingResults.removeAll(keepingCapacity: true)
		return recentResults
	}

	mutating func finishReplay(displaying lineNumbers: Set<String>) -> [TranscriptRenderResult] {
		let pending = takePendingResults(displaying: lineNumbers)
		phase = .active
		/* The document now answers whether each message survived the replay.
		 Offer every projected identifier for retirement, and let its owner keep
		 those whose rows are actually displayed. */
		retiredMessageIdentifiers.append(contentsOf: recentMessageIdentifiers.keys)
		recentResults.removeAll(keepingCapacity: false)
		recentLineNumbers.removeAll(keepingCapacity: false)
		recentMessageIdentifiers.removeAll(keepingCapacity: false)
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

	@discardableResult
	mutating func updateDelivery(
		lineNumber: String,
		state: ChatLineDeliveryState,
		messageIdentifier: String?,
		reason: String?,
		isDisplayed: Bool = false
	) -> TranscriptDeliveryUpdate? {
		/* A later state transition need not repeat the acknowledgement's
		 identifier. Keep the identifier already assigned to this line. */
		let identifier = messageIdentifier ?? deliveryUpdates[lineNumber]?.messageIdentifier
		let update = TranscriptDeliveryUpdate(
			lineNumber: lineNumber,
			state: state,
			messageIdentifier: identifier,
			reason: reason
		)
		/* An ack can arrive after its line has been trimmed away. Record one
		 only while a buffered or displayed row can receive it. A buffered row
		 folds the receipt in when it is drawn; an active row takes the receipt
		 directly and then this temporary entry is retired. */
		guard recentLineNumbers.contains(lineNumber) || phase == .active && isDisplayed else {
			return nil
		}
		/* An acknowledgement is where an outgoing line first learns its
		 message identifier, so the identifier the update names counts as one
		 the row carries. */
		let previous = deliveryUpdates[lineNumber]?.messageIdentifier
		deliveryUpdates[lineNumber] = update
		if let identifier, identifier != previous {
			retainMessage(identifier)
			if let previous {
				releaseMessage(previous)
			}
		}
		return update
	}

	/// A receipt has reached the document, which now owns the updated row. An
	/// older queued receipt must not withdraw one that arrived after it.
	mutating func deliveryWasApplied(_ update: TranscriptDeliveryUpdate) {
		guard phase == .active, deliveryUpdates[update.lineNumber] == update else { return }
		deliveryUpdates.removeValue(forKey: update.lineNumber)
		if let identifier = update.messageIdentifier {
			releaseMessage(identifier)
		}
	}

	/// The native document trimmed these lines before a queued receipt landed.
	mutating func retireDisplayedLines(_ lineNumbers: [String]) {
		guard phase == .active else { return }
		for lineNumber in lineNumbers {
			if let identifier = deliveryUpdates.removeValue(forKey: lineNumber)?.messageIdentifier {
				releaseMessage(identifier)
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
