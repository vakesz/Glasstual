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

import Foundation

/// Titles for the menu graph `MenuFactory` builds, grouped by the menu each
/// one belongs to. A title two menus share is declared once, under the menu
/// it belongs to first.
nonisolated enum MenuStrings {} // nonisolated: value

// MARK: - MenuBar

extension MenuStrings {
	enum MenuBar {
		static var application: String {
			String(localized: .TVCMainWindow.menuBarApplication)
		}

		static var file: String {
			String(localized: .TVCMainWindow.menuBarFile)
		}

		static var edit: String {
			String(localized: .TVCMainWindow.menuBarEdit)
		}

		static var view: String {
			String(localized: .TVCMainWindow.menuBarView)
		}

		static var server: String {
			String(localized: .TVCMainWindow.menuBarServer)
		}

		static var channel: String {
			String(localized: .TVCMainWindow.menuBarChannel)
		}

		static var query: String {
			String(localized: .TVCMainWindow.menuBarQuery)
		}

		static var navigation: String {
			String(localized: .TVCMainWindow.menuBarNavigation)
		}

		static var window: String {
			String(localized: .TVCMainWindow.menuBarWindow)
		}

		static var help: String {
			String(localized: .TVCMainWindow.menuBarHelp)
		}
	}
}

// MARK: - Application

extension MenuStrings {
	enum Application {
		static var about: String {
			String(localized: .TVCMainWindow.menuApplicationAbout)
		}

		static var settings: String {
			String(localized: .TVCMainWindow.menuApplicationSettings)
		}

		static var services: String {
			String(localized: .TVCMainWindow.menuApplicationServices)
		}

		static var hide: String {
			String(localized: .TVCMainWindow.menuApplicationHide)
		}

		static var hideOthers: String {
			String(localized: .TVCMainWindow.menuApplicationHideOthers)
		}

		static var showAll: String {
			String(localized: .TVCMainWindow.menuApplicationShowAll)
		}

		static var quit: String {
			String(localized: .TVCMainWindow.menuApplicationQuit)
		}
	}
}

// MARK: - File

extension MenuStrings {
	enum File {
		static var disableNotifications: String {
			String(localized: .TVCMainWindow.menuFileDisableNotifications)
		}

		static var disableNotificationSounds: String {
			String(localized: .TVCMainWindow.menuFileDisableNotificationSounds)
		}

		static var print: String {
			String(localized: .TVCMainWindow.menuFilePrint)
		}

		static var closeWindow: String {
			String(localized: .TVCMainWindow.menuFileCloseWindow)
		}
	}
}

// MARK: - Edit

extension MenuStrings {
	enum Edit {
		static var undo: String {
			String(localized: .TVCMainWindow.menuEditUndo)
		}

		static var redo: String {
			String(localized: .TVCMainWindow.menuEditRedo)
		}

		static var cut: String {
			String(localized: .TVCMainWindow.menuEditCut)
		}

		static var copy: String {
			String(localized: .TVCMainWindow.menuEditCopy)
		}

		static var paste: String {
			String(localized: .TVCMainWindow.menuEditPaste)
		}

		static var delete: String {
			String(localized: .TVCMainWindow.menuEditDelete)
		}

		static var selectAll: String {
			String(localized: .TVCMainWindow.menuEditSelectAll)
		}

		static var find: String {
			String(localized: .TVCMainWindow.menuEditFind)
		}

		static var findText: String {
			String(localized: .TVCMainWindow.menuEditFindText)
		}

		static var findNext: String {
			String(localized: .TVCMainWindow.menuEditFindNext)
		}

		static var findPrevious: String {
			String(localized: .TVCMainWindow.menuEditFindPrevious)
		}
	}
}

// MARK: - View

extension MenuStrings {
	enum View {
		static var markScrollback: String {
			String(localized: .TVCMainWindow.menuViewMarkScrollback)
		}

		static var scrollbackMarker: String {
			String(localized: .TVCMainWindow.menuViewScrollbackMarker)
		}

		static var markAllAsRead: String {
			String(localized: .TVCMainWindow.menuViewMarkAllAsRead)
		}

		static var clearScrollback: String {
			String(localized: .TVCMainWindow.menuViewClearScrollback)
		}

