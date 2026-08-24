/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

@MainActor
public extension TPCPreferences {
	@objc(performReloadActionForKeys:)
	class func performReloadAction(forKeys keys: [String]) {
		var reloadAction: TPCPreferencesReloadAction = []

		if keys.contains(where: styleReloadKeys.contains) {
			reloadAction.insert(.style)
		}

		if keys.contains("Highlight List -> Excluded Matches")
			|| keys.contains("Highlight List -> Primary Matches")
		{
			reloadAction.insert(.highlightKeywords)
		}

		if keys.contains("LogHighlights") {
			reloadAction.insert(.highlightLogging)
		}

		if keys.contains("RightToLeftTextFormatting") {
			reloadAction.insert(.textDirection)
		}

		if keys.contains("Main Input Text Field -> Font Size") {
			reloadAction.insert(.textFieldFontSize)
		}

		if keys.contains("SaveInputHistoryPerSelection") {
			reloadAction.insert(.inputHistoryScope)
		}

		if keys.contains("DisplayDockBadges") || keys.contains("DisplayPublicMessageCountInDockBadge") {
			reloadAction.insert(.dockIconBadges)
		}

		if keys.contains("Appearance") {
			reloadAction.insert(.appearance)
		}

		if keys.contains("MemberListSortFavorsServerStaff") {
			reloadAction.insert(.memberListSortOrder)
		}

		if keys.contains(where: memberListReloadKeys.contains) {
			reloadAction.insert(.memberList)
			reloadAction.insert(.memberListUserBadges)
		}

		if keys.contains("Server List Unread Message Count Badge Colors -> Highlight") {
			reloadAction.insert(.serverListUnreadBadges)
		}

		if keys.contains("GlasstualDeveloperEnvironment") {
			reloadAction.insert(.ircCommandCache)
		}

		if keys.contains("ScrollbackMaximumSavedLineCount") {
			reloadAction.insert(.scrollbackSaveLimit)
		}

		if keys.contains("ScrollbackMaximumVisibleLineCount") {
			reloadAction.insert(.scrollbackVisibleLimit)
		}

		if keys.contains("ChannelViewArrangement") {
			reloadAction.insert(.channelViewArrangement)
		}

		reloadAction.insert(.preferencesChanged)
		performReloadAction(reloadAction)
	}

	@objc(performReloadAction:)
	class func performReloadAction(_ reloadAction: TPCPreferencesReloadAction) {
		performReloadAction(reloadAction, forKey: nil)
	}

	@objc(performReloadAction:forKey:)
	class func performReloadAction(_ reloadAction: TPCPreferencesReloadAction, forKey key: String?) {
		let masterController = NSObject.masterController()
		let mainWindow = masterController.mainWindow!
		let memberList = mainWindow.memberList
		let serverList = mainWindow.serverList
		let inputTextField = mainWindow.inputTextField

		if reloadAction.contains(.dockIconBadges) {
			DockIcon.updateDockIcon()
		}

		var didReloadActiveStyle = false
		var didReloadUserInterface = false

		if reloadAction.contains(.memberListUserBadges) {
			if reloadAction == .memberListUserBadges, let key {
				memberList?.refreshDrawingForChanges(toPreference: key)
			} else {
				memberList?.refreshAllDrawings()
			}
		}

		if reloadAction.contains(.appearance) {
			TXSharedApplication.sharedAppearance().update()
			didReloadUserInterface = true
		}

		if reloadAction.contains(.style) {
			TXSharedApplication.sharedThemeController().reload()
			mainWindow.reloadTheme()
			didReloadActiveStyle = true
		}

		if reloadAction.contains(.serverList) {
			if didReloadUserInterface == false {
				serverList?.perform(Selector(("applicationAppearanceChanged")))
			}
		} else if reloadAction.contains(.serverListUnreadBadges) {
			if didReloadUserInterface == false {
				(serverList as ServerList?)?.refreshAllDrawings()
			}
		}

