// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Every command the application's menus can issue.

 The case name is the identifier: it goes into `NSMenuItem.identifier`, which
 is a string namespace of the app's own. Nothing persists it, nothing dispatches
 on it, and it is not an AppKit tag -- the numeric bands it used to carry looked
 like tags, were filed by hand into hundreds, and let a command in the wrong
 band pick up the wrong validator.

 One command is one case, however many menus offer it: Copy in the transcript's
 menu and Copy in the Edit menu are the same command in two places, and the
 placement -- title, key equivalent, which menu it hangs in -- belongs to
 ``MenuGraph/Entry``, not to the identity. A second case per placement gave
 the same command two validators that had to be kept saying the same thing.

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
	case setUnreadMarker // Mark Scrollback
	case gotoUnreadMarker // Scrollback Marker
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
	case toggleSidebar // Hide Server List
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
	case webSearch // Search With %@
	case transcriptDictionary // Look Up in Dictionary
	case transcriptChannelMenu // Channel
	case addIgnore // Add Ignore…
	case modifyIgnore // Modify Ignore…
	case removeIgnore // Remove Ignore
	case inviteTo // Invite to…
	case whois // Get Info (Whois)
	case startDirectConversation // Private Message (Query)
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
	case transcriptReply
	case transcriptReact
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
		case transcript
		case member
	}

	var validationGroup: ValidationGroup {
		switch self {
		case .connect, .connectWithoutProxy, .disconnect, .cancelReconnect,
		     .channelList, .changeNickname, .addServer, .duplicateServer,
		     .deleteServer, .serverProperties:
			.server
		case .joinChannel, .leaveChannel, .addChannel, .deleteChannel,
		     .viewChannelLogs, .modifyTopic, .modes, .channelModeModerated,
		     .channelModeInviteOnly, .channelModeManageAll, .bans, .banExceptions,
		     .inviteExceptions, .quiets, .channelProperties, .copyChannelIdentifier:
			.channel
		case .minimize, .zoom, .toggleMemberList, .toggleSidebar,
		     .appearanceSystem, .appearanceLight, .appearanceDark, .sortChannelList,
		     .centerWindow, .resetWindow, .mainWindow, .addressBook, .viewLogs,
		     .highlightList, .fileTransfers, .bringAllToFront:
			.window
		case .webSearch, .transcriptDictionary, .transcriptChannelMenu,
		     .transcriptReply, .transcriptReact:
			.transcript
		case .addIgnore, .modifyIgnore, .removeIgnore, .inviteTo, .whois,
		     .startDirectConversation, .giveOp, .giveHalfop, .giveVoice, .takeOp, .takeHalfop,
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
	///
	/// The list is the menu bar's own table, read through
	/// ``MenuGraph/topLevelCommands``: restating it here meant a menu added to
	/// the bar was a top-level menu in one file and an ordinary command in the
	/// other.
	var isTopLevelMenu: Bool {
		MenuGraph.topLevelCommands.contains(self)
	}

	/// Commands that stay live while a sheet is attached to the main window.
	var isAvailableDuringSheets: Bool {
		switch self {
		case .about, .settings, .muteNotifications, .muteNotificationSounds,
		     .developerMode, .hiddenSettings:
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
	/// Copy and Quit reads as decoration rather than as meaning. A command that
	/// hangs in both -- Copy, Paste, Mute Notifications -- carries its symbol
	/// here and is drawn with it only where ``MenuPresentation/apply(to:)``
	/// runs, which is never the menu bar.
	var symbolName: String? {
		Self.symbolNames[self]
	}

	static let symbolNames: [MenuCommand: String] = [
		.copy: "doc.on.doc", .paste: "doc.on.clipboard",
		.muteNotifications: "bell.slash", .muteNotificationSounds: "speaker.slash",
		.connect: "bolt", .connectWithoutProxy: "bolt.badge.clock",
		.disconnect: "bolt.slash", .cancelReconnect: "xmark.circle",
		.channelList: "list.bullet", .changeNickname: "pencil",
		.addServer: "plus", .duplicateServer: "plus.square.on.square",
		.deleteServer: "trash", .serverProperties: "slider.horizontal.3",
		.joinChannel: "arrow.right.square", .leaveChannel: "arrow.left.square",
		.addChannel: "plus.circle", .deleteChannel: "trash",
		.viewChannelLogs: "doc.text", .modifyTopic: "text.quote",
		.modes: "slider.horizontal.3", .bans: "hand.raised",
		.channelProperties: "gearshape", .copyChannelIdentifier: "link",
		.closeQuery: "xmark", .queryLogs: "doc.text",
		.channelNameJoinChannel: "arrow.right.square", .copyLinkURL: "link",
		.webSearch: "magnifyingglass", .transcriptDictionary: "book",
		.transcriptChannelMenu: "number",
		.addIgnore: "hand.raised", .modifyIgnore: "pencil",
		.removeIgnore: "hand.raised.slash", .inviteTo: "envelope",
		.whois: "info.circle", .startDirectConversation: "bubble.left",
		.ban: "nosign", .kick: "person.fill.xmark", .kickban: "nosign",
		.ctcp: "arrow.left.arrow.right", .ircOperator: "shield",
		.changeColor: "paintpalette",
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
	static func sidebarTitle(isVisible: Bool) -> String {
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
