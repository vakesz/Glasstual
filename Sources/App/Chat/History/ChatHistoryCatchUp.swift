// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Messages the server holds that were never fetched: everything after
/// `after` and before `before`, both excluded.
struct ChatHistoryGap: Equatable {
	let after: ChatHistoryReference
	let before: ChatHistoryReference
}

/// What a paging request asks the session to do next.
enum ChatHistoryPagingStep: Equatable {
	case send(ChatHistoryCommand)
	case finished
	/// Paging stopped before reaching the live end; `gap` is what is left.
	case finishedWithGap(ChatHistoryGap)
}

/** Catching a conversation up from the newest line the session has.

 With nothing known it asks for the latest page. Otherwise it asks for what
 came `AFTER` the newest known line, page by page, oldest first, until a page
 comes back short. After `maximumPages` full pages it gives up on paging
 forward, asks for the latest page instead, and records what lies between as
 a gap the user can fill later. */
struct ChatHistoryCatchUp: Equatable {
	private enum Phase: Equatable {
		case latestOnly
		case pagingForward
		case fetchingLiveEnd
		case done
	}

	/// How far a timestamp reference is moved back, so lines stamped within
	/// clock skew of it are fetched again; duplicates are dropped on arrival.
	static let timestampFuzz: TimeInterval = 5

	let target: String
	let limit: UInt
	let maximumPages: Int
	private let known: ChatHistoryReference?
	private var phase = Phase.done
	private(set) var pages = 0
	private var lastFilled: ChatHistoryReference?

	init(target: String, known: ChatHistoryReference?, limit: UInt, maximumPages: Int = 10) {
		self.target = target
		self.limit = max(limit, 1)
		self.maximumPages = max(maximumPages, 1)
		self.known = known.map(Self.fuzzed)
	}

	private static func fuzzed(_ reference: ChatHistoryReference) -> ChatHistoryReference {
		guard case let .timestamp(date) = reference else { return reference }
		return .timestamp(date.addingTimeInterval(-timestampFuzz))
	}

	mutating func start() -> ChatHistoryPagingStep {
		guard let known, known != .unbounded else {
			phase = .latestOnly
			return .send(.latest(target: target, after: .unbounded, limit: limit))
		}
		phase = .pagingForward
		lastFilled = known
		return .send(.after(target: target, known, limit: limit))
	}

	/** One page arrived. `count` is how many lines it held, `first` and
	 `last` the references of its oldest and newest line. A page is full when it
	 held at least `limit` lines, since servers may return more or fewer. */
	mutating func receivedPage(count: Int, first: ChatHistoryReference?, last: ChatHistoryReference?) -> ChatHistoryPagingStep {
		switch phase {
		case .latestOnly, .done:
			phase = .done
			return .finished
		case .fetchingLiveEnd:
			phase = .done
			guard let after = lastFilled, let first, count > 0 else { return .finished }
			return .finishedWithGap(ChatHistoryGap(after: after, before: first))
		case .pagingForward:
			pages += 1
			if let last {
				lastFilled = last
			}
			guard count >= Int(limit), last != nil else {
				phase = .done
				return .finished
			}
			guard pages < maximumPages, let next = lastFilled else {
				phase = .fetchingLiveEnd
				return .send(.latest(target: target, after: .unbounded, limit: limit))
			}
			return .send(.after(target: target, next, limit: limit))
		}
	}
}

/** Filling a recorded gap, oldest first, with `BETWEEN` pages.

 It stops on a short page, or when a page reaches the gap's end; after
 `maximumPages` full pages what is still missing is handed back as a smaller
 gap. */
struct ChatHistoryGapFill: Equatable {
	let target: String
	let limit: UInt
	let maximumPages: Int
	private(set) var gap: ChatHistoryGap
	private(set) var pages = 0

	init(target: String, gap: ChatHistoryGap, limit: UInt, maximumPages: Int = 10) {
		self.target = target
		self.gap = gap
		self.limit = max(limit, 1)
		self.maximumPages = max(maximumPages, 1)
	}

	func start() -> ChatHistoryPagingStep {
		.send(.between(target: target, gap.after, gap.before, limit: limit))
	}

	mutating func receivedPage(count: Int, last: ChatHistoryReference?) -> ChatHistoryPagingStep {
		pages += 1
		guard count >= Int(limit), let last, last != gap.before else {
			return .finished
		}
		gap = ChatHistoryGap(after: last, before: gap.before)
		guard pages < maximumPages else {
			return .finishedWithGap(gap)
		}
		return .send(.between(target: target, gap.after, gap.before, limit: limit))
	}
}
