/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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
	let lines: [LogLine]
	let lineNumbers: Set<String>
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
 rebuilding. It deliberately stores raw lines so a theme change can render
 them again from semantic values. */
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
	private var recentLines: [LogLine] = []
	private var recentResults: [String: LogLineRenderResult] = [:]
	private var pendingResults: [LogLineRenderResult] = []
	/** Where each retained line sits, counted from the first line the state ever
	 held rather than from the head of `recentLines`. Trimming the head then
	 costs nothing to record: `droppedLineCount` moves instead of every entry. */
	private var positions: [String: Int] = [:]
	private var droppedLineCount = 0

	var pendingLineNumbers: Set<String> {
		Set(pendingResults.map(\.lineNumber))
	}

	func containsLine(withIdentifier identifier: String) -> Bool {
		positions[identifier] != nil
	}

	var lineCount: Int {
		recentLines.count
	}

	init(capacity: Int = LogViewBufferPolicy.defaultHardLimit) {
		self.capacity = max(capacity, 1)
	}

	mutating func setCapacity(_ capacity: Int) {
		self.capacity = max(capacity, 1)
		trimToCapacity()
	}

	mutating func record(_ line: LogLine, rendered result: LogLineRenderResult) -> LiveLineAction {
		if let existing = index(of: line.uniqueIdentifier) {
			/* Re-recording a line the tail already holds moves it to the end, and
			 only then is renumbering what follows worth the walk. */
			recentLines.remove(at: existing)
			for offset in existing ..< recentLines.count {
				positions[recentLines[offset].uniqueIdentifier] = droppedLineCount + offset
			}
		}
		positions[line.uniqueIdentifier] = droppedLineCount + recentLines.count
		recentLines.append(line)
		recentResults[line.uniqueIdentifier] = result
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
		return TranscriptReplaySnapshot(
			lines: recentLines,
			lineNumbers: Set(recentLines.map(\.uniqueIdentifier)),
			results: recentLines.compactMap { recentResults[$0.uniqueIdentifier] }
		)
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
		recentLines.removeAll()
		recentResults.removeAll()
		pendingResults.removeAll()
		positions.removeAll()
		droppedLineCount = 0
	}

	/// Where a retained line sits in `recentLines`, or `nil` when it is not one.
	private func index(of uniqueIdentifier: String) -> Int? {
		guard let position = positions[uniqueIdentifier] else { return nil }
		let index = position - droppedLineCount
		return recentLines.indices.contains(index) ? index : nil
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
		deliveryUpdates[lineNumber] = update
		guard let index = index(of: lineNumber) else {
			return
		}
		recentLines[index].deliveryState = state
		if let messageIdentifier, messageIdentifier.isEmpty == false {
			recentLines[index].messageIdentifier = messageIdentifier
		}
	}

	private mutating func trimToCapacity() {
		guard recentLines.count > capacity else {
			return
		}
		let removalCount = recentLines.count - capacity
		let removedLineNumbers = recentLines.prefix(removalCount).map(\.uniqueIdentifier)
		recentLines.removeFirst(removalCount)
		droppedLineCount += removalCount
		for lineNumber in removedLineNumbers {
			recentResults.removeValue(forKey: lineNumber)
			deliveryUpdates.removeValue(forKey: lineNumber)
			positions.removeValue(forKey: lineNumber)
		}
	}
}
