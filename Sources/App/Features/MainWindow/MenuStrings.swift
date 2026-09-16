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
			String(localized: .MainWindow.menuBarApplication)
		}

		static var file: String {
			String(localized: .MainWindow.menuBarFile)
		}

		static var edit: String {
			String(localized: .MainWindow.menuBarEdit)
		}

		static var format: String {
			String(localized: .MainWindow.menuBarFormat)
		}

		static var view: String {
			String(localized: .MainWindow.menuBarView)
		}

		static var server: String {
			String(localized: .MainWindow.menuBarServer)
		}

		static var channel: String {
			String(localized: .MainWindow.menuBarChannel)
		}

		static var query: String {
			String(localized: .MainWindow.menuBarQuery)
		}

		static var navigation: String {
			String(localized: .MainWindow.menuBarNavigation)
		}

		static var window: String {
			String(localized: .MainWindow.menuBarWindow)
		}

		static var help: String {
			String(localized: .MainWindow.menuBarHelp)
		}
	}
}

// MARK: - Application

extension MenuStrings {
	enum Application {
		static var about: String {
			String(localized: .MainWindow.menuApplicationAbout)
		}

		static var settings: String {
			String(localized: .MainWindow.menuApplicationSettings)
		}

		static var services: String {
			String(localized: .MainWindow.menuApplicationServices)
		}

		static var hide: String {
			String(localized: .MainWindow.menuApplicationHide)
		}

		static var hideOthers: String {
			String(localized: .MainWindow.menuApplicationHideOthers)
		}

		static var showAll: String {
			String(localized: .MainWindow.menuApplicationShowAll)
		}

		static var quit: String {
			String(localized: .MainWindow.menuApplicationQuit)
		}
	}
}

// MARK: - File

extension MenuStrings {
	enum File {
		static var importSettings: String {
			String(localized: .MainWindow.menuFileImportSettings)
		}

		static var exportSettings: String {
			String(localized: .MainWindow.menuFileExportSettings)
		}

		static var print: String {
			String(localized: .MainWindow.menuFilePrint)
		}

		static var closeWindow: String {
			String(localized: .MainWindow.menuFileCloseWindow)
		}
	}
}

// MARK: - Notifications

extension MenuStrings {
	/// The two application-wide mute toggles, which the application menu and
	/// the Dock menu both offer.
	enum Notifications {
		static var muteNotifications: String {
			String(localized: .MainWindow.menuMuteNotifications)
		}

		static var muteNotificationSounds: String {
			String(localized: .MainWindow.menuMuteNotificationSounds)
		}
	}
}

// MARK: - Edit

extension MenuStrings {
	enum Edit {
		static var undo: String {
			String(localized: .MainWindow.menuEditUndo)
		}

		static var redo: String {
			String(localized: .MainWindow.menuEditRedo)
		}

		static var cut: String {
			String(localized: .MainWindow.menuEditCut)
		}

		static var copy: String {
			String(localized: .MainWindow.menuEditCopy)
		}

		static var paste: String {
			String(localized: .MainWindow.menuEditPaste)
		}

		static var delete: String {
			String(localized: .MainWindow.menuEditDelete)
		}

		static var selectAll: String {
			String(localized: .MainWindow.menuEditSelectAll)
		}

		static var useSelectionForFind: String {
			String(localized: .MainWindow.menuEditUseSelectionForFind)
		}

		static var pasteAndMatchStyle: String {
			String(localized: .MainWindow.menuEditPasteAndMatchStyle)
		}

		static var spellingAndGrammar: String {
			String(localized: .MainWindow.menuEditSpellingAndGrammar)
		}

		static var showSpellingAndGrammar: String {
			String(localized: .MainWindow.menuEditShowSpellingAndGrammar)
		}

		static var checkDocumentNow: String {
			String(localized: .MainWindow.menuEditCheckDocumentNow)
		}

		static var checkSpellingWhileTyping: String {
			String(localized: .MainWindow.menuEditCheckSpellingWhileTyping)
		}

		static var checkGrammarWithSpelling: String {
			String(localized: .MainWindow.menuEditCheckGrammarWithSpelling)
		}

		static var correctSpellingAutomatically: String {
			String(localized: .MainWindow.menuEditCorrectSpellingAutomatically)
		}

		static var substitutions: String {
			String(localized: .MainWindow.menuEditSubstitutions)
		}

		static var showSubstitutions: String {
			String(localized: .MainWindow.menuEditShowSubstitutions)
		}

		static var smartCopyPaste: String {
			String(localized: .MainWindow.menuEditSmartCopyPaste)
		}

		static var smartQuotes: String {
			String(localized: .MainWindow.menuEditSmartQuotes)
		}

