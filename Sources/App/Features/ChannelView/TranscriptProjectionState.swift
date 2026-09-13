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

import Foundation

/** A zero or otherwise invalid scrollback preference restores the transcript's
 established defaults. */
nonisolated struct LogViewBufferPolicy: Equatable, Sendable { // nonisolated: value
	static let defaultHardLimit = 1000
	static let validLimits = 100 ... 50000

	let hardLimit: Int

	init(preference: UInt) {
		if preference >= UInt(Self.validLimits.lowerBound),
		   preference <= UInt(Self.validLimits.upperBound)
		{
			hardLimit = Int(preference)
		} else {
			hardLimit = Self.defaultHardLimit
		}
	}
}

nonisolated enum TranscriptScrollbackMark: Equatable, Sendable { // nonisolated: value
	case none
	case latest
	case line(String)
	case after(Date)
}

nonisolated struct TranscriptDeliveryUpdate: Equatable, Sendable { // nonisolated: value
	let lineNumber: String
	let state: LogLineDeliveryState
	let messageIdentifier: String?
	let reason: String?
}

nonisolated struct TranscriptReplaySnapshot: Sendable { // nonisolated: value
	let results: [LogLineRenderResult]
}

/// Tracks the one visual boundary between restored scrollback and lines from
/// this process. The boundary may be known during the initial replay or may
/// have to wait for the first live line that arrives afterwards.
nonisolated struct TranscriptSessionBoundaryState: Sendable { // nonisolated: value
	private(set) var newestPreviousSessionLineNumber: String?
	private(set) var firstCurrentSessionLineNumber: String?
	private var markerIsPending = false

	mutating func prepareInitialHistory(
		_ historicLines: [LogLine],
		renderedLines: [LogLineRenderResult]
	) -> String? {
		newestPreviousSessionLineNumber = historicLines.last { $0.fromCurrentSession == false }?
			.uniqueIdentifier
		firstCurrentSessionLineNumber = nil
		guard newestPreviousSessionLineNumber != nil else {
			markerIsPending = false
			return nil
		}
		guard let firstCurrent = renderedLines.first(where: \.fromCurrentSession) else {
			markerIsPending = true
			return nil
		}
		markerIsPending = false
		firstCurrentSessionLineNumber = firstCurrent.lineNumber
		return firstCurrent.lineNumber
	}

	mutating func consumePendingMarker(for line: LogLineRenderResult) -> Bool {
		guard markerIsPending, line.fromCurrentSession else {
			return false
		}
		markerIsPending = false
		firstCurrentSessionLineNumber = line.lineNumber
		return true
	}

	mutating func reset() {
		newestPreviousSessionLineNumber = nil
		firstCurrentSessionLineNumber = nil
		markerIsPending = false
	}
}

/** Owns the bounded transcript while its native view does not exist or is
 rebuilding.

 What it stores is the rendered rows: a ``TranscriptLine`` is already the
 semantic form a theme change re-renders from, so keeping the archives beside
 them was a second copy of the same conversation under a second ceiling. */
nonisolated struct TranscriptProjectionState: Sendable { // nonisolated: value
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
	private(set) var mark: TranscriptScrollbackMark = .none
	private(set) var deliveryUpdates: [String: TranscriptDeliveryUpdate] = [:]

	private var capacity: Int
	/// The retained rows, oldest first.
	private var recentResults: [LogLineRenderResult] = []
	/// What ``recentResults`` holds, so a duplicate check is an answer rather
	/// than a walk.
	private var recentLineNumbers: Set<String> = []
	private var pendingResults: [LogLineRenderResult] = []

	func containsLine(withIdentifier identifier: String) -> Bool {
		recentLineNumbers.contains(identifier)
	}

	var lineCount: Int {
		recentResults.count
	}

	init(capacity: Int = LogViewBufferPolicy.defaultHardLimit) {
		self.capacity = max(capacity, 1)
	}

	mutating func setCapacity(_ capacity: Int) {
		self.capacity = max(capacity, 1)
		trimToCapacity()
	}

	mutating func record(_ result: LogLineRenderResult) -> LiveLineAction {
		/* A line printed a second time moves to the end rather than appearing
		 twice. It is rare enough to be worth a walk when it happens, and the
		 set above is what keeps the common case from walking at all. */
		if recentLineNumbers.contains(result.lineNumber) {
			recentResults.removeAll { $0.lineNumber == result.lineNumber }
		}
		recentResults.append(result)
		recentLineNumbers.insert(result.lineNumber)
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

	mutating func beginReplay() -> TranscriptReplaySnapshot {
		phase = .loading
		pendingResults.removeAll(keepingCapacity: true)
		return TranscriptReplaySnapshot(results: recentResults)
	}

	mutating func finishReplay(displaying lineNumbers: Set<String>) -> [LogLineRenderResult] {
		let pending = takePendingResults(displaying: lineNumbers)
		phase = .active
		return pending
	}

	mutating func takePendingResults(displaying lineNumbers: Set<String>) -> [LogLineRenderResult] {
		let pending = pendingResults.filter { !lineNumbers.contains($0.lineNumber) }
		pendingResults.removeAll(keepingCapacity: true)
		return pending
	}

	mutating func becomeDormant() {
		phase = .dormant
		pendingResults.removeAll(keepingCapacity: true)
	}

	mutating func reset() {
		phase = .dormant
		mark = .none
		deliveryUpdates.removeAll()
		recentResults.removeAll()
		recentLineNumbers.removeAll()
		pendingResults.removeAll()
	}

	mutating func setMark(_ mark: TranscriptScrollbackMark) {
		self.mark = mark
	}

	mutating func updateDelivery(
		lineNumber: String,
		state: LogLineDeliveryState,
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
		deliveryUpdates[lineNumber] = update
	}

	private mutating func trimToCapacity() {
		guard recentResults.count > capacity else {
			return
		}
		let removalCount = recentResults.count - capacity
		let removedLineNumbers = recentResults.prefix(removalCount).map(\.lineNumber)
		recentResults.removeFirst(removalCount)
		for lineNumber in removedLineNumbers {
			recentLineNumbers.remove(lineNumber)
			deliveryUpdates.removeValue(forKey: lineNumber)
		}
	}
}
