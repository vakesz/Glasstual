/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/// Owns the application's static menu graph. Dynamic channel/member entries
/// are still populated by `MenuActionCoordinator`, but their insertion points
/// are ordinary `NSMenu` instances rather than nib outlets.
@MainActor
enum MenuFactory {
	struct Entry {
		let title: String
		let command: MenuCommand?
		let action: Selector?
		let key: String
		let modifiers: NSEvent.ModifierFlags
		let children: [Entry]
		let isSeparator: Bool

		static func item(
			_ title: String,
			_ command: MenuCommand? = nil,
			_ action: String? = nil,
			key: String = "",
			modifiers: NSEvent.ModifierFlags = .command,
			children: [Entry] = []
		) -> Entry {
			Entry(title: title, command: command, action: action.map(NSSelectorFromString), key: key,
			      modifiers: modifiers, children: children, isSeparator: false)
		}

		static func separator(_ command: MenuCommand? = nil) -> Entry {
			Entry(title: "", command: command, action: nil, key: "", modifiers: [], children: [],
			      isSeparator: true)
		}
	}

	static func install(on controller: MenuController) {
		controller.serverListNoSelectionMenu = menu("Add Server", [
			.item("Add Server…", .serverListAddServer, "addServer:"),
		], controller)
		controller.channelViewChannelNameMenu = menu("Join Channel", [
			.item("Join Channel", .channelNameJoinChannel, "joinChannelClicked:"),
		], controller)
		controller.channelViewURLMenu = menu("URL", [
			.item("Copy URL", .copyLinkURL, "copyUrl:"),
		], controller)
		controller.dockMenu = menu("Glasstual", [
			.item("Disable All Notifications", .dockDisableNotifications, "toggleMuteOnNotifications:"),
			.item("Disable All Notification Sounds", .dockDisableNotificationSounds,
			      "toggleMuteOnNotificationSounds:"),
		], controller)
		controller.channelViewGeneralMenu = menu("Message", channelViewEntries, controller)
		controller.mainMenuChannelMenu = menu("Channel", channelEntries, controller)
		controller.mainMenuQueryMenu = menu("Query", queryEntries, controller)
		controller.mainWindowSegmentedControllerCellMenu = menu("Add", segmentedEntries, controller)
		controller.userControlMenu = menu("Member", memberEntries, controller)

		let mainMenu = menu("Main Menu", mainMenuEntries, controller)
		controller.mainMenuServerMenuItem = mainMenu.item(for: .serverMenu)
		controller.mainMenuChannelMenuItem = mainMenu.item(for: .channelMenu)
		controller.mainMenuQueryMenuItem = mainMenu.item(for: .queryMenu)
		controller.mainMenuNavigationChannelListMenu = mainMenu.item(for: .navigationChannelList)?.submenu ?? NSMenu()
		controller.muteNotificationsFileMenuItem = mainMenu.item(for: .disableNotifications)
		controller.muteNotificationsSoundsFileMenuItem = mainMenu.item(for: .disableNotificationSounds)
		controller.muteNotificationsDockMenuItem = controller.dockMenu.item(for: .dockDisableNotifications)
		controller.muteNotificationsSoundsDockMenuItem = controller.dockMenu.item(for: .dockDisableNotificationSounds)

		NSApp.mainMenu = mainMenu
		NSApp.servicesMenu = mainMenu.item(for: .services)?.submenu
		NSApp.windowsMenu = mainMenu.item(for: .windowMenu)?.submenu
		NSApp.helpMenu = mainMenu.item(for: .helpMenu)?.submenu
	}

