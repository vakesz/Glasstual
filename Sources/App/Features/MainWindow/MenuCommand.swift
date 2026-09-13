/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

/// Every command the application's menus can issue. Raw values are stable
/// persistence-free identifiers used in `NSMenuItem.identifier`; they are not
/// AppKit tags and do not participate in responder-chain dispatch.
///
/// Separators carry no command: nothing looks one up now that validation
/// disables items instead of hiding them.
public enum MenuCommand: Int, CaseIterable, Sendable {
	case applicationMenu = 1 // Glasstual
	case fileMenu = 2 // File
	case editMenu = 3 // Edit
	case formatMenu = 11 // Format
	case viewMenu = 4 // View
	case serverMenu = 5 // Server
	case channelMenu = 6 // Channel
	case queryMenu = 7 // Query
	case navigationMenu = 8 // Navigation
	case windowMenu = 9 // Window
	case helpMenu = 10 // Help
	case about = 100 // About Glasstual
	case settings = 102 // Settings…
	case services = 107 // Services
	case hideApplication = 109 // Hide Glasstual
	case hideOthers = 110 // Hide Others
	case showAll = 111 // Show All
	case quit = 113 // Quit Glasstual
	case muteNotifications = 200 // Mute Notifications
	case muteNotificationSounds = 201 // Mute Notification Sounds
	case printLog = 203 // Print…
	case importSettings = 206 // Import Settings…
	case exportSettings = 207 // Export Settings…
	case closeWindow = 205 // Close Window
	case undo = 300 // Undo
	case redo = 301 // Redo
	case cut = 303 // Cut
	case copy = 304 // Copy
	case paste = 305 // Paste
	case delete = 306 // Delete
	case selectAll = 307 // Select All
	case find = 309 // Find
	case skipSpokenNotification = 310 // Skip Spoken Notification
	case markScrollback = 400 // Mark Scrollback
	case scrollbackMarker = 401 // Scrollback Marker
	case markAllRead = 403 // Mark All as Read
	case clearScrollback = 404 // Clear Scrollback
	case increaseFont = 406 // Increase Font Size
	case decreaseFont = 407 // Decrease Font Size
	case actualSize = 408 // Actual Size
	case enterFullScreen = 409 // Enter Full Screen
	case connect = 500 // Connect
	case connectWithoutProxy = 501 // Connect Without Proxy
	case disconnect = 502 // Disconnect
	case cancelReconnect = 503 // Cancel Reconnect
	case channelList = 505 // Channel List…
	case changeNickname = 506 // Change Nickname…
	case addServer = 508 // Add Server…
	case duplicateServer = 509 // Duplicate Server
	case deleteServer = 510 // Delete Server…
	case addChannelToServer = 512 // Add Channel…
	case serverProperties = 514 // Server Properties…
	case joinChannel = 600 // Join Channel
	case leaveChannel = 601 // Leave Channel
	case addChannel = 603 // Add Channel…
	case deleteChannel = 604 // Delete Channel…
	case viewChannelLogs = 606 // View Logs
	case modifyTopic = 608 // Modify Topic…
	case modes = 609 // Modes
	case bans = 611 // List of Bans…
	case banExceptions = 612 // List of Ban Exceptions…
	case inviteExceptions = 613 // List of Invite Exceptions…
	case quiets = 614 // List of Quiets…
	case channelProperties = 616 // Channel Properties…
	case copyChannelIdentifier = 618 // Copy Unique Identifier
	case navigationServers = 700 // Servers
	case navigationChannels = 701 // Channels
	case moveBackward = 703 // Move Backward
	case moveForward = 704 // Move Forward
	case previousSelection = 706 // Previous Selection
	case nextHighlight = 708 // Next Highlight
	case previousHighlight = 709 // Previous Highlight
	case jumpToCurrentSession = 711 // Jump to Current Session
	case jumpToPresent = 712 // Jump to Present
	case navigationChannelList = 714 // Channel List
	case searchChannels = 716 // Filter Sidebar
	case channelSpotlight = 717 // Channel Search…
	case minimize = 800 // Minimize
	case zoom = 801 // Zoom
	case toggleMemberList = 803 // Hide Member List
	case toggleServerList = 804 // Hide Server List
	case appearanceSystem = 805 // Match System
	case appearanceLight = 821 // Light
	case appearanceDark = 822 // Dark
	case sortChannelList = 807 // Sort Channel List
	case centerWindow = 809 // Center Window
	case resetWindow = 810 // Reset Window to Default Size
	case mainWindow = 812 // Main Window
	case addressBook = 813 // Address Book
	case viewLogs = 815 // View Logs
	case highlightList = 816 // Highlight List
	case fileTransfers = 817 // File Transfers
	case bringAllToFront = 819 // Bring All to Front
	case acknowledgements = 900 // Acknowledgements
	case connectToHelpChannel = 907 // Connect to Help Channel
	case connectToTestingChannel = 908 // Connect to Testing Channel
	case advanced = 910 // Advanced
	case welcome = 912 // Welcome to Glasstual…
	case channelNameJoinChannel = 1000 // Join Channel
	case copyLinkURL = 1100 // Copy URL
	case webChangeNickname = 1200 // Change Nickname…
	case webSearch = 1202 // Search With %@
	case webDictionary = 1203 // Look Up in Dictionary
	case webCopy = 1205 // Copy
	case webPaste = 1206 // Paste
	case webQueryLogs = 1208 // Query Logs
	case webChannelMenu = 1209 // Channel
	case segmentedAddServer = 1300 // Add Server…
	case segmentedAddChannel = 1302 // Add Channel…
	case serverListAddServer = 1400 // Add Server…
	case addIgnore = 1600 // Add Ignore…
	case modifyIgnore = 1601 // Modify Ignore…
	case removeIgnore = 1602 // Remove Ignore
	case inviteTo = 1604 // Invite to…
	case whois = 1606 // Get Info (Whois)
	case privateMessage = 1607 // Private Message (Query)
	case giveOp = 1609 // Give Op (+o)
	case giveHalfop = 1610 // Give Halfop (+h)
	case giveVoice = 1611 // Give Voice (+v)
	case takeOp = 1614 // Take Op (-o)
	case takeHalfop = 1615 // Take Halfop (-h)
	case takeVoice = 1616 // Take Voice (-v)
	case ban = 1619 // Ban
	case kick = 1620 // Kick
	case kickban = 1621 // Ban and Kick
	case ctcp = 1623 // Client-to-Client
	case ircOperator = 1624 // IRC Operator
	case changeColor = 1625 // Change Color…
	case dockMuteNotifications = 1700 // Mute Notifications
	case dockMuteNotificationSounds = 1701 // Mute Notification Sounds
	case closeQuery = 1800 // Close Query
	case queryLogs = 1802 // Query Logs
	case findText = 3_090_000 // Find…
	case findNext = 3_090_001 // Find Next
	case findPrevious = 3_090_002 // Find Previous
	case useSelectionForFind = 3_090_003 // Use Selection for Find
	case channelModeModerated = 6_090_000 // Moderated (+m)
	case channelModeInviteOnly = 6_090_002 // Invite Only (+i)
	case channelModeManageAll = 6_090_004 // Manage All Modes…
	case nextServer = 7_000_000 // Next Server
	case previousServer = 7_000_001 // Previous Server
	case nextActiveServer = 7_000_003 // Next Active Server
	case previousActiveServer = 7_000_004 // Previous Active Server
	case nextChannel = 7_010_000 // Next Channel
	case previousChannel = 7_010_001 // Previous Channel
	case nextActiveChannel = 7_010_003 // Next Active Channel
	case previousActiveChannel = 7_010_004 // Previous Active Channel
	case nextUnreadChannel = 7_010_006 // Next Unread Channel
	case previousUnreadChannel = 7_010_007 // Previous Unread Channel
	case developerMode = 9_100_000 // Developer Mode
	case hiddenSettings = 9_100_002 // Hidden Settings…
	case resetWarnings = 9_100_007 // Reset All Warnings
	case ctcpSendFile = 16_230_000 // Send File…
	case ctcpPing = 16_230_002 // Lag (PING)
	case ctcpTime = 16_230_003 // Local Time (TIME)
	case ctcpClientInfo = 16_230_005 // Client Information (CLIENTINFO)
	case ctcpVersion = 16_230_006 // Client Version (VERSION)
	case ctcpFinger = 16_230_008 // User Information (FINGER)
	case ctcpUserInfo = 16_230_009 // User Information (USERINFO)
	case operatorSetVirtualHost = 16_240_000 // Set Virtual Host (vHost)…
	case operatorKill = 16_240_002 // Kill from Server
	case operatorShun = 16_240_003 // Shun on Server
	case operatorGline = 16_240_004 // Ban from Server (G:Line)