		if reloadAction.contains(.memberList) {
			if didReloadUserInterface == false {
				memberList?.applicationAppearanceChanged()
			}
		}

		var didReloadMemberListSortOrder = false

		if reloadAction.contains(.memberListSortOrder) {
			for client in masterController.world.clientList as? [IRCClient] ?? [] {
				for channel in client.channelList as? [IRCChannel] ?? [] {
					channel.sortMembers()
				}
			}

			didReloadMemberListSortOrder = true
		}

		if reloadAction.contains(.memberList) {
			if didReloadMemberListSortOrder == false {
				memberList?.refreshAllDrawings()
			}
		}

		if reloadAction.contains(.highlightKeywords) {
			cleanUpHighlightKeywords()
		}

		if reloadAction.contains(.highlightLogging) {
			if logHighlights() == false {
				for client in masterController.world.clientList as? [IRCClient] ?? [] {
					client.clearCachedHighlights()
				}
			}
		}

		if reloadAction.contains(.textDirection) {
			inputTextField?.updateTextDirection()

			if didReloadActiveStyle == false {
				mainWindow.reloadTheme()
			}
		}

		if reloadAction.contains(.textFieldFontSize) {
			inputTextField?.updateTextBasedOnPreferredFontSize()
		}

		if reloadAction.contains(.inputHistoryScope) {
			mainWindow.inputHistoryManager().noteObjectScopeDidChange()
		}

		if reloadAction.contains(.ircCommandCache) {
			IRCCommandIndex.invalidateCaches()
		}

		if reloadAction.contains(.logTranscripts) {
			for client in masterController.world.clientList as? [IRCClient] ?? [] {
				client.reopenLogFileIfNeeded()

				for channel in client.channelList as? [IRCChannel] ?? [] {
					channel.reopenLogFileIfNeeded()
				}
			}
		}

		if reloadAction.contains(.scrollbackSaveLimit) {
			TVCLogControllerHistoricLogFile.sharedInstance().resetMaximumLineCount()
		}

		if reloadAction.contains(.scrollbackVisibleLimit) {
			for client in masterController.world.clientList as? [IRCClient] ?? [] {
				client.viewController.changeScrollbackLimit()

				for channel in client.channelList as? [IRCChannel] ?? [] {
					channel.viewController.changeScrollbackLimit()
				}
			}
		}

		if reloadAction.contains(.channelViewArrangement) {
			mainWindow.updateChannelViewArrangement()
		}

		if reloadAction.contains(.preferencesChanged) {
			(masterController.world as AnyObject).perform(NSSelectorFromString("preferencesChanged"))
			(mainWindow as AnyObject).perform(NSSelectorFromString("preferencesChanged"))
		}
	}

	private class var styleReloadKeys: Set<String> {
		[
			"AutomaticallyFilterUnicodeTextSpam",
			"ConversationTrackingIncludesUserModeSymbol",
			"DisableRemoteNicknameColorHashing",
			"DisplayEventInLogView -> Date Changes",
			"DisplayEventInLogView -> Inline Media",
			"DisplayEventInLogView -> Join, Part, Quit",
			"Theme -> Nickname Format",
			"Theme -> Timestamp Format",
			"Theme -> Channel Font Preference Enabled",
			"Theme -> Nickname Format Preference Enabled",
			"Theme -> Timestamp Format Preference Enabled",
			TPCPreferencesThemeFontNameDefaultsKey,
			TPCPreferencesThemeFontSizeDefaultsKey,
			TPCPreferencesThemeNameDefaultsKey,
		]
	}

	private class var memberListReloadKeys: Set<String> {
		[
			"DisplayUserListNoModeSymbol",
			"User List Mode Badge Colors -> +y",
			"User List Mode Badge Colors -> +q",
			"User List Mode Badge Colors -> +a",
			"User List Mode Badge Colors -> +o",
			"User List Mode Badge Colors -> +h",
			"User List Mode Badge Colors -> +v",
			"User List Mode Badge Colors -> no mode",
		]
	}
}
