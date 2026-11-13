// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

struct HistoryLoadPolicyTests {
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
}
