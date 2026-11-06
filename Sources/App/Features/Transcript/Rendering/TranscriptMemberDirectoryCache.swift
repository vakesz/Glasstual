// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The conversation's members as the renderer reads them, rebuilt only when the
 names, marks, membership or casemapping change.

 Owned by a transcript controller. Away, account and conversation edits do not
 rebuild it; nor does printing, however many lines use it. */
@MainActor
final class TranscriptMemberDirectoryCache {
	private weak var memberList: ConversationMembers?
	private var revision: UInt64?
	private var directory: RenderedMemberDirectory = []
	/// How many times the directory was built, which is what says a burst of
	/// prints or a conversation-weight edit reused it.
	private(set) var rebuildCount = 0

	func members(in conversation: Conversation?) -> RenderedMemberDirectory {
		guard let list = conversation?.memberInfo else {
			memberList = nil
			revision = nil
			directory = []
			return []
		}
		let caseMapping = conversation?.associatedSession?.supportInfo.caseMapping ?? .rfc1459
		if memberList !== list || revision != list.renderRevision || directory.caseMapping != caseMapping {
			memberList = list
			revision = list.renderRevision
			directory = RenderedMemberDirectory(list.memberList.map(RenderedMember.init), caseMapping: caseMapping)
			rebuildCount += 1
		}
		return directory
	}
}
