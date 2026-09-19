// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

/// The channel actions the interface can offer from current membership.
/// Recreate this value when performing an action: privileges can change while
/// a menu or an editor is open. The server remains the final authority for
/// network-specific half-operator privileges.
struct ChannelActionPermissions {
	let isJoined: Bool
	let canModifyTopic: Bool
	let canChangeModes: Bool

	init(channel: Conversation?, session: ServerSession?) {
		guard let channel, let session,
		      session.canJoinChannels, channel.associatedSession === session,
		      session.conversationList.contains(where: { $0 === channel }),
		      channel.isChannel, channel.isActive
		else {
			isJoined = false
			canModifyTopic = false
			canChangeModes = false
			return
		}

		isJoined = true
		// Channel prefix rank, rather than global IRC operator status, determines
		// moderation. isHalfOp falls back to operator when PREFIX has no half-op.
		let member = channel.findMember(session.userNickname)
		canChangeModes = member.map { $0.isOp || $0.isHalfOp } == true
		let topicIsRestricted = channel.modeInfo?.modeInfo(for: ChannelMode.operatorTopic.rawValue)?.modeIsSet == true
		canModifyTopic = topicIsRestricted == false || canChangeModes
	}
}
