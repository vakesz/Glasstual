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
	case hidden(summaryLineNumber: String)
}

/// Keeps folding decisions separate from native text storage. All source rows
/// remain available for expansion, history lookup and subsequent regrouping.
nonisolated struct TranscriptFoldingState: Sendable {
	private struct Group: Sendable {
		let kind: TranscriptFoldKind
		let summaryLineNumber: String
		var lineNumbers: [String]
		var identifiers: Set<String>
	}

	private(set) var presentations: [String: TranscriptFoldPresentation] = [:]
	private var groups: [String: Group] = [:]
	private var summaryByIdentifier: [String: String] = [:]
	private var expandedIdentifiers: Set<String> = []

	/// Returns every line whose presentation changed, including retired rows.
	/// Retained row identities carry expansion across prepend, append and trim.
	@discardableResult
	mutating func update(
		rows: [TranscriptRow],
		generalEventDisplay: GeneralEventMessageDisplay,
		mutedNicknames: Set<String>,
		caseMapping: ISupportCaseMapping
	) -> Set<String> {
		let previous = presentations
		let foldedNicknames = Set(mutedNicknames.map { IRCCaseFolding.fold($0, using: caseMapping) })
		let updatedGroups = Self.makeGroups(
			rows: rows,
			collapseGeneralEvents: generalEventDisplay == .collapse,
			mutedNicknames: foldedNicknames,
			caseMapping: caseMapping
		)
		expandedIdentifiers.formIntersection(Set(updatedGroups.flatMap(\.identifiers)))
		presentations.removeAll(keepingCapacity: true)
		groups.removeAll(keepingCapacity: true)
		summaryByIdentifier.removeAll(keepingCapacity: true)
		for group in updatedGroups {
			groups[group.summaryLineNumber] = group
			for identifier in group.identifiers {
				summaryByIdentifier[identifier] = group.summaryLineNumber
			}
			let expanded = !expandedIdentifiers.isDisjoint(with: group.identifiers)
			setExpanded(expanded, for: group)
		}
		if generalEventDisplay == .hide {
			for row in rows where Self.isGeneralEvent(row) {
				presentations[row.lineNumber] = .hidden(summaryLineNumber: row.lineNumber)
			}
		}
		return changedLineNumbers(comparedTo: previous)
	}

	@discardableResult
	mutating func toggle(summaryLineNumber: String) -> Set<String> {
		guard let group = groups[summaryLineNumber],
		      case let .summary(_, _, expanded) = presentations[summaryLineNumber]
		else { return [] }
		let previous = presentations
		setExpanded(!expanded, for: group)
		return changedLineNumbers(comparedTo: previous)
	}

	/// A jump to either a displayed identity or a history identity opens its group.
	@discardableResult
	mutating func reveal(lineNumber: String) -> Set<String> {
		guard let summary = summaryByIdentifier[lineNumber], let group = groups[summary] else { return [] }
		let previous = presentations
		setExpanded(true, for: group)
		return changedLineNumbers(comparedTo: previous)
	}

	mutating func reset() {
		self = Self()
	}

	private mutating func setExpanded(_ expanded: Bool, for group: Group) {
		if expanded {
			expandedIdentifiers.formUnion(group.identifiers)
		} else {
			expandedIdentifiers.subtract(group.identifiers)
		}
		presentations[group.summaryLineNumber] = .summary(
			kind: group.kind, count: group.lineNumbers.count, expanded: expanded
		)
		for lineNumber in group.lineNumbers.dropFirst() {
			presentations[lineNumber] = expanded ? nil : .hidden(summaryLineNumber: group.summaryLineNumber)
		}
	}

	private func changedLineNumbers(comparedTo previous: [String: TranscriptFoldPresentation]) -> Set<String> {
		Set(previous.keys).union(presentations.keys).filter { previous[$0] != presentations[$0] }
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
				Group(kind: $0, summaryLineNumber: row.lineNumber, lineNumbers: [row.lineNumber], identifiers: Set(row.identifiers))
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
