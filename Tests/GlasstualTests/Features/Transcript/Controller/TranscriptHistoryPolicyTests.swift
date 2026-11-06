// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct TranscriptHistoryPolicyTests {
	private nonisolated static let policies: [HistoryLoadPolicy] = {
		let flags = [false, true]
		var all: [HistoryLoadPolicy] = []
		for firstLoad in flags {
			for reload in flags {
				for console in flags {
					for directChat in flags {
						for direct in flags {
							for remembers in flags {
								all.append(HistoryLoadPolicy(
									firstLoad: firstLoad,
									reloadsScrollbackOnLaunch: reload,
									isConsole: console,
									isDirectChat: directChat,
									isDirect: direct,
									remembersDirectConversations: remembers
								))
							}
						}
					}
				}
			}
		}
		return all
	}()

	@Test("The policy reads stored history exactly when the original four-term rule did", arguments: policies)
	func matchesTheOriginalRule(_ policy: HistoryLoadPolicy) {
		let original = !(policy.firstLoad && !policy.reloadsScrollbackOnLaunch ||
			policy.isConsole ||
			policy.isDirectChat ||
			(policy.firstLoad && policy.isDirect && !policy.remembersDirectConversations))
		#expect(policy.includesStoredHistory == original)
	}

	@Test("A console and a direct chat never replay stored history")
	func consoleAndDirectChatNeverReplay() {
		for policy in Self.policies where policy.isConsole || policy.isDirectChat {
			#expect(!policy.includesStoredHistory)
		}
	}

	@Test("Later reloads ignore the launch settings")
	func laterReloadsIgnoreLaunchSettings() {
		for policy in Self.policies where !policy.firstLoad && !policy.isConsole && !policy.isDirectChat {
			#expect(policy.includesStoredHistory)
		}
	}

	@Test("A fetch outcome maps to entries, failure and success")
	func fetchOutcomeMapping() {
		let page = TranscriptHistoryMerge.fetched(.page([]))
		#expect(page.entries.isEmpty && page.failure == nil && page.succeeded)
		let failed = TranscriptHistoryMerge.fetched(.failed(.unavailable))
		#expect(failed.entries.isEmpty && failed.failure == .unavailable && !failed.succeeded)
		let cancelled = TranscriptHistoryMerge.fetched(.cancelled)
		#expect(cancelled.entries.isEmpty && cancelled.failure == nil && !cancelled.succeeded)
	}

	@Test("A replayed line is claimed once and later duplicates render fresh")
	func replayedLinesAreClaimedOnce() {
		let result = TranscriptHistoryMerge.assign(
			identifiers: ["a", "b", "a", "c"],
			replayedLineNumbers: ["a", "c", "z"]
		)
		#expect(result.slots == [.replayed(lineNumber: "a"), .fresh, .fresh, .replayed(lineNumber: "c")])
		#expect(result.consumed == ["a", "c"])
	}

	@Test("Nothing is claimed when no replay overlaps the stored page")
	func noOverlapRendersFresh() {
		let result = TranscriptHistoryMerge.assign(identifiers: ["a", "b"], replayedLineNumbers: [])
		#expect(result.slots == [.fresh, .fresh])
		#expect(result.consumed.isEmpty)
	}
}