	// Built at runtime by `MenuPresentation.messageReplyItems`. They are not in
	// the static graph but belong to the transcript menu's band.
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
		     .channelList, .changeNickname, .addServer, .duplicateServer,
		     .deleteServer, .addChannelToServer, .serverProperties:
			.server
		case .joinChannel, .leaveChannel, .addChannel, .deleteChannel,
		     .viewChannelLogs, .modifyTopic, .modes, .channelModeModerated,
		     .channelModeInviteOnly, .channelModeManageAll, .bans, .banExceptions,
		     .inviteExceptions, .quiets, .channelProperties, .copyChannelIdentifier:
			.channel
		case .minimize, .zoom, .toggleMemberList, .toggleServerList,
		     .appearanceSystem, .appearanceLight, .appearanceDark, .sortChannelList,
		     .centerWindow, .resetWindow, .mainWindow, .addressBook, .viewLogs,
		     .highlightList, .fileTransfers, .bringAllToFront:
			.window
		case .webChangeNickname, .webSearch, .webDictionary, .webCopy, .webPaste,
		     .webQueryLogs, .webChannelMenu, .webReply, .webReact:
			.web
		case .addIgnore, .modifyIgnore, .removeIgnore, .inviteTo, .whois,
		     .privateMessage, .giveOp, .giveHalfop, .giveVoice, .takeOp, .takeHalfop,
		     .takeVoice, .ban, .kick, .kickban, .ctcp, .ircOperator, .changeColor,
		     .ctcpSendFile, .ctcpPing, .ctcpTime, .ctcpClientInfo, .ctcpVersion,
		     .ctcpFinger, .ctcpUserInfo, .operatorSetVirtualHost, .operatorKill,
		     .operatorShun, .operatorGline:
			.member
		default:
			.general
		}
	}

	/// Top-level menu bar titles. They are always enabled: disabling one hides
	/// every command beneath it.
	var isTopLevelMenu: Bool {
		switch self {
		case .applicationMenu, .fileMenu, .editMenu, .formatMenu, .viewMenu,
		     .serverMenu, .channelMenu, .queryMenu, .navigationMenu, .windowMenu,
		     .helpMenu:
			true
		default:
			false
		}
	}

	/// Commands that stay live while a sheet is attached to the main window.
	var isAvailableDuringSheets: Bool {
		switch self {
		case .about, .settings, .muteNotifications, .muteNotificationSounds,
		     .dockMuteNotifications, .dockMuteNotificationSounds, .developerMode,
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
		     .acknowledgements, .advanced, .welcome, .exportSettings:
			true
		default:
			false
		}
	}
}

