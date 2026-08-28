/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import AppKit

/// Every command the application's menus can issue, keyed by the tag stored in
/// `TXCMainMenu.xib`. The raw values are the nib's tags, so they are frozen:
/// changing one silently repoints a menu item. Symbol art, validation grouping
/// and the sheet/essential policy all key off this one vocabulary instead of
/// the three parallel tables that preceded it.
public enum MenuCommand: Int, CaseIterable, Sendable {
	case applicationMenu = 1 // Glasstual
	case fileMenu = 2 // File
	case editMenu = 3 // Edit
	case viewMenu = 4 // View
	case serverMenu = 5 // Server
	case channelMenu = 6 // Channel
	case queryMenu = 7 // Query
	case navigationMenu = 8 // Navigation
	case windowMenu = 9 // Window
	case helpMenu = 10 // Help
	case about = 100 // About Glasstual
	case aboutSeparator = 101
	case settings = 102 // Settings…
	case settingsSeparator = 106
	case services = 107 // Services
	case servicesSeparator = 108
	case hideApplication = 109 // Hide Glasstual
	case hideOthers = 110 // Hide Others
	case showAll = 111 // Show All
	case showAllSeparator = 112
	case quit = 113 // Quit Glasstual
	case disableNotifications = 200 // Disable All Notifications
	case disableNotificationSounds = 201 // Disable All Notification Sounds
	case disableNotificationSoundsSeparator = 202
	case printLog = 203 // Print
	case printLogSeparator = 204
	case closeWindow = 205 // Close Window
	case undo = 300 // Undo
	case redo = 301 // Redo
	case redoSeparator = 302
	case cut = 303 // Cut
	case copy = 304 // Copy
	case paste = 305 // Paste
	case delete = 306 // Delete
	case selectAll = 307 // Select All
	case selectAllSeparator = 308
	case find = 309 // Find
	case markScrollback = 400 // Mark Scrollback
	case scrollbackMarker = 401 // Scrollback Marker
	case scrollbackMarkerSeparator = 402
	case markAllRead = 403 // Mark All As Read
	case clearScrollback = 404 // Clear Scrollback
	case clearScrollbackSeparator = 405
	case increaseFont = 406 // Increase Font Size
	case decreaseFont = 407 // Decrease Font Size
	case decreaseFontSeparator = 408
	case enterFullScreen = 409 // Enter Full Screen
	case connect = 500 // Connect
	case connectWithoutProxy = 501 // Connect Without Proxy
	case disconnect = 502 // Disconnect
	case cancelReconnect = 503 // Cancel Reconnect
	case cancelReconnectSeparator = 504
	case channelList = 505 // Channel List…
	case changeNickname = 506 // Change Nickname…
	case changeNicknameSeparator = 507
	case addServer = 508 // Add Server…
	case duplicateServer = 509 // Duplicate Server
	case deleteServer = 510 // Delete Server…
	case deleteServerSeparator = 511
	case addChannelToServer = 512 // Add Channel…
	case addChannelToServerSeparator = 513
	case serverProperties = 514 // Server Properties…
	case joinChannel = 600 // Join Channel
	case leaveChannel = 601 // Leave Channel
	case leaveChannelSeparator = 602
	case addChannel = 603 // Add Channel…
	case deleteChannel = 604 // Delete Channel
	case deleteChannelSeparator = 605
	case viewChannelLogs = 606 // View Logs
	case viewChannelLogsSeparator = 607
	case modifyTopic = 608 // Modify Topic
	case modes = 609 // Modes
	case modesSeparator = 610
	case bans = 611 // List of Bans
	case banExceptions = 612 // List of Ban Exceptions
	case inviteExceptions = 613 // List of Invite Exceptions
	case quiets = 614 // List of Quiets
	case quietsSeparator = 615
	case channelProperties = 616 // Channel Properties…
	case channelPropertiesSeparator = 617
	case copyChannelIdentifier = 618 // Copy Unique Identifier
	case navigationServers = 700 // Servers
	case navigationChannels = 701 // Channels
	case navigationChannelsSeparator = 702
	case moveBackward = 703 // Move Backward
	case moveForward = 704 // Move Forward
	case moveForwardSeparator = 705
	case previousSelection = 706 // Previous Selection
	case previousSelectionSeparator = 707
	case nextHighlight = 708 // Next Highlight
	case previousHighlight = 709 // Previous Highlight
	case previousHighlightSeparator = 710
	case jumpToCurrentSession = 711 // Jump to Current Session
	case jumpToPresent = 712 // Jump to Present
	case jumpToPresentSeparator = 713
	case navigationChannelList = 714 // Channel List…
	case navigationChannelListSeparator = 715
	case searchChannels = 716 // Search channels…
	case minimize = 800 // Minimize
	case zoom = 801 // Zoom
	case zoomSeparator = 802
	case toggleMemberList = 803 // Hide Member List
	case toggleServerList = 804 // Hide Server List
	case toggleAppearance = 805 // Toggle Window Appearance
	case toggleAppearanceSeparator = 806
	case sortChannelList = 807 // Sort Channel List
	case sortChannelListSeparator = 808
	case centerWindow = 809 // Center Window
	case resetWindow = 810 // Reset Window to Default Size
	case resetWindowSeparator = 811
	case mainWindow = 812 // Main Window
	case addressBook = 813 // Address Book
	case ignoreList = 814 // Ignore List
	case viewLogs = 815 // View Logs
	case highlightList = 816 // Highlight List
	case fileTransfers = 817 // File Transfers
	case fileTransfersSeparator = 818
	case bringAllToFront = 819 // Bring All to Front
	case acknowledgements = 900 // Acknowledgements
	case acknowledgementsSeparator = 906
	case connectToHelpChannel = 907 // Connect to Help Channel
	case connectToTestingChannel = 908 // Connect to Testing Channel
	case connectToTestingChannelSeparator = 909
	case advanced = 910 // Advanced
	case advancedSeparator = 911
	case welcome = 912 // Welcome to Glasstual…
	case channelNameJoinChannel = 1000 // Join Channel
	case copyLinkURL = 1100 // Copy URL
	case webChangeNickname = 1200 // Change Nickname…
	case webChangeNicknameSeparator = 1201
	case webSearch = 1202 // Search With Google
	case webDictionary = 1203 // Look Up in Dictionary
	case webDictionarySeparator = 1204
	case webCopy = 1205 // Copy
	case webPaste = 1206 // Paste
	case webPasteSeparator = 1207
	case webQueryLogs = 1208 // Query Logs
	case webChannelMenu = 1209 // Channel
	case segmentedAddServer = 1300 // Add Server…
	case segmentedAddServerSeparator = 1301
	case segmentedAddChannel = 1302 // Add Channel…
	case serverListAddServer = 1400 // Add Server…
	case addIgnore = 1600 // Add Ignore
	case modifyIgnore = 1601 // Modify Ignore
	case removeIgnore = 1602 // Remove Ignore
	case removeIgnoreSeparator = 1603
	case inviteTo = 1604 // Invite to…
	case inviteToSeparator = 1605
	case whois = 1606 // Get Info (Whois)
	case privateMessage = 1607 // Private Message (Query)
	case privateMessageSeparator = 1608
	case giveOp = 1609 // Give Op (+o)
	case giveHalfop = 1610 // Give Halfop (+h)
	case giveVoice = 1611 // Give Voice (+v)
	case allModesGiven = 1612 // All Modes Given
	case allModesGivenSeparator = 1613
	case takeOp = 1614 // Take Op (-o)
	case takeHalfop = 1615 // Take Halfop (-h)
	case takeVoice = 1616 // Take Voice (-v)
	case allModesTaken = 1617 // All Modes Taken
	case allModesTakenSeparator = 1618
	case ban = 1619 // Ban
	case kick = 1620 // Kick
	case kickban = 1621 // Ban and Kick
	case kickbanSeparator = 1622
	case ctcp = 1623 // Client-to-Client
	case ircOperator = 1624 // IRC Operator
	case changeColor = 1625 // Change Color…
	case dockDisableNotifications = 1700 // Disable All Notifications
	case dockDisableNotificationSounds = 1701 // Disable All Notification Sounds
	case closeQuery = 1800 // Close Query
	case closeQuerySeparator = 1801
	case queryLogs = 1802 // Query Logs
	case findText = 3_090_000 // Find…
	case findNext = 3_090_001 // Find Next
	case findPrevious = 3_090_002 // Find Previous
	case channelModeModerated = 6_090_000 // Moderated (+m)
	case channelModeUnmoderated = 6_090_001 // Unmoderated (-m)
	case channelModeInviteOnly = 6_090_002 // Invite Only (+i)
	case channelModeAnyoneCanJoin = 6_090_003 // Anyone Can Join (-i)
	case channelModeManageAll = 6_090_004 // Manage All Modes
	case nextServer = 7_000_000 // Next Server
	case previousServer = 7_000_001 // Previous Server
	case previousServerSeparator = 7_000_002
	case nextActiveServer = 7_000_003 // Next Active Server
	case previousActiveServer = 7_000_004 // Previous Active Server
	case nextChannel = 7_010_000 // Next Channel
	case previousChannel = 7_010_001 // Previous Channel
	case previousChannelSeparator = 7_010_002
	case nextActiveChannel = 7_010_003 // Next Active Channel
	case previousActiveChannel = 7_010_004 // Previous Active Channel
	case previousActiveChannelSeparator = 7_010_005
	case nextUnreadChannel = 7_010_006 // Next Unread Channel
	case previousUnreadChannel = 7_010_007 // Previous Unread Channel
	case developerMode = 9_100_000 // Enable Developer Mode
	case developerModeSeparator = 9_100_001
	case hiddenSettings = 9_100_002 // Hidden Settings…
	case hiddenSettingsSeparator = 9_100_003
	case exportPreferences = 9_100_004 // Export Preferences
	case importPreferences = 9_100_005 // Import Preferences
	case importPreferencesSeparator = 9_100_006
	case resetDontAskMeWarnings = 9_100_007 // Reset "Don't Ask Me" Warnings
	case ctcpSendFile = 16_230_000 // Send file…
	case ctcpSendFileSeparator = 16_230_001
	case ctcpPing = 16_230_002 // Lag (PING)
	case ctcpTime = 16_230_003 // Local Time (TIME)
	case ctcpTimeSeparator = 16_230_004
	case ctcpClientInfo = 16_230_005 // Client Information (CLIENTINFO)
	case ctcpVersion = 16_230_006 // Client Version (VERSION)
	case ctcpVersionSeparator = 16_230_007
	case ctcpFinger = 16_230_008 // User Information (FINGER)
	case ctcpUserInfo = 16_230_009 // User Information (USERINFO)
	case operatorSetVirtualHost = 16_240_000 // Set Virtual Host (vHost)
	case operatorSetVirtualHostSeparator = 16_240_001
	case operatorKill = 16_240_002 // Kill from Server
	case operatorShun = 16_240_003 // Shun on Server
	case operatorGline = 16_240_004 // Ban from Server (G:Line)