		static var increaseFontSize: String {
			String(localized: .TVCMainWindow.menuViewIncreaseFontSize)
		}

		static var decreaseFontSize: String {
			String(localized: .TVCMainWindow.menuViewDecreaseFontSize)
		}

		static var enterFullScreen: String {
			String(localized: .TVCMainWindow.menuViewEnterFullScreen)
		}
	}
}

// MARK: - Server

extension MenuStrings {
	enum Server {
		static var connect: String {
			String(localized: .TVCMainWindow.menuServerConnect)
		}

		static var connectWithoutProxy: String {
			String(localized: .TVCMainWindow.menuServerConnectWithoutProxy)
		}

		static var disconnect: String {
			String(localized: .TVCMainWindow.menuServerDisconnect)
		}

		static var cancelReconnect: String {
			String(localized: .TVCMainWindow.menuServerCancelReconnect)
		}

		static var channelList: String {
			String(localized: .TVCMainWindow.menuServerChannelList)
		}

		static var changeNickname: String {
			String(localized: .TVCMainWindow.menuServerChangeNickname)
		}

		static var addServer: String {
			String(localized: .TVCMainWindow.menuServerAddServer)
		}

		static var duplicateServer: String {
			String(localized: .TVCMainWindow.menuServerDuplicateServer)
		}

		static var deleteServer: String {
			String(localized: .TVCMainWindow.menuServerDeleteServer)
		}

		static var addChannel: String {
			String(localized: .TVCMainWindow.menuServerAddChannel)
		}

		static var serverProperties: String {
			String(localized: .TVCMainWindow.menuServerProperties)
		}
	}
}

// MARK: - Channel

extension MenuStrings {
	enum Channel {
		static var joinChannel: String {
			String(localized: .TVCMainWindow.menuChannelJoin)
		}

		static var leaveChannel: String {
			String(localized: .TVCMainWindow.menuChannelLeave)
		}

		static var deleteChannel: String {
			String(localized: .TVCMainWindow.menuChannelDelete)
		}

		static var viewLogs: String {
			String(localized: .TVCMainWindow.menuChannelViewLogs)
		}

		static var modifyTopic: String {
			String(localized: .TVCMainWindow.menuChannelModifyTopic)
		}

		static var modes: String {
			String(localized: .TVCMainWindow.menuChannelModes)
		}

		static var modeModerated: String {
			String(localized: .TVCMainWindow.menuChannelModeModerated)
		}

		static var modeUnmoderated: String {
			String(localized: .TVCMainWindow.menuChannelModeUnmoderated)
		}

		static var modeInviteOnly: String {
			String(localized: .TVCMainWindow.menuChannelModeInviteOnly)
		}

		static var modeAnyoneCanJoin: String {
			String(localized: .TVCMainWindow.menuChannelModeAnyoneCanJoin)
		}

		static var modeManageAll: String {
			String(localized: .TVCMainWindow.menuChannelModeManageAll)
		}

		static var bans: String {
			String(localized: .TVCMainWindow.menuChannelBans)
		}

		static var banExceptions: String {
			String(localized: .TVCMainWindow.menuChannelBanExceptions)
		}

		static var inviteExceptions: String {
			String(localized: .TVCMainWindow.menuChannelInviteExceptions)
		}

		static var quiets: String {
			String(localized: .TVCMainWindow.menuChannelQuiets)
		}

		static var channelProperties: String {
			String(localized: .TVCMainWindow.menuChannelProperties)
		}

		static var copyUniqueIdentifier: String {
			String(localized: .TVCMainWindow.menuChannelCopyUniqueIdentifier)
		}
	}
}

// MARK: - Query

extension MenuStrings {
	enum Query {
		static var closeQuery: String {
			String(localized: .TVCMainWindow.menuQueryClose)
		}

		static var queryLogs: String {
			String(localized: .TVCMainWindow.menuQueryLogs)
		}
	}
}

// MARK: - Navigation

extension MenuStrings {
	enum Navigation {
		static var servers: String {
			String(localized: .TVCMainWindow.menuNavigationServers)
		}

		static var nextServer: String {
			String(localized: .TVCMainWindow.menuNavigationNextServer)
		}

