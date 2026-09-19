// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Channel action permissions")
struct ChannelActionPermissionsTests {
	@Test("An unrestricted topic is editable by joined users, while modes require channel rank", arguments: ["", "v"])
	func ordinaryMembersCanChangeOnlyUnrestrictedTopics(modes: String) throws {
		let (session, channel) = try joinedChannel(modes: modes)
		var permissions = ChannelActionPermissions(channel: channel, session: session)
		#expect(permissions.isJoined)
		#expect(permissions.canModifyTopic)
		#expect(permissions.canChangeModes == false)
		_ = channel.modeInfo?.updateModes("+t")
		permissions = ChannelActionPermissions(channel: channel, session: session)
		#expect(permissions.canModifyTopic == false)
		#expect(permissions.canChangeModes == false)
	}

	@Test("Advertised half-operators and higher ranks retain moderation actions", arguments: ["h", "o", "a", "q"])
	func advertisedModeratorsCanAct(modes: String) throws {
		let (session, channel) = try joinedChannel(modes: modes)
		_ = channel.modeInfo?.updateModes("+t")
		let permissions = ChannelActionPermissions(channel: channel, session: session)
		#expect(permissions.canModifyTopic)
		#expect(permissions.canChangeModes)
	}

	@Test("Servers without half-operators still allow operators but not voices", arguments: ["o", "v"])
	func ordinaryPrefixTableUsesOperatorThreshold(modes: String) throws {
		let (session, channel) = try joinedChannel(modes: modes, prefixes: "PREFIX=(ov)@+")
		_ = channel.modeInfo?.updateModes("+t")
		let permissions = ChannelActionPermissions(channel: channel, session: session)
		#expect(permissions.canModifyTopic == (modes == "o"))
		#expect(permissions.canChangeModes == (modes == "o"))
	}

	@Test("A global IRC operator without channel privileges cannot moderate")
	func globalOperatorIsNotChannelAuthority() throws {
		let (session, channel) = try joinedChannel(modes: "")
		let user = try #require(channel.findMember(session.userNickname)?.user)
		session.modify(user) { $0.isIRCop = true }
		_ = channel.modeInfo?.updateModes("+t")
		try #require(channel.findMember(session.userNickname)?.user.isIRCop == true)
		let permissions = ChannelActionPermissions(channel: channel, session: session)
		#expect(permissions.canModifyTopic == false)
		#expect(permissions.canChangeModes == false)
	}

	@Test("Stopped, departed and detached channels cannot offer mutations", arguments: 0 ..< 7)
	func unavailableChannelsCannotAct(reason: Int) throws {
		let (session, channel) = try joinedChannel(modes: "o")
		let targetSession: ServerSession?
		switch reason {
		case 0: session.isLoggedIn = false; targetSession = session
		case 1: session.isQuitting = true; targetSession = session
		case 2: session.isDisconnecting = true; targetSession = session
		case 3: session.isTerminating = true; targetSession = session
		case 4: channel.deactivate(); targetSession = session
		case 5: session.remove(channel); targetSession = session
		default: targetSession = TestServerSession()
		}
		let permissions = ChannelActionPermissions(channel: channel, session: targetSession)
		#expect(permissions.isJoined == false)
		#expect(permissions.canModifyTopic == false)
		#expect(permissions.canChangeModes == false)
	}

	private func joinedChannel(
		modes: String,
		prefixes: String = "PREFIX=(qaohv)~&@%+"
	) throws -> (TestServerSession, Conversation) {
		let session = TestServerSession()
		session.userNickname = "local"
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData(prefixes)
		let channel = try #require(session.findConversationOrCreate("#permissions"))
		channel.activate()
		var member = Member(user: session.findUserOrCreate(session.userNickname), prefixes: session.currentUserPrefixes)
		member.modes = ChannelModeSymbolSet(letters: modes)
		channel.addMember(member)
		return (session, channel)
	}
}