	// Built at runtime by `MenuPresentation.messageReplyItems`. They are not in
	// the nib but belong to the web context menu's tag band.
	case webReplySeparator = 1210
	case webReply = 1211
	case webReact = 1212
}

// MARK: - Validation grouping

public extension MenuCommand {
	/// Which command-specific validator owns a command. The previous code
	/// derived this from the tag's numeric band, so a tag filed in the wrong
	/// hundred silently got the wrong validator; the mapping is explicit here.
	enum ValidationGroup: Sendable {
		case general
		case server
		case channel
		case window
		case web
		case member
	}

	var validationGroup: ValidationGroup {
		switch self {
		case .connect, .connectWithoutProxy, .disconnect, .cancelReconnect,
		     .cancelReconnectSeparator, .channelList, .changeNickname,
		     .changeNicknameSeparator, .addServer, .duplicateServer, .deleteServer,
		     .deleteServerSeparator, .addChannelToServer, .addChannelToServerSeparator,
		     .serverProperties:
			.server
		case .joinChannel, .leaveChannel, .leaveChannelSeparator, .addChannel,
		     .deleteChannel, .deleteChannelSeparator, .viewChannelLogs,
		     .viewChannelLogsSeparator, .modifyTopic, .modes, .modesSeparator, .bans,
		     .banExceptions, .inviteExceptions, .quiets, .quietsSeparator,
		     .channelProperties, .channelPropertiesSeparator, .copyChannelIdentifier:
			.channel
		case .minimize, .zoom, .zoomSeparator, .toggleMemberList, .toggleServerList,
		     .toggleAppearance, .toggleAppearanceSeparator, .sortChannelList,
		     .sortChannelListSeparator, .centerWindow, .resetWindow,
		     .resetWindowSeparator, .mainWindow, .addressBook, .ignoreList, .viewLogs,
		     .highlightList, .fileTransfers, .fileTransfersSeparator, .bringAllToFront:
			.window
		case .webChangeNickname, .webChangeNicknameSeparator, .webSearch, .webDictionary,
		     .webDictionarySeparator, .webCopy, .webPaste, .webPasteSeparator,
		     .webQueryLogs, .webChannelMenu, .webReplySeparator, .webReply, .webReact:
			.web
		case .addIgnore, .modifyIgnore, .removeIgnore, .removeIgnoreSeparator, .inviteTo,
		     .inviteToSeparator, .whois, .privateMessage, .privateMessageSeparator,
		     .giveOp, .giveHalfop, .giveVoice, .allModesGiven, .allModesGivenSeparator,
		     .takeOp, .takeHalfop, .takeVoice, .allModesTaken, .allModesTakenSeparator,
		     .ban, .kick, .kickban, .kickbanSeparator, .ctcp, .ircOperator, .changeColor:
			.member
		default:
			.general
		}
	}

