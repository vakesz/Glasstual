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
	static let defaultSoftLimit = 200
	static let defaultHardLimit = 1000
	static let validLimits = 100 ... 50000

	let softLimit: Int
	let hardLimit: Int

	init(preference: UInt) {
		if preference >= UInt(Self.validLimits.lowerBound),
		   preference <= UInt(Self.validLimits.upperBound)
		{
			let limit = Int(preference)
			softLimit = limit
			hardLimit = limit
		} else {
			softLimit = Self.defaultSoftLimit
			hardLimit = Self.defaultHardLimit
		}
	}
}

nonisolated enum TranscriptScrollbackMark: Equatable, Sendable { // nonisolated: value
	case none
	case latest
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
	private var pendingResults: [LogLineRenderResult] = []

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
		if let existing = recentLines.firstIndex(where: { $0.uniqueIdentifier == line.uniqueIdentifier }) {
			recentLines.remove(at: existing)
		}
		recentLines.append(line)
		trimToCapacity()

		switch phase {
		case .active:
			return .append
		case .loading:
			pendingResults.append(result)
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
			lineNumbers: Set(recentLines.map(\.uniqueIdentifier))
		)
	}

	mutating func finishReplay(displaying lineNumbers: Set<String>) -> [LogLineRenderResult] {
		let pending = pendingResults.filter { lineNumbers.contains($0.lineNumber) == false }
		pendingResults.removeAll(keepingCapacity: true)
		phase = .active
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
		pendingResults.removeAll()
	}

	mutating func setMark(_ mark: TranscriptScrollbackMark) {
		self.mark = mark
	}

	/// The first thing said on or after `date`; what "go to mark" jumps to.
	func renderedLineNumber(onOrAfter date: Date) -> String? {
		recentLines.first { $0.receivedAt >= date && $0.lineType.isConversation }?.uniqueIdentifier
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
		guard let index = recentLines.firstIndex(where: { $0.uniqueIdentifier == lineNumber }) else {
			return
		}
		recentLines[index].deliveryState = state
		if let messageIdentifier, messageIdentifier.isEmpty == false {
			recentLines[index].messageIdentifier = messageIdentifier
		}
	}

	/** Merges historic storage with the in-memory tail. When both contain a
	 line, the in-memory copy wins because it may carry a delivery update that
	 arrived after the historic write. */
	static func merging(historic: [LogLine], replay: [LogLine]) -> [LogLine] {
		let replayByIdentifier = Dictionary(uniqueKeysWithValues: replay.map { ($0.uniqueIdentifier, $0) })
		var seen = Set<String>()
		var merged = historic.map { line in
			seen.insert(line.uniqueIdentifier)
			return replayByIdentifier[line.uniqueIdentifier] ?? line
		}
		merged.append(contentsOf: replay.filter { seen.insert($0.uniqueIdentifier).inserted })
		return merged
	}

	private mutating func trimToCapacity() {
		guard recentLines.count > capacity else {
			return
		}
		let removalCount = recentLines.count - capacity
		let removedLineNumbers = recentLines.prefix(removalCount).map(\.uniqueIdentifier)
		recentLines.removeFirst(removalCount)
		for lineNumber in removedLineNumbers {
			deliveryUpdates.removeValue(forKey: lineNumber)
		}
	}
}
