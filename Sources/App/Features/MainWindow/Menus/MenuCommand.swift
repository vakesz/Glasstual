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

/** Every command the application's menus can issue.

 The case name is the identifier: it goes into `NSMenuItem.identifier`, which
 is a string namespace of the app's own. Nothing persists it, nothing dispatches
 on it, and it is not an AppKit tag -- the numeric bands it used to carry looked
 like tags, were filed by hand into hundreds, and let a command in the wrong
 band pick up the wrong validator.

 Separators carry no command: nothing looks one up now that validation disables
 items instead of hiding them. */
enum MenuCommand: String, CaseIterable, Sendable {
	case applicationMenu // Glasstual
	case fileMenu // File
	case editMenu // Edit
	case formatMenu // Format
	case viewMenu // View
	case serverMenu // Server
	case channelMenu // Channel
	case queryMenu // Query
	case navigationMenu // Navigation
	case windowMenu // Window
	case helpMenu // Help
	case about // About Glasstual
	case settings // Settings…
	case services // Services
	case hideApplication // Hide Glasstual
	case hideOthers // Hide Others
	case showAll // Show All
	case quit // Quit Glasstual
	case muteNotifications // Mute Notifications
	case muteNotificationSounds // Mute Notification Sounds
	case printLog // Print…
	case importSettings // Import Settings…
	case exportSettings // Export Settings…
	case closeWindow // Close Window
	case undo // Undo
	case redo // Redo
	case cut // Cut
	case copy // Copy
	case paste // Paste
	case delete // Delete
	case selectAll // Select All
	case find // Find
	case markScrollback // Mark Scrollback
	case scrollbackMarker // Scrollback Marker
	case markAllRead // Mark All as Read
	case clearScrollback // Clear Scrollback
	case increaseFont // Increase Font Size
	case decreaseFont // Decrease Font Size
	case actualSize // Actual Size
	case enterFullScreen // Enter Full Screen
	case connect // Connect
	case connectWithoutProxy // Connect Without Proxy
	case disconnect // Disconnect
	case cancelReconnect // Cancel Reconnect
	case channelList // Channel List…
	case changeNickname // Change Nickname…
	case addServer // Add Server…
	case duplicateServer // Duplicate Server
	case deleteServer // Delete Server…
	case addChannelToServer // Add Channel…
	case serverProperties // Server Properties…
	case joinChannel // Join Channel
	case leaveChannel // Leave Channel
	case addChannel // Add Channel…
	case deleteChannel // Delete Channel…
	case viewChannelLogs // View Logs
	case modifyTopic // Modify Topic…
	case modes // Modes
	case bans // List of Bans…
	case banExceptions // List of Ban Exceptions…
	case inviteExceptions // List of Invite Exceptions…
	case quiets // List of Quiets…
	case channelProperties // Channel Properties…
	case copyChannelIdentifier // Copy Unique Identifier
	case navigationServers // Servers
	case navigationChannels // Channels
	case moveBackward // Move Backward
	case moveForward // Move Forward
	case previousSelection // Previous Selection
	case nextHighlight // Next Highlight
	case previousHighlight // Previous Highlight
	case jumpToCurrentSession // Jump to Current Session
	case jumpToPresent // Jump to Present
	case navigationChannelList // Channel List
	case searchChannels // Filter Sidebar
	case channelSpotlight // Channel Search…
	case minimize // Minimize
	case zoom // Zoom
	case toggleMemberList // Hide Member List
	case toggleServerList // Hide Server List
	case appearanceSystem // Match System
	case appearanceLight // Light
	case appearanceDark // Dark
	case sortChannelList // Sort Channel List
	case centerWindow // Center Window
	case resetWindow // Reset Window to Default Size
	case mainWindow // Main Window
	case addressBook // Address Book
	case viewLogs // View Logs
	case highlightList // Highlight List
	case fileTransfers // File Transfers
	case bringAllToFront // Bring All to Front
	case acknowledgements // Acknowledgements
	case connectToHelpChannel // Connect to Help Channel
	case connectToTestingChannel // Connect to Testing Channel
	case advanced // Advanced
	case welcome // Welcome to Glasstual…
	case channelNameJoinChannel // Join Channel
	case copyLinkURL // Copy URL
	case webChangeNickname // Change Nickname…
	case webSearch // Search With %@
	case webDictionary // Look Up in Dictionary
	case webCopy // Copy
	case webPaste // Paste
	case webQueryLogs // Query Logs
	case webChannelMenu // Channel
	case serverListAddServer // Add Server…
	case addIgnore // Add Ignore…
	case modifyIgnore // Modify Ignore…
	case removeIgnore // Remove Ignore
	case inviteTo // Invite to…
	case whois // Get Info (Whois)
	case privateMessage // Private Message (Query)
	case giveOp // Give Op (+o)
	case giveHalfop // Give Halfop (+h)
	case giveVoice // Give Voice (+v)
	case takeOp // Take Op (-o)
	case takeHalfop // Take Halfop (-h)
	case takeVoice // Take Voice (-v)
	case ban // Ban
	case kick // Kick
	case kickban // Ban and Kick
	case ctcp // Client-to-Client
	case ircOperator // IRC Operator
	case changeColor // Change Color…
	case dockMuteNotifications // Mute Notifications
	case dockMuteNotificationSounds // Mute Notification Sounds
	case closeQuery // Close Query
	case queryLogs // Query Logs
	case findText // Find…
	case findNext // Find Next
	case findPrevious // Find Previous
	case useSelectionForFind // Use Selection for Find
	case channelModeModerated // Moderated (+m)
	case channelModeInviteOnly // Invite Only (+i)
	case channelModeManageAll // Manage All Modes…
	case nextServer // Next Server
	case previousServer // Previous Server
	case nextActiveServer // Next Active Server
	case previousActiveServer // Previous Active Server
	case nextChannel // Next Channel
	case previousChannel // Previous Channel
	case nextActiveChannel // Next Active Channel
	case previousActiveChannel // Previous Active Channel
	case nextUnreadChannel // Next Unread Channel
	case previousUnreadChannel // Previous Unread Channel
	case developerMode // Developer Mode
	case hiddenSettings // Hidden Settings…
	case resetWarnings // Reset All Warnings
	case ctcpSendFile // Send File…
	case ctcpPing // Lag (PING)
	case ctcpTime // Local Time (TIME)
	case ctcpClientInfo // Client Information (CLIENTINFO)
	case ctcpVersion // Client Version (VERSION)
	case ctcpFinger // User Information (FINGER)
	case ctcpUserInfo // User Information (USERINFO)
	case operatorSetVirtualHost // Set Virtual Host (vHost)…
	case operatorKill // Kill from Server
	case operatorShun // Shun on Server
	case operatorGline // Ban from Server (G:Line)