		static var smartDashes: String {
			String(localized: .MainWindow.menuEditSmartDashes)
		}

		static var smartLinks: String {
			String(localized: .MainWindow.menuEditSmartLinks)
		}

		static var dataDetectors: String {
			String(localized: .MainWindow.menuEditDataDetectors)
		}

		static var textReplacement: String {
			String(localized: .MainWindow.menuEditTextReplacement)
		}

		static var transformations: String {
			String(localized: .MainWindow.menuEditTransformations)
		}

		static var makeUpperCase: String {
			String(localized: .MainWindow.menuEditMakeUpperCase)
		}

		static var makeLowerCase: String {
			String(localized: .MainWindow.menuEditMakeLowerCase)
		}

		static var capitalize: String {
			String(localized: .MainWindow.menuEditCapitalize)
		}

		static var speech: String {
			String(localized: .MainWindow.menuEditSpeech)
		}

		static var startSpeaking: String {
			String(localized: .MainWindow.menuEditStartSpeaking)
		}

		static var stopSpeaking: String {
			String(localized: .MainWindow.menuEditStopSpeaking)
		}

		static var skipSpokenNotification: String {
			String(localized: .MainWindow.menuEditSkipSpokenNotification)
		}

		static var find: String {
			String(localized: .MainWindow.menuEditFind)
		}

		static var findText: String {
			String(localized: .MainWindow.menuEditFindText)
		}

		static var findNext: String {
			String(localized: .MainWindow.menuEditFindNext)
		}

		static var findPrevious: String {
			String(localized: .MainWindow.menuEditFindPrevious)
		}
	}
}

// MARK: - View

extension MenuStrings {
	enum View {
		static var markScrollback: String {
			String(localized: .MainWindow.menuViewMarkScrollback)
		}

		static var scrollbackMarker: String {
			String(localized: .MainWindow.menuViewScrollbackMarker)
		}

		static var markAllAsRead: String {
			String(localized: .MainWindow.menuViewMarkAllAsRead)
		}

		static var clearScrollback: String {
			String(localized: .MainWindow.menuViewClearScrollback)
		}

		static var increaseFontSize: String {
			String(localized: .MainWindow.menuViewIncreaseFontSize)
		}

		static var decreaseFontSize: String {
			String(localized: .MainWindow.menuViewDecreaseFontSize)
		}

		static var actualSize: String {
			String(localized: .MainWindow.menuViewActualSize)
		}

		static var appearance: String {
			String(localized: .MainWindow.menuViewAppearance)
		}

		static var appearanceSystem: String {
			String(localized: .MainWindow.menuViewAppearanceSystem)
		}

		static var appearanceLight: String {
			String(localized: .MainWindow.menuViewAppearanceLight)
		}

		static var appearanceDark: String {
			String(localized: .MainWindow.menuViewAppearanceDark)
		}

		static var enterFullScreen: String {
			String(localized: .MainWindow.menuViewEnterFullScreen)
		}
	}
}

// MARK: - Server

extension MenuStrings {
	enum Server {
		static var connect: String {
			String(localized: .MainWindow.menuServerConnect)
		}

		static var connectWithoutProxy: String {
			String(localized: .MainWindow.menuServerConnectWithoutProxy)
		}

		static var disconnect: String {
			String(localized: .MainWindow.menuServerDisconnect)
		}

		static var cancelReconnect: String {
			String(localized: .MainWindow.menuServerCancelReconnect)
		}

		static var channelList: String {
			String(localized: .MainWindow.menuServerChannelList)
		}

		static var changeNickname: String {
			String(localized: .MainWindow.menuServerChangeNickname)
		}

		static var addServer: String {
			String(localized: .MainWindow.menuServerAddServer)
		}

		static var duplicateServer: String {
			String(localized: .MainWindow.menuServerDuplicateServer)
		}

		static var deleteServer: String {
			String(localized: .MainWindow.menuServerDeleteServer)
		}

		static var addChannel: String {
			String(localized: .MainWindow.menuServerAddChannel)
		}

		static var serverProperties: String {
			String(localized: .MainWindow.menuServerProperties)
		}
	}
}

// MARK: - Channel

extension MenuStrings {
	enum Channel {
		static var joinChannel: String {
			String(localized: .MainWindow.menuChannelJoin)
		}

		static var leaveChannel: String {
			String(localized: .MainWindow.menuChannelLeave)
		}

		static var deleteChannel: String {
			String(localized: .MainWindow.menuChannelDelete)
		}

		static var viewLogs: String {
			String(localized: .MainWindow.menuChannelViewLogs)
		}

