// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension MenuGraph {
	static let serverEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuServerConnect), .connect, #selector(MenuActionController.connect(_:))),
		/* Option reveals the proxy-free variant in place, which is how macOS
			offers a modified form of the command above it. AppKit swaps in an
			alternate whose modifiers differ from the primary's, and Connect has
			none. Option alone therefore has to be the whole mask, or the swap
			waits for Command as well. */
		.item(
			String(localized: .MainWindow.menuServerConnectWithoutProxy),
			.connectWithoutProxy,
			#selector(MenuActionController.connectBypassingProxy(_:)),
			modifiers: .option,
			isAlternate: true
		),
		.item(String(localized: .MainWindow.menuServerDisconnect), .disconnect, #selector(MenuActionController.disconnect(_:))),
		.item(
			String(localized: .MainWindow.menuServerCancelReconnect),
			.cancelReconnect,
			#selector(MenuActionController.cancelReconnection(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerChannelList),
			.channelList,
			#selector(MenuActionController.showServerChannelList(_:))
		),
		.item(
			String(localized: .MainWindow.menuServerChangeNickname),
			.changeNickname,
			#selector(MenuActionController.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuServerAddServer), .addServer, #selector(MenuActionController.addServer(_:))),
		.item(
			String(localized: .MainWindow.menuServerDuplicateServer),
			.duplicateServer,
			#selector(MenuActionController.duplicateServer(_:))
		),
		.item(String(localized: .MainWindow.menuServerDeleteServer), .deleteServer, #selector(MenuActionController.deleteServer(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerAddChannel),
			.addChannel,
			#selector(MenuActionController.addChannel(_:))
		),
		.separator(),
		/* ⌘U belongs to Underline now. The comma key already names "the
			settings of", so the three scopes read as one family: ⌘, for the
			application, ⇧⌘, for the server, ⌥⌘, for the channel. */
		.item(
			String(localized: .MainWindow.menuServerProperties),
			.serverProperties,
			#selector(MenuActionController.showServerPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .shift]
		),
	]

	private static let favoriteEntry = Entry.item(
		String(localized: .Sidebar.pinFavorite), .toggleFavorite, #selector(MenuActionController.toggleFavorite(_:))
	)

	static let channelEntries: [Entry] = [
		favoriteEntry,
		.separator(),
		.item(String(localized: .MainWindow.menuChannelJoin), .joinChannel, #selector(MenuActionController.joinChannel(_:))),
		.item(String(localized: .MainWindow.menuChannelLeave), .leaveChannel, #selector(MenuActionController.leaveConversation(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerAddChannel),
			.addChannel,
			#selector(MenuActionController.addChannel(_:)),
			key: "+",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelDelete),
			.deleteChannel,
			#selector(MenuActionController.deleteConversation(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelViewLogs),
			.viewChannelLogs,
			#selector(MenuActionController.openConversationLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelModifyTopic),
			.modifyTopic,
			#selector(MenuActionController.showChannelModifyTopicSheet(_:)),
			key: "t"
		),
		.item(String(localized: .MainWindow.menuChannelModes), .modes, children: [
			.item(
				String(localized: .MainWindow.menuChannelModeModerated),
				.channelModeModerated,
				#selector(MenuActionController.toggleChannelModerationMode(_:))
			),
			.item(
				String(localized: .MainWindow.menuChannelModeInviteOnly),
				.channelModeInviteOnly,
				#selector(MenuActionController.toggleChannelInviteMode(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuChannelModeManageAll),
				.channelModeManageAll,
				#selector(MenuActionController.showChannelModifyModesSheet(_:))
			),
		]),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelBans),
			.bans,
			#selector(MenuActionController.showChannelMaskList(_:)),
			key: "b",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelBanExceptions),
			.banExceptions,
			#selector(MenuActionController.showChannelBanExceptionList(_:)),
			key: "e",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelInviteExceptions),
			.inviteExceptions,
			#selector(MenuActionController.showChannelInviteExceptionList(_:)),
			key: "i",
			modifiers: [.command, .shift]
		),
		.item(String(localized: .MainWindow.menuChannelQuiets), .quiets, #selector(MenuActionController.showChannelQuietList(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelProperties),
			.channelProperties,
			#selector(MenuActionController.showChannelPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelCopyUniqueIdentifier),
			.copyChannelIdentifier,
			#selector(MenuActionController.copyUniqueIdentifier(_:))
		),
	]

	/*  The menu for a one-to-one conversation.

	 Query Logs carries no key equivalent. Channel ▸ View Logs sends the same
	 action, validates for a one-to-one conversation too, and already answers
	 Shift-Command-L. Two menu-bar items on one shortcut leave AppKit to pick
	 one of them. */

	static let directEntries: [Entry] = [
		favoriteEntry,
		.separator(),
		.item(String(localized: .MainWindow.menuQueryClose), .closeQuery, #selector(MenuActionController.leaveConversation(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuQueryLogs),
			.queryLogs,
			#selector(MenuActionController.openConversationLogs(_:))
		),
	]

	static let navigationEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuNavigationServers), .navigationServers, children: [
			.item(
				String(localized: .MainWindow.menuNavigationNextServer),
				.nextServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousServer),
				.previousServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextActiveServer),
				.nextActiveServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousActiveServer),
				.previousActiveServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuNavigationChannels), .navigationChannels, children: [
			.item(
				String(localized: .MainWindow.menuNavigationNextChannel),
				.nextChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousChannel),
				.previousChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextActiveChannel),
				.nextActiveChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousActiveChannel),
				.previousActiveChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextUnreadChannel),
				.nextUnreadChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousUnreadChannel),
				.previousUnreadChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
		]),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationMoveBackward),
			.moveBackward,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationMoveForward),
			.moveForward,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationPreviousSelection),
			.previousSelection,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationNextHighlight),
			.nextHighlight,
			#selector(MenuActionController.onNextHighlight(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationPreviousHighlight),
			.previousHighlight,
			#selector(MenuActionController.onPreviousHighlight(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationJumpToCurrentSession),
			.jumpToCurrentSession,
			#selector(MenuActionController.jumpToCurrentSession(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationJumpToPresent),
			.jumpToPresent,
			#selector(MenuActionController.jumpToPresent(_:))
		),
		.separator(),
		/* The untitled child is what gives the item a submenu to hand to
			`mainMenuNavigationConversationListMenu`, which is refilled wholesale
			whenever the sidebar changes. */
		.item(String(localized: .MainWindow.menuNavigationChannelList), .navigationChannelList, children: [.item("")]),
		.separator(),
		/* The sidebar filter moved into the window toolbar, so this focuses that
			field. Conversation Search keeps its own item below rather than being
			left with no way in. */
		.item(
			String(localized: .MainWindow.menuNavigationSearchChannels),
			.searchChannels,
			#selector(MenuActionController.focusSearchField(_:)),
			key: "f",
			modifiers: [.command, .option]
		),
		/* Shift-Command-O, the key Xcode's Open Quickly uses for the same kind
			of type-to-jump panel. Option-Command-D is the system's Dock hiding
			shortcut and never reached this item. */
		.item(
			String(localized: .MainWindow.menuNavigationChannelSpotlight),
			.channelSpotlight,
			#selector(MenuActionController.showChannelSpotlightWindow(_:)),
			key: "o",
			modifiers: [.command, .shift]
		),
	]

	static let transcriptEntries: [Entry] = [
		.item(
			String(localized: .MainWindow.menuServerChangeNickname),
			.changeNickname,
			#selector(MenuActionController.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(
			SystemWebSearch.menuTitle,
			.webSearch,
			#selector(MenuActionController.searchWeb(_:))
		),
		.item(
			String(localized: .MainWindow.menuTranscriptLookUpInDictionary),
			.transcriptDictionary,
			#selector(MenuActionController.lookUpInDictionary(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuEditCopy), .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(String(localized: .MainWindow.menuEditPaste), .paste, #selector(MenuActionController.paste(_:)), key: "v"),
		.separator(),
		.item(
			String(localized: .MainWindow.menuQueryLogs),
			.queryLogs,
			#selector(MenuActionController.openConversationLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.item(String(localized: .MainWindow.menuBarChannel), .transcriptChannelMenu),
	]

	static let memberEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuMemberMute), .muteUser, #selector(MenuActionController.memberMute(_:))),
		.item(String(localized: .MainWindow.menuMemberUnmute), .unmuteUser, #selector(MenuActionController.memberUnmute(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberAddIgnore), .addIgnore, #selector(MenuActionController.memberAddIgnore(_:))),
		.item(
			String(localized: .MainWindow.menuMemberModifyIgnore),
			.modifyIgnore,
			#selector(MenuActionController.memberModifyIgnore(_:))
		),
		.item(
			String(localized: .MainWindow.menuMemberRemoveIgnore),
			.removeIgnore,
			#selector(MenuActionController.memberRemoveIgnore(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberInviteTo), .inviteTo, #selector(MenuActionController.memberSendInvite(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberWhois), .whois, #selector(MenuActionController.memberSendWhois(_:))),
		.item(
			String(localized: .MainWindow.menuMemberPrivateMessage),
			.startDirectConversation,
			#selector(MenuActionController.memberStartDirectConversation(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberGiveOp), .giveOp, #selector(MenuActionController.memberModeGiveOp(_:))),
		.item(
			String(localized: .MainWindow.menuMemberGiveHalfop),
			.giveHalfop,
			#selector(MenuActionController.memberModeGiveHalfop(_:))
		),
		.item(String(localized: .MainWindow.menuMemberGiveVoice), .giveVoice, #selector(MenuActionController.memberModeGiveVoice(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberTakeOp), .takeOp, #selector(MenuActionController.memberModeTakeOp(_:))),
		.item(
			String(localized: .MainWindow.menuMemberTakeHalfop),
			.takeHalfop,
			#selector(MenuActionController.memberModeTakeHalfop(_:))
		),
		.item(String(localized: .MainWindow.menuMemberTakeVoice), .takeVoice, #selector(MenuActionController.memberModeTakeVoice(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberBan), .ban, #selector(MenuActionController.memberBanFromChannel(_:))),
		.item(String(localized: .MainWindow.menuMemberKick), .kick, #selector(MenuActionController.memberKickFromChannel(_:))),
		.item(
			String(localized: .MainWindow.menuMemberKickban),
			.kickban,
			#selector(MenuActionController.memberKickbanFromChannel(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberCtcp), .ctcp, children: [
			.item(
				String(localized: .MainWindow.menuMemberSendFile),
				.ctcpSendFile,
				#selector(MenuActionController.memberSendFileRequest(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuMemberCtcpPing), .ctcpPing, #selector(MenuActionController.memberSendCTCPPing(_:))),
			.item(String(localized: .MainWindow.menuMemberCtcpTime), .ctcpTime, #selector(MenuActionController.memberSendCTCPTime(_:))),
			.separator(),
			.item(
				String(localized: .MainWindow.menuMemberCtcpClientInfo),
				.ctcpClientInfo,
				#selector(MenuActionController.memberSendCTCPClientInfo(_:))
			),
			.item(
				String(localized: .MainWindow.menuMemberCtcpVersion),
				.ctcpVersion,
				#selector(MenuActionController.memberSendCTCPVersion(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuMemberCtcpFinger),
				.ctcpFinger,
				#selector(MenuActionController.memberSendCTCPFinger(_:))
			),
			.item(
				String(localized: .MainWindow.menuMemberCtcpUserInfo),
				.ctcpUserInfo,
				#selector(MenuActionController.memberSendCTCPUserinfo(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuMemberIrcOperator), .ircOperator, children: [
			.item(
				String(localized: .MainWindow.menuMemberSetVirtualHost),
				.operatorSetVirtualHost,
				#selector(MenuActionController.memberSetVirtualHost(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuMemberKill), .operatorKill, #selector(MenuActionController.memberKillFromServer(_:))),
			.item(String(localized: .MainWindow.menuMemberShun), .operatorShun, #selector(MenuActionController.memberShunOnServer(_:))),
			.item(String(localized: .MainWindow.menuMemberGline), .operatorGline, #selector(MenuActionController.memberBanFromServer(_:))),
		]),
		.item(String(localized: .MainWindow.menuMemberChangeColor), .changeColor, #selector(MenuActionController.memberChangeColor(_:))),
	]
}