	private static func menu(_ title: String, _ entries: [Entry], _ controller: MenuController) -> NSMenu {
		let result = NSMenu(title: title)
		result.delegate = controller
		for entry in entries {
			let item: NSMenuItem
			if entry.isSeparator {
				item = .separator()
			} else {
				item = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.key)
				if let action = entry.action {
					if applicationActions.contains(action) {
						item.target = NSApp
					} else if responderActions.contains(action) {
						item.target = nil
					} else {
						item.target = controller
					}
				}
				item.keyEquivalentModifierMask = entry.key.isEmpty ? [] : entry.modifiers
				if !entry.children.isEmpty {
					item.submenu = menu(entry.title, entry.children, controller)
				} else if entry.command == .services {
					item.submenu = menu(entry.title, [], controller)
				}
			}
			item.command = entry.command
			result.addItem(item)
		}
		return result
	}

	private static let applicationActions = Set([
		#selector(NSApplication.hide(_:)),
		#selector(NSApplication.hideOtherApplications(_:)),
		#selector(NSApplication.unhideAllApplications(_:)),
		#selector(NSApplication.terminate(_:)),
	])

	private static let responderActions = Set([
		"undo:", "redo:", "cut:", "copy:", "delete:", "selectAll:", "toggleFullScreen:",
		"performMiniaturize:", "performZoom:", "arrangeInFront:",
	].map(NSSelectorFromString))

	private static let mainMenuEntries: [Entry] = [
		.item("Glasstual", .applicationMenu, children: applicationEntries),
		.item("File", .fileMenu, children: fileEntries),
		.item("Edit", .editMenu, children: editEntries),
		.item("View", .viewMenu, children: viewEntries),
		.item("Server", .serverMenu, children: serverEntries),
		.item("Channel", .channelMenu),
		.item("Query", .queryMenu),
		.item("Navigation", .navigationMenu, children: navigationEntries),
		.item("Window", .windowMenu, children: windowEntries),
		.item("Help", .helpMenu, children: helpEntries),
	]

	private static let applicationEntries: [Entry] = [
		.item("About Glasstual", .about, "showAboutWindow:"),
		.separator(.aboutSeparator),
		.item("Settings…", .settings, "showPreferencesWindow:", key: ","),
		.separator(.settingsSeparator),
		.item("Services", .services, children: []),
		.separator(.servicesSeparator),
		.item("Hide Glasstual", .hideApplication, "hide:", key: "h"),
		.item("Hide Others", .hideOthers, "hideOtherApplications:", key: "h", modifiers: [.command, .option]),
		.item("Show All", .showAll, "unhideAllApplications:"),
		.separator(.showAllSeparator),
		.item("Quit Glasstual", .quit, "terminate:", key: "q"),
	]

	private static let fileEntries: [Entry] = [
		.item("Disable All Notifications", .disableNotifications, "toggleMuteOnNotifications:"),
		.item("Disable All Notification Sounds", .disableNotificationSounds,
		      "toggleMuteOnNotificationSounds:", key: "M"),
		.separator(.disableNotificationSoundsSeparator),
		.item("Print", .printLog, "print:", key: "p"),
		.separator(.printLogSeparator),
		.item("Close Window", .closeWindow, "closeWindow:", key: "w"),
	]

	private static let editEntries: [Entry] = [
		.item("Undo", .undo, "undo:", key: "z"), .item("Redo", .redo, "redo:", key: "Z"),
		.separator(.redoSeparator),
		.item("Cut", .cut, "cut:", key: "x"), .item("Copy", .copy, "copy:", key: "c"),
		.item("Paste", .paste, "paste:", key: "v"), .item("Delete", .delete, "delete:"),
		.item("Select All", .selectAll, "selectAll:", key: "a"), .separator(.selectAllSeparator),
		.item("Find", .find, children: [
			.item("Find…", .findText, "showFindPrompt:", key: "f"),
			.item("Find Next", .findNext, "showFindPrompt:", key: "g"),
			.item("Find Previous", .findPrevious, "showFindPrompt:", key: "G", modifiers: [.command, .shift]),
		]),
	]

	private static let viewEntries: [Entry] = [
		.item("Mark Scrollback", .markScrollback, "markScrollback:", key: "l"),
		.item("Scrollback Marker", .scrollbackMarker, "gotoScrollbackMarker:", key: "l",
		      modifiers: [.command, .control]),
		.separator(.scrollbackMarkerSeparator),
		.item("Mark All As Read", .markAllRead, "markAllAsRead:", key: "U"),
		.item("Clear Scrollback", .clearScrollback, "clearScrollback:", key: "k"),
		.separator(.clearScrollbackSeparator),
		.item("Increase Font Size", .increaseFont, "increaseLogFontSize:", key: "="),
		.item("Decrease Font Size", .decreaseFont, "decreaseLogFontSize:", key: "-"),
		.separator(.decreaseFontSeparator),
		.item("Enter Full Screen", .enterFullScreen, "toggleFullScreen:", key: "f", modifiers: [.command, .control]),
	]

	private static let serverEntries: [Entry] = [
		.item("Connect", .connect, "connect:"), .item(
			"Connect Without Proxy",
			.connectWithoutProxy,
			"connectBypassingProxy:"
		),
		.item("Disconnect", .disconnect, "disconnect:"), .item(
			"Cancel Reconnect",
			.cancelReconnect,
			"cancelReconnection:"
		),
		.separator(.cancelReconnectSeparator), .item("Channel List…", .channelList, "showServerChannelList:"),
		.item("Change Nickname…", .changeNickname, "showServerChangeNicknameSheet:"),
		.separator(.changeNicknameSeparator), .item("Add Server…", .addServer, "addServer:"),
		.item("Duplicate Server", .duplicateServer, "duplicateServer:"), .item(
			"Delete Server…",
			.deleteServer,
			"deleteServer:"
		),
		.separator(.deleteServerSeparator), .item("Add Channel…", .addChannelToServer, "addChannel:"),
		.separator(.addChannelToServerSeparator), .item(
			"Server Properties…",
			.serverProperties,
			"showServerPropertiesSheet:",
			key: "u"
		),
	]

	private static let channelEntries: [Entry] = [
		.item("Join Channel", .joinChannel, "joinChannel:"), .item("Leave Channel", .leaveChannel, "leaveChannel:"),
		.separator(.leaveChannelSeparator), .item(
			"Add Channel…",
			.addChannel,
			"addChannel:",
			key: "+",
			modifiers: [.command, .shift]
		),
		.item("Delete Channel", .deleteChannel, "deleteChannel:"), .separator(.deleteChannelSeparator),
		.item("View Logs", .viewChannelLogs, "openChannelLogs:", key: "L"), .separator(.viewChannelLogsSeparator),
		.item("Modify Topic", .modifyTopic, "showChannelModifyTopicSheet:", key: "t"),
		.item("Modes", .modes, children: [
			.item("Moderated (+m)", .channelModeModerated, "toggleChannelModerationMode:"),
			.item("Unmoderated (-m)", .channelModeUnmoderated, "toggleChannelModerationMode:"),
			.item("Invite Only (+i)", .channelModeInviteOnly, "toggleChannelInviteMode:"),
			.item("Anyone Can Join (-i)", .channelModeAnyoneCanJoin, "toggleChannelInviteMode:"),
			.item("Manage All Modes", .channelModeManageAll, "showChannelModifyModesSheet:"),
		]),
		.separator(.modesSeparator), .item("List of Bans", .bans, "showChannelBanList:", key: "B"),
		.item("List of Ban Exceptions", .banExceptions, "showChannelBanExceptionList:", key: "E"),
		.item("List of Invite Exceptions", .inviteExceptions, "showChannelInviteExceptionList:", key: "I"),
		.item("List of Quiets", .quiets, "showChannelQuietList:"), .separator(.quietsSeparator),
		.item("Channel Properties…", .channelProperties, "showChannelPropertiesSheet:", key: "i"),
		.separator(.channelPropertiesSeparator), .item(
			"Copy Unique Identifier",
			.copyChannelIdentifier,
			"copyUniqueIdentifier:"
		),
	]

	private static let queryEntries: [Entry] = [
		.item("Close Query", .closeQuery, "leaveChannel:"), .separator(.closeQuerySeparator),
		.item("Query Logs", .queryLogs, "openChannelLogs:", key: "L"),
	]

	private static let navigationEntries: [Entry] = [
		.item("Servers", .navigationServers, children: [
			.item("Next Server", .nextServer, "performNavigationAction:"),
			.item("Previous Server", .previousServer, "performNavigationAction:"),
			.separator(.previousServerSeparator),
			.item("Next Active Server", .nextActiveServer, "performNavigationAction:"),
			.item("Previous Active Server", .previousActiveServer, "performNavigationAction:"),
		]),
		.item("Channels", .navigationChannels, children: [
			.item("Next Channel", .nextChannel, "performNavigationAction:"),
			.item("Previous Channel", .previousChannel, "performNavigationAction:"),
			.separator(.previousChannelSeparator),
			.item("Next Active Channel", .nextActiveChannel, "performNavigationAction:"),
			.item("Previous Active Channel", .previousActiveChannel, "performNavigationAction:"),
			.separator(.previousActiveChannelSeparator),
			.item("Next Unread Channel", .nextUnreadChannel, "performNavigationAction:"),
			.item("Previous Unread Channel", .previousUnreadChannel, "performNavigationAction:"),
		]),
		.separator(.navigationChannelsSeparator),
		.item("Move Backward", .moveBackward, "performNavigationAction:"),
		.item("Move Forward", .moveForward, "performNavigationAction:"), .separator(.moveForwardSeparator),
		.item("Previous Selection", .previousSelection, "performNavigationAction:"),
		.separator(.previousSelectionSeparator),
		.item("Next Highlight", .nextHighlight, "onNextHighlight:"),
		.item("Previous Highlight", .previousHighlight, "onPreviousHighlight:"),
		.separator(.previousHighlightSeparator),
		.item("Jump to Current Session", .jumpToCurrentSession, "jumpToCurrentSession:"),
		.item("Jump to Present", .jumpToPresent, "jumpToPresent:"), .separator(.jumpToPresentSeparator),
		.item("Channel List…", .navigationChannelList, children: [.item("Item")]),
		.separator(.navigationChannelListSeparator), .item(
			"Search channels…",
			.searchChannels,
			"showChannelSpotlightWindow:",
			key: "d"
		),
	]

	private static let windowEntries: [Entry] = [
		.item("Minimize", .minimize, "performMiniaturize:", key: "m"), .item("Zoom", .zoom, "performZoom:"),
		.separator(.zoomSeparator), .item(
			"Hide Member List",
			.toggleMemberList,
			"toggleMemberListVisibility:",
			key: "u",
			modifiers: [.command, .option]
		),
		.item(
			"Hide Server List",
			.toggleServerList,
			"toggleServerListVisibility:",
			key: "s",
			modifiers: [.command, .option]
		),
		.item("Toggle Window Appearance", .toggleAppearance, "toggleMainWindowAppearance:", key: "D"),
		.separator(.toggleAppearanceSeparator), .item(
			"Sort Channel List",
			.sortChannelList,
			"sortChannelListNames:",
			key: "r"
		),
		.separator(.sortChannelListSeparator), .item("Center Window", .centerWindow, "centerMainWindow:"),
		.item("Reset Window to Default Size", .resetWindow, "resetMainWindowFrame:"), .separator(.resetWindowSeparator),
		.item("Main Window", .mainWindow, "showMainWindow:", key: "1", modifiers: .control),
		.item("Address Book", .addressBook, "showAddressBook:", key: "2", modifiers: .control),
		.item("Ignore List", .ignoreList, "showIgnoreList:", key: "3", modifiers: .control),
		.item("View Logs", .viewLogs, "openLogLocation:", key: "4", modifiers: .control),
		.item("Highlight List", .highlightList, "showServerHighlightList:", key: "5", modifiers: .control),
		.item("File Transfers", .fileTransfers, "showFileTransfersWindow:", key: "6", modifiers: .control),
		.separator(.fileTransfersSeparator), .item("Bring All to Front", .bringAllToFront, "arrangeInFront:"),
	]

	private static let helpEntries: [Entry] = [
		.item("Acknowledgements", .acknowledgements, "openAcknowledgements:"), .separator(.acknowledgementsSeparator),
		.item("Connect to Help Channel", .connectToHelpChannel, "connectToGlasstualHelpChannel:"),
		.item("Connect to Testing Channel", .connectToTestingChannel, "connectToGlasstualTestingChannel:"),
		.separator(.connectToTestingChannelSeparator),
		.item("Advanced", .advanced, children: [
			.item("Enable Developer Mode", .developerMode, "toggleDeveloperMode:"),
			.item("Hidden Settings…", .hiddenSettings, "showHiddenPreferences:"),
			.item("Export Preferences", .exportPreferences, "exportPreferences:"),
			.item("Import Preferences", .importPreferences, "importPreferences:"),
			.item("Reset Don't Ask Me Warnings", .resetDontAskMeWarnings, "resetDoNotAskMePopupWarnings:"),
		]),
		.separator(.advancedSeparator), .item("Welcome to Glasstual…", .welcome, "showOnboardingWindow:"),
	]

	private static let channelViewEntries: [Entry] = [
		.item("Change Nickname…", .webChangeNickname, "showServerChangeNicknameSheet:"),
		.separator(.webChangeNicknameSeparator), .item("Search With Google", .webSearch, "searchGoogle:"),
		.item("Look Up in Dictionary", .webDictionary, "lookUpInDictionary:"), .separator(.webDictionarySeparator),
		.item("Copy", .webCopy, "copy:", key: "c"), .item("Paste", .webPaste, "paste:", key: "v"),
		.separator(.webPasteSeparator), .item("Query Logs", .webQueryLogs, "openChannelLogs:", key: "L"),
		.item("Channel", .webChannelMenu),
	]

	private static let segmentedEntries: [Entry] = [
		.item("Add Server…", .segmentedAddServer, "addServer:"), .separator(.segmentedAddServerSeparator),
		.item("Add Channel…", .segmentedAddChannel, "addChannel:"),
	]

	private static let memberEntries: [Entry] = [
		.item("Add Ignore", .addIgnore, "memberAddIgnore:"), .item(
			"Modify Ignore",
			.modifyIgnore,
			"memberModifyIgnore:"
		),
		.item("Remove Ignore", .removeIgnore, "memberRemoveIgnore:"), .separator(.removeIgnoreSeparator),
		.item("Invite to…", .inviteTo, "memberSendInvite:"), .separator(.inviteToSeparator),
		.item("Get Info (Whois)", .whois, "memberSendWhois:"),
		.item("Private Message (Query)", .privateMessage, "memberStartPrivateMessage:"),
		.separator(.privateMessageSeparator),
		.item("Give Op (+o)", .giveOp, "memberModeGiveOp:"), .item(
			"Give Halfop (+h)",
			.giveHalfop,
			"memberModeGiveHalfop:"
		),
		.item("Give Voice (+v)", .giveVoice, "memberModeGiveVoice:"),
		.item("All Modes Given", .allModesGiven), .separator(.allModesGivenSeparator),
		.item("Take Op (-o)", .takeOp, "memberModeTakeOp:"), .item(
			"Take Halfop (-h)",
			.takeHalfop,
			"memberModeTakeHalfop:"
		),
		.item("Take Voice (-v)", .takeVoice, "memberModeTakeVoice:"),
		.item("All Modes Taken", .allModesTaken), .separator(.allModesTakenSeparator),
		.item("Ban", .ban, "memberBanFromChannel:"), .item("Kick", .kick, "memberKickFromChannel:"),
		.item("Ban and Kick", .kickban, "memberKickbanFromChannel:"),
		.separator(.kickbanSeparator),
		.item("Client-to-Client", .ctcp, children: [
			.item("Send File…", .ctcpSendFile, "memberSendFileRequest:"),
			.separator(.ctcpSendFileSeparator),
			.item("Lag (PING)", .ctcpPing, "memberSendCTCPPing:"),
			.item("Local Time (TIME)", .ctcpTime, "memberSendCTCPTime:"),
			.separator(.ctcpTimeSeparator),
			.item("Client Information (CLIENTINFO)", .ctcpClientInfo, "memberSendCTCPClientInfo:"),
			.item("Client Version (VERSION)", .ctcpVersion, "memberSendCTCPVersion:"),
			.separator(.ctcpVersionSeparator),
			.item("User Information (FINGER)", .ctcpFinger, "memberSendCTCPFinger:"),
			.item("User Information (USERINFO)", .ctcpUserInfo, "memberSendCTCPUserinfo:"),
		]),
		.item("IRC Operator", .ircOperator, children: [
			.item("Set Virtual Host (vHost)", .operatorSetVirtualHost, "showSetVhostPrompt:"),
			.separator(.operatorSetVirtualHostSeparator),
			.item("Kill from Server", .operatorKill, "memberKillFromServer:"),
			.item("Shun on Server", .operatorShun, "memberShunOnServer:"),
			.item("Ban from Server (G:Line)", .operatorGline, "memberBanFromServer:"),
		]),
		.item("Change Color…", .changeColor, "memberChangeColor:"),
	]
}