// MARK: - Menu symbols

public extension MenuCommand {
	/// The SF Symbol drawn next to the command, if it takes one.
	///
	/// Contextual menus only. The menu bar is plain: macOS draws no images
	/// beside its own commands, and a column of symbols next to Cut, Copy and
	/// Quit reads as decoration rather than as meaning.
	var symbolName: String? {
		Self.symbolNames[self]
	}

	internal static let symbolNames: [MenuCommand: String] = [
		.connect: "bolt", .connectWithoutProxy: "bolt.badge.clock",
		.disconnect: "bolt.slash", .cancelReconnect: "xmark.circle",
		.channelList: "list.bullet", .changeNickname: "pencil",
		.addServer: "plus", .duplicateServer: "plus.square.on.square",
		.deleteServer: "trash", .addChannelToServer: "plus.circle",
		.serverProperties: "slider.horizontal.3",
		.joinChannel: "arrow.right.square", .leaveChannel: "arrow.left.square",
		.addChannel: "plus.circle", .deleteChannel: "trash",
		.viewChannelLogs: "doc.text", .modifyTopic: "text.quote",
		.modes: "slider.horizontal.3", .bans: "hand.raised",
		.channelProperties: "gearshape", .copyChannelIdentifier: "link",
		.closeQuery: "xmark", .queryLogs: "doc.text",
		.channelNameJoinChannel: "arrow.right.square", .copyLinkURL: "link",
		.webChangeNickname: "pencil", .webSearch: "magnifyingglass",
		.webDictionary: "book", .webCopy: "doc.on.doc",
		.webPaste: "doc.on.clipboard", .webQueryLogs: "doc.text",
		.webChannelMenu: "number", .segmentedAddServer: "plus",
		.segmentedAddChannel: "plus.circle", .serverListAddServer: "plus",
		.addIgnore: "hand.raised", .modifyIgnore: "pencil",
		.removeIgnore: "hand.raised.slash", .inviteTo: "envelope",
		.whois: "info.circle", .privateMessage: "bubble.left",
		.ban: "nosign", .kick: "person.fill.xmark", .kickban: "nosign",
		.ctcp: "arrow.left.arrow.right", .ircOperator: "shield",
		.changeColor: "paintpalette",
		.dockMuteNotifications: "bell.slash",
		.dockMuteNotificationSounds: "speaker.slash",
	]
}

// MARK: - AppKit bridging

public extension NSMenuItem {
	/// The command this item issues. Programmatic menus store this in the item
	/// identifier so AppKit's numeric tag namespace remains available to controls
	/// and third-party menu items.
	var command: MenuCommand? {
		get {
			guard let value = identifier?.rawValue,
			      value.hasPrefix("com.vakesz.glasstual.command."),
			      let rawValue = Int(value.split(separator: ".").last ?? "")
			else { return nil }
			return MenuCommand(rawValue: rawValue)
		}
		set {
			identifier = newValue.map {
				NSUserInterfaceItemIdentifier("com.vakesz.glasstual.command.\($0.rawValue)")
			}
		}
	}
}

public extension NSMenu {
	func item(for command: MenuCommand) -> NSMenuItem? {
		for item in items {
			if item.command == command {
				return item
			}
			if let nested = item.submenu?.item(for: command) {
				return nested
			}
		}
		return nil
	}
}
