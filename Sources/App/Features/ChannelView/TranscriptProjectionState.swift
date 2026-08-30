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

/** The native and JavaScript transcript buffers use one policy. A zero or
 otherwise invalid preference restores the theme API's established defaults. */
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
	let state: TVCLogLineDeliveryState
	let messageIdentifier: String?
	let reason: String?
}

nonisolated struct TranscriptReplaySnapshot: Sendable { // nonisolated: value
	let lines: [LogLine]
	let lineNumbers: Set<String>
}

/** Owns the bounded native transcript while its WebKit projection does not
 exist or is rebuilding. It deliberately stores raw lines: a theme reload must
 render them through the new theme, not replay stale HTML. */
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

	mutating func updateDelivery(
		lineNumber: String,
		state: TVCLogLineDeliveryState,
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
