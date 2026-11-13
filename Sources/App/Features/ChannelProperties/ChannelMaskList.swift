// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions
import Observation
import SwiftUI

extension ChannelMaskKind {
	/// What the window is titled and the table is headed with: the list this is
	/// and the channel it belongs to. It lives with the window rather than with
	/// the kind so the heading's catalogue stays inside the feature that owns it.
	func heading(channelName: String) -> String {
		switch self {
		case .ban:
			String(localized: .ChannelProperties.headingForTheBanBans(channelName))
		case .banException:
			String(localized: .ChannelProperties.banExceptions(channelName))
		case .inviteException:
			String(localized: .ChannelProperties.inviteExceptions(channelName))
		case .quiet:
			String(localized: .ChannelProperties.headingForTheQuietQuiets(channelName))
		}
	}
}

extension ChannelMaskKind {
	/// What an empty table says, by the list it is: "No Bans" rather than a
	/// title that is the same whichever list came back empty.
	var emptyTitle: LocalizedStringResource {
		switch self {
		case .ban: .ChannelProperties.emptyTitleBans
		case .banException: .ChannelProperties.emptyTitleBanExceptions
		case .inviteException: .ChannelProperties.emptyTitleInviteExceptions
		case .quiet: .ChannelProperties.emptyTitleQuiets
		}
	}
}

/** Why a change to the list was not made, shown beside the field it came from.

 The server answers a refused `MODE` with an error numeric, and the window keeps
 the reason rather than letting it scroll past in a transcript the user is not
 looking at. */
enum ChannelMaskListIssue: Equatable, Sendable {
	case invalid(MaskNormalizer.Rejection)
	case duplicate
	/// `ERR_CHANOPRIVSNEEDED`.
	case notOperator
	/// `ERR_BANLISTFULL`.
	case listFull
	/// Any other refusal, with the text the server gave.
	case rejected(String)

	var message: String {
		switch self {
		case .invalid(.empty):
			String(localized: .ChannelProperties.issueEmpty)
		case .invalid(.containsWhitespace):
			String(localized: .ChannelProperties.issueWhitespace)
		case .invalid(.startsWithColon):
			String(localized: .ChannelProperties.issueColon)
		case .invalid(.tooLong):
			String(localized: .ChannelProperties.issueTooLong)
		case .duplicate:
			String(localized: .ChannelProperties.issueDuplicate)
		case .notOperator:
			String(localized: .ChannelProperties.issueNotOperator)
		case .listFull:
			String(localized: .ChannelProperties.issueListFull)
		case let .rejected(text):
			String(localized: .ChannelProperties.issueRejected(text))
		}
	}
}

struct ChannelMaskListEntry: Identifiable, Hashable, Sendable {
	let id = UUID()
	var entryMask = ""
	var entryMaskDescription: String?
	var entryAuthor = ""
	var entryCreationDate: Date?

	var entryCreationDateString: String {
		guard let entryCreationDate else {
			return ApplicationStrings.unknownValue
		}

		return entryCreationDate.formatted(date: .abbreviated, time: .shortened)
	}
}

struct ChannelMaskListComparator: SortComparator {
	enum Field: Hashable, Sendable {
		case mask
		case author
		case creationDate
	}

	let field: Field
	var order: SortOrder

	func compare(_ lhs: ChannelMaskListEntry, _ rhs: ChannelMaskListEntry) -> ComparisonResult {
		let result = switch field {
		case .mask:
			lhs.entryMask.localizedCaseInsensitiveCompare(rhs.entryMask)
		case .author:
			lhs.entryAuthor.localizedCaseInsensitiveCompare(rhs.entryAuthor)
		case .creationDate:
			(lhs.entryCreationDate ?? .distantPast).compare(rhs.entryCreationDate ?? .distantPast)
		}

		return result.ordered(by: order)
	}
}

@Observable
final class ChannelMaskListModel {
	var entries: [ChannelMaskListEntry] = []
	var selection: Set<ChannelMaskListEntry.ID> = []
	var sortOrder: [ChannelMaskListComparator] = [
		ChannelMaskListComparator(field: .creationDate, order: .reverse),
	]
	var maximumEntries = 0
	var isRefreshing = true
	/// What is typed in the field above the table.
	var draft = ""
	/// The entry the field is replacing, or `nil` while it adds a new one.
	var editingMask: String?
	/// Why the last change could not be made, until the next one is tried.
	var issue: ChannelMaskListIssue?
	/** How many entries the list keeps.

	 A channel's ban list arrives one line at a time and nothing bounded it, so
	 a list nobody has pruned in years was held whole. What is past the cap is
	 counted. */
	static let maximumRetainedEntries = 20000
	private(set) var discardedEntryCount = 0

	var selectedMasks: [String] {
		entries.filter { selection.contains($0.id) }.map(\.entryMask)
	}

	var entryCountDescription: String {
		Self.entryCountDescription(
			entries.count,
			maximum: maximumEntries,
			isTruncated: discardedEntryCount > 0
		)
	}

	/// - Parameter isTruncated: Whether the window dropped entries the server
	///   sent. Neither the bare count nor the `MAXLIST` comparison may be used
	///   then: both read as the list being all of it.
	static func entryCountDescription(_ count: Int, maximum: Int, isTruncated: Bool) -> String {
		if isTruncated {
			return String(localized: .ChannelProperties.entryCountTruncated(count))
		}

		guard maximum > 0 else {
			return String(localized: .ChannelProperties.entryCount(count))
		}

		return String(localized: .ChannelProperties.ofEntries(count, maximum))
	}

	/// What to tell the user when the list is not all of it, or `nil` when it
	/// is. The count above the table cannot say this on its own: a list cut at
	/// the cap reads as a complete one that happens to be exactly that long.
	var truncationNotice: LocalizedStringResource? {
		/* Why the count above the list is not the whole list. Saying how many
		 are shown as well would repeat the count itself. */
		discardedEntryCount > 0 ? .ChannelProperties.listTruncatedNotice : nil
	}

	func add(_ entry: ChannelMaskListEntry) {
		guard entries.count < Self.maximumRetainedEntries else {
			discardedEntryCount += 1
			return
		}

		entries.insert(entry, at: insertionIndex(for: entry))
	}

	/** Where `entry` belongs in the list as it is sorted now: after every entry
	 that does not sort after it, so entries that compare equal keep the order
	 they arrived in.

	 A binary search, because the list arrives one line at a time: re-sorting
	 the whole list for each line was quadratic, and at the cap that was twenty
	 thousand sorts on the main actor for one reply. */
	private func insertionIndex(for entry: ChannelMaskListEntry) -> Int {
		var lower = entries.startIndex
		var upper = entries.endIndex

		while lower < upper {
			let middle = lower + (upper - lower) / 2
			if Self.compare(entries[middle], entry, using: sortOrder) == .orderedDescending {
				upper = middle
			} else {
				lower = middle + 1
			}
		}

		return lower
	}

	/// The first comparator that tells the two apart decides, as `sort(using:)`
	/// does with the same array.
	private static func compare(
		_ lhs: ChannelMaskListEntry,
		_ rhs: ChannelMaskListEntry,
		using comparators: [ChannelMaskListComparator]
	) -> ComparisonResult {
		for comparator in comparators {
			let result = comparator.compare(lhs, rhs)
			if result != .orderedSame {
				return result
			}
		}

		return .orderedSame
	}

	func clear() {
		entries = []
		selection = []
		discardedEntryCount = 0
	}

	func sort(using order: [ChannelMaskListComparator]) {
		entries.sort(using: order)
	}
}
