// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// What a channel or member command needs from the selection before it may be
/// chosen. A command's whole rule is a set of these, so reading the table says
/// what it needs without tracing a branch.
nonisolated struct MenuCommandRequirement: OptionSet, Sendable {
	let rawValue: Int

	/// A server is selected.
	static let session = Self(rawValue: 1 << 0)
	/// The selected server has finished registering.
	static let loggedIn = Self(rawValue: 1 << 1)
	/// The selected server reports its user as an IRC operator.
	static let ircOperator = Self(rawValue: 1 << 2)
	/// A conversation is selected.
	static let conversation = Self(rawValue: 1 << 3)
	/// A conversation is selected and it is not the server console.
	static let notConsole = Self(rawValue: 1 << 4)
	/// The selected conversation is a channel.
	static let channel = Self(rawValue: 1 << 5)
	/// The selected conversation is a channel or a direct conversation.
	static let channelOrDirect = Self(rawValue: 1 << 6)
	/// The selected conversation is active.
	static let activeConversation = Self(rawValue: 1 << 7)
	/// The user is in the selected channel.
	static let joined = Self(rawValue: 1 << 8)
	/// The selected channel is one the user may join now.
	static let joinable = Self(rawValue: 1 << 9)
	/// The user's rank in the channel allows changing modes.
	static let canChangeModes = Self(rawValue: 1 << 10)
	/// The user's rank and the channel's topic mode allow changing the topic.
	static let canModifyTopic = Self(rawValue: 1 << 11)
	/// Another channel exists on the server to invite to.
	static let otherChannelExists = Self(rawValue: 1 << 12)
	/// Transcripts are being written to disk.
	static let writingTranscripts = Self(rawValue: 1 << 13)
	/// The server supports the ban exception list.
	static let banExceptionList = Self(rawValue: 1 << 14)
	/// The server supports the invite exception list.
	static let inviteExceptionList = Self(rawValue: 1 << 15)
	/// The server supports the quiet list.
	static let quietList = Self(rawValue: 1 << 16)

	/// Acting on a member of the active channel.
	static let channelManagement: Self = [.loggedIn, .channel, .activeConversation]
}

extension MenuCommand {
	/// The requirements of a channel-menu command, or `nil` where it has no rule
	/// beyond being shown.
	var channelRequirements: MenuCommandRequirement? {
		switch self {
		case .toggleFavorite: .channelOrDirect
		case .joinChannel: .joinable
		case .leaveChannel, .bans: .joined
		case .addChannel: .session
		case .viewChannelLogs: [.conversation, .writingTranscripts]
		case .modifyTopic: .canModifyTopic
		case .modes, .channelModeManageAll, .channelModeModerated, .channelModeInviteOnly: .canChangeModes
		case .banExceptions: [.joined, .banExceptionList]
		case .inviteExceptions: [.joined, .inviteExceptionList]
		case .quiets: [.joined, .quietList]
		case .channelProperties: .channel
		case .copyChannelIdentifier: .conversation
		default: nil
		}
	}

	/// The requirements of a member-menu command that depend only on the
	/// selected server and conversation. Commands that also read the selected
	/// members are decided in the validator.
	var memberRequirements: MenuCommandRequirement? {
		switch self {
		case .inviteTo: [.loggedIn, .notConsole, .otherChannelExists]
		case .whois, .ctcp, .ctcpSendFile, .ctcpSendFileSecurely, .ctcpPing, .ctcpTime,
		     .ctcpClientInfo, .ctcpVersion, .ctcpFinger, .ctcpUserInfo:
			[.loggedIn, .notConsole]
		case .startDirectConversation: [.loggedIn, .channel]
		case .messagePrivatelyInChannel: [.loggedIn, .channel]
		case .changeColor: .channel
		case .ban, .banAccount, .kick, .kickban: .channelManagement
		case .ircOperator, .operatorSetVirtualHost, .operatorKill, .operatorShun, .operatorGline:
			[.ircOperator, .loggedIn, .notConsole]
		default: nil
		}
	}
}

/// The selection a command is judged against. It holds the two objects and
/// answers each requirement on demand, so the permission and list lookups run
/// only for commands that ask for them.
@MainActor
struct MenuCommandContext {
	let session: ServerSession?
	let conversation: Conversation?

	func satisfies(_ requirements: MenuCommandRequirement) -> Bool {
		let checks: [(MenuCommandRequirement, () -> Bool)] = [
			(.session, { session != nil }),
			(.loggedIn, { session?.isLoggedIn == true }),
			(.ircOperator, { session?.identity.isIRCop == true }),
			(.conversation, { conversation != nil }),
			(.notConsole, { conversation?.isConsole == false }),
			(.channel, { conversation?.isChannel == true }),
			(.channelOrDirect, { conversation.map { $0.isChannel || $0.isDirect } == true }),
			(.activeConversation, { conversation?.isActive == true }),
			(.joined, { permissions.isJoined }),
			(.joinable, { conversation.map { session?.canJoin($0) == true } == true }),
			(.canChangeModes, { permissions.canChangeModes }),
			(.canModifyTopic, { permissions.canModifyTopic }),
			(.otherChannelExists, { hasOtherChannel }),
			(.writingTranscripts, { ApplicationPaths.isWritingTranscripts }),
			(.banExceptionList, { session?.supportInfo.isListSupported(.banException) == true }),
			(.inviteExceptionList, { session?.supportInfo.isListSupported(.inviteException) == true }),
			(.quietList, { session?.supportInfo.isListSupported(.quiet) == true }),
		]

		return checks.allSatisfy { requirement, isMet in
			requirements.contains(requirement) == false || isMet()
		}
	}

	var permissions: ChannelActionPermissions {
		ChannelActionPermissions(channel: conversation, session: session)
	}

	private var hasOtherChannel: Bool {
		session?.conversationList.contains { $0 !== conversation && $0.isChannel } == true
	}
}
