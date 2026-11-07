// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

nonisolated enum TranscriptFoldKind: Equatable, Sendable {
	case generalEvents
	case mutedUser(normalizedNickname: String, displayNickname: String)

	fileprivate func groups(with other: Self) -> Bool {
		switch (self, other) {
		case (.generalEvents, .generalEvents):
			true
		case let (.mutedUser(first, _), .mutedUser(second, _)):
			first == second
		default:
			false
		}
	}
}

nonisolated enum TranscriptFoldPresentation: Equatable, Sendable {
	/// An expanded summary precedes the first row's ordinary content.
	case summary(kind: TranscriptFoldKind, count: Int, expanded: Bool)
	case hidden
}

/// Keeps folding decisions separate from native text storage. Routine edits
/// affect only the touched edge; policy changes may regroup the whole buffer.
nonisolated struct TranscriptFoldingState: Sendable {
	private struct Group: Sendable {
		var kind: TranscriptFoldKind
		var lineNumbers: [String]
		var firstLineIndex = 0
		var identifiers: Set<String>
		var expanded = false
		var firstRowHasMarkers: Bool

		var count: Int {
			lineNumbers.count - firstLineIndex
		}

		var summaryLineNumber: String {
			lineNumbers[firstLineIndex]
		}

		var activeLineNumbers: ArraySlice<String> {
			lineNumbers[firstLineIndex...]
		}

		mutating func retireFirst(_ count: Int) {
			precondition(count <= self.count)
			firstLineIndex += count
			// Keep a long-running, capped transcript from retaining every old
			// summary identity. This compaction is amortized over removed rows.
			if firstLineIndex > 1024, firstLineIndex > lineNumbers.count / 2 {
				lineNumbers.removeFirst(firstLineIndex)
				firstLineIndex = 0
			}
		}
	}

	private(set) var presentations: [String: TranscriptFoldPresentation] = [:]
	private(set) var rowCount = 0
	private var groups: [Int: Group] = [:]
	private var groupBySummary: [String: Int] = [:]
	private var groupByLineNumber: [String: Int] = [:]
	private var nextGroupIdentifier = 0
	private var firstGroupIdentifier: Int?
	private var lastGroupIdentifier: Int?

	/// A policy or marker change can regroup any row. Retained identities carry
	/// expansion through a different grouping; removed identities do not.
	@discardableResult
	mutating func update(
		rows: [TranscriptRow],
		generalEventDisplay: GeneralEventMessageDisplay,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> Set<String> {
		let previous = presentations
		let expandedIdentifiers = Set(groups.values.filter(\.expanded).flatMap(\.identifiers))
		let updatedGroups = Self.makeGroups(
			rows: rows, collapseGeneralEvents: generalEventDisplay == .collapse,
			mutedNicknames: Self.fold(mutedNicknames, using: caseMapping), caseMapping: caseMapping
		)
		presentations.removeAll(keepingCapacity: true)
		groups.removeAll(keepingCapacity: true)
		groupBySummary.removeAll(keepingCapacity: true)
		groupByLineNumber.removeAll(keepingCapacity: true)
		rowCount = rows.count
		for var group in updatedGroups {
			group.expanded = !expandedIdentifiers.isDisjoint(with: group.identifiers)
			register(group)
		}
		if generalEventDisplay == .hide {
			for row in rows where Self.isGeneralEvent(row) {
				presentations[row.lineNumber] = .hidden
			}
		}
		firstGroupIdentifier = rows.first.flatMap { groupByLineNumber[$0.lineNumber] }
		lastGroupIdentifier = rows.last.flatMap { groupByLineNumber[$0.lineNumber] }
		return changedLineNumbers(comparedTo: previous)
	}

	/// Returns only existing rows that must be redrawn. New rows can be rendered
	/// from their final presentation before they enter the native text storage.
	@discardableResult
	mutating func append(
		rows: [TranscriptRow],
		generalEventDisplay: GeneralEventMessageDisplay,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> Set<String> {
		let foldedNicknames = Self.fold(mutedNicknames, using: caseMapping)
		var changed: Set<String> = []
		for row in rows {
			let kind = Self.foldKind(
				for: row, collapseGeneralEvents: generalEventDisplay == .collapse,
				mutedNicknames: foldedNicknames, caseMapping: caseMapping
			)
			if let kind, row.markers.isEmpty, let identifier = lastGroupIdentifier,
			   groups[identifier]?.kind.groups(with: kind) == true
			{
				groups[identifier]?.lineNumbers.append(row.lineNumber)
				groups[identifier]?.identifiers.formUnion(row.identifiers)
				groupByLineNumber[row.lineNumber] = identifier
				guard let group = groups[identifier] else {
					preconditionFailure("An appended fold group must remain registered")
				}
				presentations[group.summaryLineNumber] = .summary(
					kind: group.kind, count: group.count, expanded: group.expanded
				)
				changed.insert(group.summaryLineNumber)
				if group.expanded == false {
					presentations[row.lineNumber] = .hidden
					changed.insert(row.lineNumber)
				}
			} else if let kind {
				let group = Group(
					kind: kind, lineNumbers: [row.lineNumber], identifiers: Set(row.identifiers),
					firstRowHasMarkers: !row.markers.isEmpty
				)
				lastGroupIdentifier = register(group)
				changed.insert(row.lineNumber)
			} else {
				lastGroupIdentifier = nil
				if generalEventDisplay == .hide, Self.isGeneralEvent(row) {
					presentations[row.lineNumber] = .hidden
					changed.insert(row.lineNumber)
				}
			}
			if rowCount == 0 {
				firstGroupIdentifier = lastGroupIdentifier
			}
			rowCount += 1
		}
		return changed
	}

	/// Older history is normally loaded in blocks. Build its groups once, then
	/// merge at most the block's trailing group with the retained first group.
	@discardableResult
	mutating func prepend(
		rows: [TranscriptRow],
		generalEventDisplay: GeneralEventMessageDisplay,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> Set<String> {
		guard rows.isEmpty == false else { return [] }
		let hadRows = rowCount > 0
		let incomingGroups = Self.makeGroups(
			rows: rows, collapseGeneralEvents: generalEventDisplay == .collapse,
			mutedNicknames: Self.fold(mutedNicknames, using: caseMapping), caseMapping: caseMapping
		)
		var changed: Set<String> = []
		let oldFirstIdentifier = firstGroupIdentifier
		let joiningIndex = incomingGroups.indices.last.flatMap { index -> Int? in
			guard let lastRow = rows.last, incomingGroups[index].lineNumbers.last == lastRow.lineNumber,
			      let oldFirstIdentifier, let oldFirst = groups[oldFirstIdentifier],
			      oldFirst.firstRowHasMarkers == false,
			      incomingGroups[index].kind.groups(with: oldFirst.kind)
			else { return nil }
			return index
		}
		for (index, incoming) in incomingGroups.enumerated() {
			if index == joiningIndex, let oldFirstIdentifier, var oldFirst = groups[oldFirstIdentifier] {
				let oldSummary = oldFirst.summaryLineNumber
				oldFirst.kind = incoming.kind
				oldFirst.lineNumbers = incoming.lineNumbers + Array(oldFirst.activeLineNumbers)
				oldFirst.firstLineIndex = 0
				oldFirst.firstRowHasMarkers = incoming.firstRowHasMarkers
				oldFirst.identifiers.formUnion(incoming.identifiers)
				groups[oldFirstIdentifier] = oldFirst
				groupBySummary.removeValue(forKey: oldSummary)
				groupBySummary[oldFirst.summaryLineNumber] = oldFirstIdentifier
				for lineNumber in incoming.lineNumbers {
					groupByLineNumber[lineNumber] = oldFirstIdentifier
				}
				presentations[oldSummary] = oldFirst.expanded ? nil : .hidden
				setPresentation(for: oldFirst, only: incoming.lineNumbers)
				changed.insert(oldSummary)
				changed.formUnion(incoming.lineNumbers)
			} else {
				register(incoming)
				changed.formUnion(incoming.lineNumbers)
			}
		}
		if generalEventDisplay == .hide {
			for row in rows where Self.isGeneralEvent(row) {
				presentations[row.lineNumber] = .hidden
				changed.insert(row.lineNumber)
			}
		}
		rowCount += rows.count
		firstGroupIdentifier = rows.first.flatMap { groupByLineNumber[$0.lineNumber] }
		if hadRows == false {
			lastGroupIdentifier = rows.last.flatMap { groupByLineNumber[$0.lineNumber] }
		}
		return changed
	}

	/// Retiring the oldest rows advances each affected group's head without
	/// renumbering the remaining groups or rewriting their hidden state.
	@discardableResult
	mutating func retire(rows: [TranscriptRow], firstRetainedRow: TranscriptRow?) -> Set<String> {
		guard rows.isEmpty == false else { return [] }
		precondition(rows.count <= rowCount)
		var retiredCounts: [Int: Int] = [:]
		for row in rows {
			presentations.removeValue(forKey: row.lineNumber)
			if let identifier = groupByLineNumber.removeValue(forKey: row.lineNumber) {
				retiredCounts[identifier, default: 0] += 1
				for identity in row.identifiers {
					groups[identifier]?.identifiers.remove(identity)
				}
			}
		}
		var changed: Set<String> = []
		for (identifier, count) in retiredCounts {
			guard var group = groups[identifier] else { continue }
			let oldSummary = group.summaryLineNumber
			group.retireFirst(count)
			if group.count == 0 {
				groups.removeValue(forKey: identifier)
				groupBySummary.removeValue(forKey: oldSummary)
			} else {
				groupBySummary.removeValue(forKey: oldSummary)
				groupBySummary[group.summaryLineNumber] = identifier
				presentations[group.summaryLineNumber] = .summary(
					kind: group.kind, count: group.count, expanded: group.expanded
				)
				changed.insert(group.summaryLineNumber)
				groups[identifier] = group
			}
		}
		rowCount -= rows.count
		if rowCount == 0 {
			reset()
		} else if let firstRetainedRow {
			firstGroupIdentifier = groupByLineNumber[firstRetainedRow.lineNumber]
			if let firstGroupIdentifier {
				groups[firstGroupIdentifier]?.firstRowHasMarkers = !firstRetainedRow.markers.isEmpty
				if case let .mutedUser(normalizedNickname, displayNickname) = groups[firstGroupIdentifier]?.kind,
				   let nickname = firstRetainedRow.nickname, nickname != displayNickname
				{
					groups[firstGroupIdentifier]?.kind = .mutedUser(
						normalizedNickname: normalizedNickname, displayNickname: nickname
					)
					if case let .summary(_, count, expanded) = presentations[firstRetainedRow.lineNumber] {
						presentations[firstRetainedRow.lineNumber] = .summary(
							kind: .mutedUser(normalizedNickname: normalizedNickname, displayNickname: nickname),
							count: count, expanded: expanded
						)
						changed.insert(firstRetainedRow.lineNumber)
					}
				}
			}
		}
		return changed
	}

	@discardableResult
	mutating func toggle(summaryLineNumber: String) -> Set<String> {
		guard let identifier = groupBySummary[summaryLineNumber], var group = groups[identifier] else { return [] }
		group.expanded.toggle()
		groups[identifier] = group
		setPresentation(for: group)
		return Set(group.activeLineNumbers)
	}

	/// The view resolves persisted history identities to display line numbers.
	@discardableResult
	mutating func reveal(lineNumber: String) -> Set<String> {
		guard let identifier = groupByLineNumber[lineNumber], var group = groups[identifier], group.expanded == false
		else { return [] }
		group.expanded = true
		groups[identifier] = group
		setPresentation(for: group)
		return Set(group.activeLineNumbers)
	}

	mutating func reset() {
		self = Self()
	}

	@discardableResult
	private mutating func register(_ group: Group) -> Int {
		let identifier = nextGroupIdentifier
		nextGroupIdentifier += 1
		groups[identifier] = group
		groupBySummary[group.summaryLineNumber] = identifier
		for lineNumber in group.activeLineNumbers {
			groupByLineNumber[lineNumber] = identifier
		}
		setPresentation(for: group)
		return identifier
	}

	private mutating func setPresentation(for group: Group, only lines: [String]? = nil) {
		presentations[group.summaryLineNumber] = .summary(
			kind: group.kind, count: group.count, expanded: group.expanded
		)
		for lineNumber in lines ?? Array(group.activeLineNumbers.dropFirst()) where lineNumber != group.summaryLineNumber {
			presentations[lineNumber] = group.expanded ? nil : .hidden
		}
	}

	private func changedLineNumbers(comparedTo previous: [String: TranscriptFoldPresentation]) -> Set<String> {
		Set(previous.keys).union(presentations.keys).filter { previous[$0] != presentations[$0] }
	}

	private static func fold(_ nicknames: Set<String>, using caseMapping: ISupportCaseMapping) -> Set<String> {
		Set(nicknames.map { IRCCaseFolding.fold($0, using: caseMapping) })
	}

	private static func makeGroups(
		rows: [TranscriptRow],
		collapseGeneralEvents: Bool,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> [Group] {
		var result: [Group] = []
		var pending: Group?
		for row in rows {
			let kind = foldKind(
				for: row, collapseGeneralEvents: collapseGeneralEvents,
				mutedNicknames: mutedNicknames, caseMapping: caseMapping
			)
			if let kind, row.markers.isEmpty, pending?.kind.groups(with: kind) == true {
				pending?.lineNumbers.append(row.lineNumber)
				pending?.identifiers.formUnion(row.identifiers)
				continue
			}
			if let pending {
				result.append(pending)
			}
			pending = kind.map {
				Group(
					kind: $0, lineNumbers: [row.lineNumber], identifiers: Set(row.identifiers),
					firstRowHasMarkers: !row.markers.isEmpty
				)
			}
		}
		if let pending {
			result.append(pending)
		}
		return result
	}

	private static func foldKind(
		for row: TranscriptRow,
		collapseGeneralEvents: Bool,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> TranscriptFoldKind? {
		guard row.memberType != .localUser else { return nil }
		if row.lineType.isConversation, let nickname = row.nickname, !nickname.isEmpty {
			let normalized = IRCCaseFolding.fold(nickname, using: caseMapping)
			if mutedNicknames.contains(normalized) {
				return .mutedUser(normalizedNickname: normalized, displayNickname: nickname)
			}
		}
		return collapseGeneralEvents && isGeneralEvent(row) ? .generalEvents : nil
	}

	private static func isGeneralEvent(_ row: TranscriptRow) -> Bool {
		guard row.memberType != .localUser else { return false }
		switch row.lineType {
		case .join, .part, .quit, .nick, .mode, .topic:
			return true
		default:
			return false
		}
	}
}