		static var modifyTopic: String {
			String(localized: .MainWindow.menuChannelModifyTopic)
		}

		static var modes: String {
			String(localized: .MainWindow.menuChannelModes)
		}

		static var modeModerated: String {
			String(localized: .MainWindow.menuChannelModeModerated)
		}

		static var modeInviteOnly: String {
			String(localized: .MainWindow.menuChannelModeInviteOnly)
		}

		static var modeManageAll: String {
			String(localized: .MainWindow.menuChannelModeManageAll)
		}

		static var bans: String {
			String(localized: .MainWindow.menuChannelBans)
		}

		static var banExceptions: String {
			String(localized: .MainWindow.menuChannelBanExceptions)
		}

		static var inviteExceptions: String {
			String(localized: .MainWindow.menuChannelInviteExceptions)
		}

		static var quiets: String {
			String(localized: .MainWindow.menuChannelQuiets)
		}

		static var channelProperties: String {
			String(localized: .MainWindow.menuChannelProperties)
		}

		static var copyUniqueIdentifier: String {
			String(localized: .MainWindow.menuChannelCopyUniqueIdentifier)
		}
	}
}

// MARK: - Query

extension MenuStrings {
	enum Query {
		static var closeQuery: String {
			String(localized: .MainWindow.menuQueryClose)
		}

		static var queryLogs: String {
			String(localized: .MainWindow.menuQueryLogs)
		}
	}
}

// MARK: - Navigation

extension MenuStrings {
	enum Navigation {
		static var servers: String {
			String(localized: .MainWindow.menuNavigationServers)
		}

		static var nextServer: String {
			String(localized: .MainWindow.menuNavigationNextServer)
		}

		static var previousServer: String {
			String(localized: .MainWindow.menuNavigationPreviousServer)
		}

		static var nextActiveServer: String {
			String(localized: .MainWindow.menuNavigationNextActiveServer)
		}

		static var previousActiveServer: String {
			String(localized: .MainWindow.menuNavigationPreviousActiveServer)
		}

		static var channels: String {
			String(localized: .MainWindow.menuNavigationChannels)
		}

		static var nextChannel: String {
			String(localized: .MainWindow.menuNavigationNextChannel)
		}

		static var previousChannel: String {
			String(localized: .MainWindow.menuNavigationPreviousChannel)
		}

		static var nextActiveChannel: String {
			String(localized: .MainWindow.menuNavigationNextActiveChannel)
		}

		static var previousActiveChannel: String {
			String(localized: .MainWindow.menuNavigationPreviousActiveChannel)
		}

		static var nextUnreadChannel: String {
			String(localized: .MainWindow.menuNavigationNextUnreadChannel)
		}

		static var previousUnreadChannel: String {
			String(localized: .MainWindow.menuNavigationPreviousUnreadChannel)
		}

		static var moveBackward: String {
			String(localized: .MainWindow.menuNavigationMoveBackward)
		}

		static var moveForward: String {
			String(localized: .MainWindow.menuNavigationMoveForward)
		}

		static var previousSelection: String {
			String(localized: .MainWindow.menuNavigationPreviousSelection)
		}

		static var nextHighlight: String {
			String(localized: .MainWindow.menuNavigationNextHighlight)
		}

		static var previousHighlight: String {
			String(localized: .MainWindow.menuNavigationPreviousHighlight)
		}

		static var jumpToCurrentSession: String {
			String(localized: .MainWindow.menuNavigationJumpToCurrentSession)
		}

		static var jumpToPresent: String {
			String(localized: .MainWindow.menuNavigationJumpToPresent)
		}

		static var channelList: String {
			String(localized: .MainWindow.menuNavigationChannelList)
		}

		static var searchChannels: String {
			String(localized: .MainWindow.menuNavigationSearchChannels)
		}

		static var channelSpotlight: String {
			String(localized: .MainWindow.menuNavigationChannelSpotlight)
		}
	}
}

// MARK: - Window

extension MenuStrings {
	enum Window {
		static var minimize: String {
			String(localized: .MainWindow.menuWindowMinimize)
		}

		static var zoom: String {
			String(localized: .MainWindow.menuWindowZoom)
		}

		static var sortChannelList: String {
			String(localized: .MainWindow.menuWindowSortChannelList)
		}

		static var centerWindow: String {
			String(localized: .MainWindow.menuWindowCenter)
		}

		static var resetWindow: String {
			String(localized: .MainWindow.menuWindowResetSize)
		}

		static var mainWindow: String {
			String(localized: .MainWindow.menuWindowMainWindow)
		}

		static var addressBook: String {
			String(localized: .MainWindow.menuWindowAddressBook)
		}

