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

import Foundation
import os

private let preferencesReloadLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferencesReload"
)

public struct PreferencesReloadAction: OptionSet, Sendable {
	public let rawValue: UInt

	public init(rawValue: UInt) {
		self.rawValue = rawValue
	}

	public static let appearance = Self(rawValue: 1 << 0)
	public static let dockIconBadges = Self(rawValue: 1 << 2)
	public static let highlightKeywords = Self(rawValue: 1 << 3)
	public static let highlightLogging = Self(rawValue: 1 << 4)
	public static let ircCommandCache = Self(rawValue: 1 << 5)
	public static let inputHistoryScope = Self(rawValue: 1 << 6)
	public static let logTranscripts = Self(rawValue: 1 << 7)
	public static let memberList = Self(rawValue: 1 << 9)
	public static let memberListSortOrder = Self(rawValue: 1 << 10)
	public static let memberListUserBadges = Self(rawValue: 1 << 11)
	public static let preferencesChanged = Self(rawValue: 1 << 12)
	public static let scrollbackSaveLimit = Self(rawValue: 1 << 13)
	public static let scrollbackVisibleLimit = Self(rawValue: 1 << 14)
	public static let serverList = Self(rawValue: 1 << 15)
	public static let serverListUnreadBadges = Self(rawValue: 1 << 16)
	public static let style = Self(rawValue: 1 << 17)
	public static let textDirection = Self(rawValue: 1 << 19)
	public static let textFieldFontSize = Self(rawValue: 1 << 20)
}

@MainActor
public extension TextualPreferences {
	class func performReloadAction(forKeys keys: [String]) {
		performReloadAction(reloadAction(forKeys: keys))
	}

	/// The mapping is kept separate from performing it so it can be checked
	/// without a main window.
	class func reloadAction(forKeys keys: [String]) -> PreferencesReloadAction {
		var reloadAction: PreferencesReloadAction = []

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

		if keys.contains(Preferences.Badges.serverListUnreadHighlight.name) {
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

		if keys.contains("LogTranscript") {
			reloadAction.insert(.logTranscripts)
		}

		if keys.contains(IRCWorldClientListDefaultsKey) {
			reloadAction.insert(.serverList)
		}

		reloadAction.insert(.preferencesChanged)
		return reloadAction
	}

	class func performReloadAction(_ reloadAction: PreferencesReloadAction) {
		performReloadAction(reloadAction, forKey: nil)
	}

	class func performReloadAction(_ reloadAction: PreferencesReloadAction, forKey key: String?) {
		let didReloadActiveStyle = reloadInterface(for: reloadAction, changedKey: key)
		reloadMemberOrderingAndHighlights(for: reloadAction)
		reloadInputAndStorage(for: reloadAction, didReloadActiveStyle: didReloadActiveStyle)
		notifyPreferenceObservers(for: reloadAction)
	}

	private class func reloadInterface(
		for reloadAction: PreferencesReloadAction,
		changedKey key: String?
	) -> Bool {
		let appController: ApplicationController = AppController.shared
		// Reachable during preference import and during theme validation at
		// launch, both of which can run before the main window exists.
		guard let mainWindow = appController.mainWindow else {
			preferencesReloadLogger.debug("No main window to reload the interface of")
			return false
		}
		let memberList = mainWindow.memberList
		let serverList = mainWindow.serverList

		if reloadAction.contains(.dockIconBadges) {
			DockIcon.updateDockIcon()
		}

		var didReloadActiveStyle = false
		var didReloadUserInterface = false

		if reloadAction.contains(.memberListUserBadges) {
			if reloadAction == .memberListUserBadges, let key {
				memberList?.refreshDrawing(forChangesToPreference: key)
			} else {
				memberList?.refreshAllDrawings()
			}
		}

		if reloadAction.contains(.appearance) {
			SharedApplication.sharedAppearance().updateAppearance()
			didReloadUserInterface = true
		}

		if reloadAction.contains(.style) {
			SharedApplication.sharedThemeController().reload()
			mainWindow.reloadTheme()
			didReloadActiveStyle = true
		}

		if reloadAction.contains(.serverList) {
			if didReloadUserInterface == false {
				serverList?.applicationAppearanceChanged()
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

		return didReloadActiveStyle
	}

	private class func reloadMemberOrderingAndHighlights(for reloadAction: PreferencesReloadAction) {
		let appController: ApplicationController = AppController.shared
		let memberList = appController.mainWindow?.memberList

		var didReloadMemberListSortOrder = false

		if reloadAction.contains(.memberListSortOrder) {
			for client in appController.world.clientList {
				for channel in client.channelList {
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
				for client in appController.world.clientList {
					client.clearCachedHighlights()
				}
			}
		}
	}

	private class func reloadInputAndStorage(
		for reloadAction: PreferencesReloadAction,
		didReloadActiveStyle: Bool
	) {
		let appController: ApplicationController = AppController.shared
		guard let mainWindow = appController.mainWindow else {
			preferencesReloadLogger.debug("No main window to reload input and storage for")
			return
		}
		let inputTextField = mainWindow.inputTextField

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
			mainWindow.inputHistoryManager().noteInputHistoryObjectScopeDidChange()
		}

		if reloadAction.contains(.ircCommandCache) {
			CommandIndex.invalidateCaches()
		}

		if reloadAction.contains(.logTranscripts) {
			for client in appController.world.clientList {
				client.reopenLogFileIfNeeded()

				for channel in client.channelList {
					channel.reopenLogFileIfNeeded()
				}
			}
		}

		if reloadAction.contains(.scrollbackSaveLimit) {
			LogControllerHistoricLogFile.shared().resetMaximumLineCount()
		}

		if reloadAction.contains(.scrollbackVisibleLimit) {
			for client in appController.world.clientList {
				client.logController?.changeScrollbackLimit()

				for channel in client.channelList {
					channel.logController?.changeScrollbackLimit()
				}
			}
		}
	}

	private class func notifyPreferenceObservers(for reloadAction: PreferencesReloadAction) {
		if reloadAction.contains(.preferencesChanged) {
			let appController: ApplicationController = AppController.shared
			guard let mainWindow = appController.mainWindow else { return }

			appController.world.preferencesChanged()
			mainWindow.preferencesChanged()
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
		Set(UserListModeBadge.allCases.map(\.preferenceKey.name))
			.union([Preferences.Appearance.memberListNoModeSymbol.name])
	}
}
