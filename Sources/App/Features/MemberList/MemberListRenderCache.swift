/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

/// Owned by a transcript controller. Away, account and conversation edits do not
/// rebuild the nickname/mark values its renderer consumes.
@MainActor
final class MemberListRenderCache {
	private weak var memberList: ChannelMemberList?
	private var revision: UInt64?
	private var snapshot: [RenderedMember] = []
	private(set) var rebuildCount = 0

	func members(in channel: IRCChannel?) -> [RenderedMember] {
		guard let list = channel?.memberInfo else {
			memberList = nil
			revision = nil
			snapshot = []
			return []
		}
		if memberList !== list || revision != list.renderRevision {
			memberList = list
			revision = list.renderRevision
			snapshot = list.memberList.map(RenderedMember.init)
			rebuildCount += 1
		}
		return snapshot
	}
}