		static var viewLogs: String {
			String(localized: .MainWindow.menuWindowViewLogs)
		}

		static var highlightList: String {
			String(localized: .MainWindow.menuWindowHighlightList)
		}

		static var fileTransfers: String {
			String(localized: .MainWindow.menuWindowFileTransfers)
		}

		static var bringAllToFront: String {
			String(localized: .MainWindow.menuWindowBringAllToFront)
		}
	}
}

// MARK: - Help

extension MenuStrings {
	enum Help {
		static var acknowledgements: String {
			String(localized: .MainWindow.menuHelpAcknowledgements)
		}

		static var connectToHelpChannel: String {
			String(localized: .MainWindow.menuHelpConnectToHelpChannel)
		}

		static var connectToTestingChannel: String {
			String(localized: .MainWindow.menuHelpConnectToTestingChannel)
		}

		static var advanced: String {
			String(localized: .MainWindow.menuHelpAdvanced)
		}

		static var developerMode: String {
			String(localized: .MainWindow.menuHelpDeveloperMode)
		}

		static var hiddenSettings: String {
			String(localized: .MainWindow.menuHelpHiddenSettings)
		}

		static var resetWarnings: String {
			String(localized: .MainWindow.menuHelpResetWarnings)
		}

		static var welcome: String {
			String(localized: .MainWindow.menuHelpWelcome)
		}
	}
}

// MARK: - Transcript

extension MenuStrings {
	enum Transcript {
		static var lookUpInDictionary: String {
			String(localized: .MainWindow.menuTranscriptLookUpInDictionary)
		}

		static var copyURL: String {
			String(localized: .MainWindow.menuTranscriptCopyUrl)
		}
	}
}

// MARK: - Member

extension MenuStrings {
	enum Member {
		static var addIgnore: String {
			String(localized: .MainWindow.menuMemberAddIgnore)
		}

		static var modifyIgnore: String {
			String(localized: .MainWindow.menuMemberModifyIgnore)
		}

		static var removeIgnore: String {
			String(localized: .MainWindow.menuMemberRemoveIgnore)
		}

		static var inviteTo: String {
			String(localized: .MainWindow.menuMemberInviteTo)
		}

		static var whois: String {
			String(localized: .MainWindow.menuMemberWhois)
		}

		static var privateMessage: String {
			String(localized: .MainWindow.menuMemberPrivateMessage)
		}

		static var giveOp: String {
			String(localized: .MainWindow.menuMemberGiveOp)
		}

		static var giveHalfop: String {
			String(localized: .MainWindow.menuMemberGiveHalfop)
		}

		static var giveVoice: String {
			String(localized: .MainWindow.menuMemberGiveVoice)
		}

		static var takeOp: String {
			String(localized: .MainWindow.menuMemberTakeOp)
		}

		static var takeHalfop: String {
			String(localized: .MainWindow.menuMemberTakeHalfop)
		}

		static var takeVoice: String {
			String(localized: .MainWindow.menuMemberTakeVoice)
		}

		static var ban: String {
			String(localized: .MainWindow.menuMemberBan)
		}

		static var kick: String {
			String(localized: .MainWindow.menuMemberKick)
		}

		static var kickban: String {
			String(localized: .MainWindow.menuMemberKickban)
		}

		static var ctcp: String {
			String(localized: .MainWindow.menuMemberCtcp)
		}

		static var sendFile: String {
			String(localized: .MainWindow.menuMemberSendFile)
		}

		static var ctcpPing: String {
			String(localized: .MainWindow.menuMemberCtcpPing)
		}

		static var ctcpTime: String {
			String(localized: .MainWindow.menuMemberCtcpTime)
		}

		static var ctcpClientInfo: String {
			String(localized: .MainWindow.menuMemberCtcpClientInfo)
		}

		static var ctcpVersion: String {
			String(localized: .MainWindow.menuMemberCtcpVersion)
		}

		static var ctcpFinger: String {
			String(localized: .MainWindow.menuMemberCtcpFinger)
		}

		static var ctcpUserInfo: String {
			String(localized: .MainWindow.menuMemberCtcpUserInfo)
		}

		static var ircOperator: String {
			String(localized: .MainWindow.menuMemberIrcOperator)
		}

		static var setVirtualHost: String {
			String(localized: .MainWindow.menuMemberSetVirtualHost)
		}

		static var kill: String {
			String(localized: .MainWindow.menuMemberKill)
		}

		static var shun: String {
			String(localized: .MainWindow.menuMemberShun)
		}

		static var gline: String {
			String(localized: .MainWindow.menuMemberGline)
		}

		static var changeColor: String {
			String(localized: .MainWindow.menuMemberChangeColor)
		}
	}
}