	/// Top-level menu bar titles. They are always enabled: disabling one hides
	/// every command beneath it.
	var isTopLevelMenu: Bool {
		switch self {
		case .applicationMenu, .fileMenu, .editMenu, .viewMenu, .serverMenu,
		     .channelMenu, .queryMenu, .navigationMenu, .windowMenu, .helpMenu:
			true
		default:
			false
		}
	}

	/// Commands that stay live while a sheet is attached to the main window.
	var isAvailableDuringSheets: Bool {
		switch self {
		case .about, .settings, .disableNotifications, .disableNotificationSounds,
		     .dockDisableNotifications, .dockDisableNotificationSounds, .developerMode,
		     .hiddenSettings:
			true
		default:
			false
		}
	}

	/// Commands that stay live even before the application finishes launching.
	var isEssential: Bool {
		switch self {
		case .about, .quit, .printLog, .closeWindow, .paste, .mainWindow,
		     .acknowledgements, .advanced, .welcome, .exportPreferences:
			true
		default:
			false
		}
	}
}

// MARK: - Menu symbols

public extension MenuCommand {
	/// The SF Symbol drawn next to the command, if it takes one.
	var symbolName: String? {
		Self.symbolNames[self]
	}

	internal static let symbolNames: [MenuCommand: String] = [
		.settings: "gear", .quit: "power", .disableNotifications: "bell.slash",
		.disableNotificationSounds: "speaker.slash", .printLog: "printer",
		.closeWindow: "xmark", .undo: "arrow.uturn.backward", .redo: "arrow.uturn.forward",
		.cut: "scissors", .copy: "doc.on.doc", .paste: "doc.on.clipboard",
		.delete: "trash", .selectAll: "selection.pin.in.out", .markScrollback: "bookmark",
		.markAllRead: "envelope.open", .clearScrollback: "eraser",
		.increaseFont: "textformat.size.larger", .decreaseFont: "textformat.size.smaller",
		.enterFullScreen: "arrow.up.left.and.arrow.down.right", .connect: "bolt",
		.connectWithoutProxy: "bolt.badge.clock", .disconnect: "bolt.slash",
		.cancelReconnect: "xmark.circle", .channelList: "list.bullet",
		.changeNickname: "pencil", .addServer: "plus",
		.duplicateServer: "plus.square.on.square", .deleteServer: "trash",
		.addChannelToServer: "plus.circle", .serverProperties: "slider.horizontal.3",
		.joinChannel: "arrow.right.square", .leaveChannel: "arrow.left.square",
		.addChannel: "plus.circle", .deleteChannel: "trash", .viewChannelLogs: "doc.text",
		.modifyTopic: "text.quote", .modes: "slider.horizontal.3", .bans: "hand.raised",
		.channelProperties: "gearshape", .jumpToPresent: "arrow.down.to.line",
		.searchChannels: "magnifyingglass", .minimize: "minus", .zoom: "plus.rectangle",
		.toggleMemberList: "person.2", .toggleServerList: "sidebar.left",
		.mainWindow: "macwindow", .addressBook: "person.crop.circle",
		.ignoreList: "hand.raised", .viewLogs: "doc.text",
		.highlightList: "exclamationmark.bubble",
		.fileTransfers: "arrow.up.arrow.down.circle",
		.acknowledgements: "info.circle", .connectToHelpChannel: "questionmark.circle",
		.welcome: "hand.wave", .channelNameJoinChannel: "arrow.right.square",
		.copyLinkURL: "link", .webChangeNickname: "pencil", .webSearch: "magnifyingglass",
		.webDictionary: "book", .webCopy: "doc.on.doc", .webPaste: "doc.on.clipboard",
		.webQueryLogs: "doc.text", .webChannelMenu: "number", .segmentedAddServer: "plus",
		.segmentedAddChannel: "plus.circle", .serverListAddServer: "plus",
		.addIgnore: "hand.raised", .modifyIgnore: "pencil",
		.removeIgnore: "hand.raised.slash", .inviteTo: "envelope", .whois: "info.circle",
		.privateMessage: "bubble.left", .ban: "nosign", .kick: "figure.walk",
		.kickban: "nosign", .ctcp: "arrow.left.arrow.right", .ircOperator: "shield",
		.dockDisableNotifications: "bell.slash",
		.dockDisableNotificationSounds: "speaker.slash", .closeQuery: "xmark",
		.queryLogs: "doc.text", .findText: "magnifyingglass",
	]
}

// MARK: - AppKit bridging

public extension NSMenuItem {
	/// The command this item issues, or `nil` for an item whose tag is not part
	/// of the application's command vocabulary (AppKit and WebKit both put their
	/// own tags on items we copy).
	var command: MenuCommand? {
		get { MenuCommand(rawValue: tag) }
		set { tag = newValue?.rawValue ?? 0 }
	}
}

public extension NSMenu {
	func item(for command: MenuCommand) -> NSMenuItem? {
		item(withTag: command.rawValue)
	}
}