	// Built at runtime by `MenuPresentation.messageReplyItems`. They are not in
	// the static graph but belong to the transcript menu's band.
	case webReply
	case webReact
}

// MARK: - Validation grouping

extension MenuCommand {
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

	/// Commands that stay live even before the application finishes launching:
	/// nothing about Settings, About or Welcome waits on the rest of launch.
	var isEssential: Bool {
		switch self {
		case .about, .settings, .quit, .printLog, .closeWindow, .paste, .mainWindow,
		     .acknowledgements, .advanced, .welcome, .exportSettings:
			true
		default:
			false
		}
	}
}

// MARK: - Menu symbols

extension MenuCommand {
	/// The SF Symbol drawn next to the command, if it takes one.
	///
	/// Contextual menus only. The menu bar is plain, because macOS draws no
	/// images beside its own commands, and a column of symbols next to Cut,
	/// Copy and Quit reads as decoration rather than as meaning.
	var symbolName: String? {
		Self.symbolNames[self]
	}

	static let symbolNames: [MenuCommand: String] = [
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
		.webChannelMenu: "number", .serverListAddServer: "plus",
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

extension NSMenuItem {
	private static let commandIdentifierPrefix = "com.vakesz.glasstual.command."

	/// The command this item issues. Programmatic menus store this in the item
	/// identifier so AppKit's numeric tag namespace remains available to controls
	/// and third-party menu items.
	var command: MenuCommand? {
		get {
			guard let value = identifier?.rawValue, value.hasPrefix(Self.commandIdentifierPrefix) else { return nil }
			return MenuCommand(rawValue: String(value.dropFirst(Self.commandIdentifierPrefix.count)))
		}
		set {
			identifier = newValue.map {
				NSUserInterfaceItemIdentifier(Self.commandIdentifierPrefix + $0.rawValue)
			}
		}
	}
}

extension NSMenu {
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

extension MenuCommand {
	/// The Window menu's server-list item names what the click will do, so its
	/// title flips with the sidebar's state.
	static func serverListTitle(isVisible: Bool) -> String {
		isVisible
			? String(localized: .MainWindow.hideServerList)
			: String(localized: .MainWindow.showServerList)
	}

	/// The same for the member list.
	static func memberListTitle(isVisible: Bool) -> String {
		isVisible
			? String(localized: .MainWindow.dynamicViewWindowMenuHideMemberList)
			: String(localized: .MainWindow.showMemberList)
	}
}