		static var previousServer: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousServer)
		}

		static var nextActiveServer: String {
			String(localized: .TVCMainWindow.menuNavigationNextActiveServer)
		}

		static var previousActiveServer: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousActiveServer)
		}

		static var channels: String {
			String(localized: .TVCMainWindow.menuNavigationChannels)
		}

		static var nextChannel: String {
			String(localized: .TVCMainWindow.menuNavigationNextChannel)
		}

		static var previousChannel: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousChannel)
		}

		static var nextActiveChannel: String {
			String(localized: .TVCMainWindow.menuNavigationNextActiveChannel)
		}

		static var previousActiveChannel: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousActiveChannel)
		}

		static var nextUnreadChannel: String {
			String(localized: .TVCMainWindow.menuNavigationNextUnreadChannel)
		}

		static var previousUnreadChannel: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousUnreadChannel)
		}

		static var moveBackward: String {
			String(localized: .TVCMainWindow.menuNavigationMoveBackward)
		}

		static var moveForward: String {
			String(localized: .TVCMainWindow.menuNavigationMoveForward)
		}

		static var previousSelection: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousSelection)
		}

		static var nextHighlight: String {
			String(localized: .TVCMainWindow.menuNavigationNextHighlight)
		}

		static var previousHighlight: String {
			String(localized: .TVCMainWindow.menuNavigationPreviousHighlight)
		}

		static var jumpToCurrentSession: String {
			String(localized: .TVCMainWindow.menuNavigationJumpToCurrentSession)
		}

		static var jumpToPresent: String {
			String(localized: .TVCMainWindow.menuNavigationJumpToPresent)
		}

		static var channelList: String {
			String(localized: .TVCMainWindow.menuNavigationChannelList)
		}

		static var searchChannels: String {
			String(localized: .TVCMainWindow.menuNavigationSearchChannels)
		}

		static var channelSpotlight: String {
			String(localized: .TVCMainWindow.menuNavigationChannelSpotlight)
		}
	}
}

// MARK: - Window

extension MenuStrings {
	enum Window {
		static var minimize: String {
			String(localized: .TVCMainWindow.menuWindowMinimize)
		}

		static var zoom: String {
			String(localized: .TVCMainWindow.menuWindowZoom)
		}

		static var toggleAppearance: String {
			String(localized: .TVCMainWindow.menuWindowToggleAppearance)
		}

		static var sortChannelList: String {
			String(localized: .TVCMainWindow.menuWindowSortChannelList)
		}

		static var centerWindow: String {
			String(localized: .TVCMainWindow.menuWindowCenter)
		}

		static var resetWindow: String {
			String(localized: .TVCMainWindow.menuWindowResetSize)
		}

		static var mainWindow: String {
			String(localized: .TVCMainWindow.menuWindowMainWindow)
		}

		static var addressBook: String {
			String(localized: .TVCMainWindow.menuWindowAddressBook)
		}

		static var ignoreList: String {
			String(localized: .TVCMainWindow.menuWindowIgnoreList)
		}

		static var viewLogs: String {
			String(localized: .TVCMainWindow.menuWindowViewLogs)
		}

		static var highlightList: String {
			String(localized: .TVCMainWindow.menuWindowHighlightList)
		}

		static var fileTransfers: String {
			String(localized: .TVCMainWindow.menuWindowFileTransfers)
		}

		static var bringAllToFront: String {
			String(localized: .TVCMainWindow.menuWindowBringAllToFront)
		}
	}
}

// MARK: - Help

extension MenuStrings {
	enum Help {
		static var acknowledgements: String {
			String(localized: .TVCMainWindow.menuHelpAcknowledgements)
		}

		static var connectToHelpChannel: String {
			String(localized: .TVCMainWindow.menuHelpConnectToHelpChannel)
		}

		static var connectToTestingChannel: String {
			String(localized: .TVCMainWindow.menuHelpConnectToTestingChannel)
		}

		static var advanced: String {
			String(localized: .TVCMainWindow.menuHelpAdvanced)
		}

		static var developerMode: String {
			String(localized: .TVCMainWindow.menuHelpDeveloperMode)
		}

		static var hiddenSettings: String {
			String(localized: .TVCMainWindow.menuHelpHiddenSettings)
		}

		static var exportPreferences: String {
			String(localized: .TVCMainWindow.menuHelpExportPreferences)
		}

