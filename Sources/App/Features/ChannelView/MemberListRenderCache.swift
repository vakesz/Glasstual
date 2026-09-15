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

/** The channel's members as the renderer reads them, rebuilt only when the
 names, marks, membership or casemapping change.

 Owned by a transcript controller. Away, account and conversation edits do not
 rebuild it; nor does printing, however many lines use it. */
@MainActor
final class MemberListRenderCache {
	private weak var memberList: ChannelMemberList?
	private var revision: UInt64?
	private var directory: RenderedMemberDirectory = []
	/// How many times the directory was built, which is what says a burst of
	/// prints or a conversation-weight edit reused it.
	private(set) var rebuildCount = 0

	func members(in channel: Channel?) -> RenderedMemberDirectory {
		guard let list = channel?.memberInfo else {
			memberList = nil
			revision = nil
			directory = []
			return []
		}
		let caseMapping = channel?.associatedClient?.supportInfo.caseMapping ?? .rfc1459
		if memberList !== list || revision != list.renderRevision || directory.caseMapping != caseMapping {
			memberList = list
			revision = list.renderRevision
			directory = RenderedMemberDirectory(list.memberList.map(RenderedMember.init), caseMapping: caseMapping)
			rebuildCount += 1
		}
		return directory
	}
}