		static var importPreferences: String {
			String(localized: .TVCMainWindow.menuHelpImportPreferences)
		}

		static var resetDontAskMeWarnings: String {
			String(localized: .TVCMainWindow.menuHelpResetWarnings)
		}

		static var welcome: String {
			String(localized: .TVCMainWindow.menuHelpWelcome)
		}
	}
}

// MARK: - Transcript

extension MenuStrings {
	enum Transcript {
		static var searchWithProvider: String {
			String(localized: .TVCMainWindow.menuTranscriptSearchWithGoogle)
		}

		static var lookUpInDictionary: String {
			String(localized: .TVCMainWindow.menuTranscriptLookUpInDictionary)
		}

		static var copyURL: String {
			String(localized: .TVCMainWindow.menuTranscriptCopyUrl)
		}
	}
}

// MARK: - Member

extension MenuStrings {
	enum Member {
		static var addIgnore: String {
			String(localized: .TVCMainWindow.menuMemberAddIgnore)
		}

		static var modifyIgnore: String {
			String(localized: .TVCMainWindow.menuMemberModifyIgnore)
		}

		static var removeIgnore: String {
			String(localized: .TVCMainWindow.menuMemberRemoveIgnore)
		}

		static var inviteTo: String {
			String(localized: .TVCMainWindow.menuMemberInviteTo)
		}

		static var whois: String {
			String(localized: .TVCMainWindow.menuMemberWhois)
		}

		static var privateMessage: String {
			String(localized: .TVCMainWindow.menuMemberPrivateMessage)
		}

		static var giveOp: String {
			String(localized: .TVCMainWindow.menuMemberGiveOp)
		}

		static var giveHalfop: String {
			String(localized: .TVCMainWindow.menuMemberGiveHalfop)
		}

		static var giveVoice: String {
			String(localized: .TVCMainWindow.menuMemberGiveVoice)
		}

		static var allModesGiven: String {
			String(localized: .TVCMainWindow.menuMemberAllModesGiven)
		}

		static var takeOp: String {
			String(localized: .TVCMainWindow.menuMemberTakeOp)
		}

		static var takeHalfop: String {
			String(localized: .TVCMainWindow.menuMemberTakeHalfop)
		}

		static var takeVoice: String {
			String(localized: .TVCMainWindow.menuMemberTakeVoice)
		}

		static var allModesTaken: String {
			String(localized: .TVCMainWindow.menuMemberAllModesTaken)
		}

		static var ban: String {
			String(localized: .TVCMainWindow.menuMemberBan)
		}

		static var kick: String {
			String(localized: .TVCMainWindow.menuMemberKick)
		}

		static var kickban: String {
			String(localized: .TVCMainWindow.menuMemberKickban)
		}

		static var ctcp: String {
			String(localized: .TVCMainWindow.menuMemberCtcp)
		}

		static var sendFile: String {
			String(localized: .TVCMainWindow.menuMemberSendFile)
		}

		static var ctcpPing: String {
			String(localized: .TVCMainWindow.menuMemberCtcpPing)
		}

		static var ctcpTime: String {
			String(localized: .TVCMainWindow.menuMemberCtcpTime)
		}

		static var ctcpClientInfo: String {
			String(localized: .TVCMainWindow.menuMemberCtcpClientInfo)
		}

		static var ctcpVersion: String {
			String(localized: .TVCMainWindow.menuMemberCtcpVersion)
		}

		static var ctcpFinger: String {
			String(localized: .TVCMainWindow.menuMemberCtcpFinger)
		}

		static var ctcpUserInfo: String {
			String(localized: .TVCMainWindow.menuMemberCtcpUserInfo)
		}

		static var ircOperator: String {
			String(localized: .TVCMainWindow.menuMemberIrcOperator)
		}

		static var setVirtualHost: String {
			String(localized: .TVCMainWindow.menuMemberSetVirtualHost)
		}

		static var kill: String {
			String(localized: .TVCMainWindow.menuMemberKill)
		}

		static var shun: String {
			String(localized: .TVCMainWindow.menuMemberShun)
		}

		static var gline: String {
			String(localized: .TVCMainWindow.menuMemberGline)
		}

		static var changeColor: String {
			String(localized: .TVCMainWindow.menuMemberChangeColor)
		}
	}
}
