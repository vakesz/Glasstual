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

private let preferenceReloadLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "PreferenceReload"
)

nonisolated struct PreferencesReloadAction: OptionSet, Sendable { // nonisolated: value
	let rawValue: UInt

	static let appearance = Self(rawValue: 1 << 0)
	static let dockIconBadges = Self(rawValue: 1 << 2)
	static let highlightKeywords = Self(rawValue: 1 << 3)
	static let highlightLogging = Self(rawValue: 1 << 4)
	static let inputHistoryScope = Self(rawValue: 1 << 6)
	static let logTranscripts = Self(rawValue: 1 << 7)
	static let memberList = Self(rawValue: 1 << 9)
	static let memberListSortOrder = Self(rawValue: 1 << 10)
	static let memberListUserBadges = Self(rawValue: 1 << 11)
	static let preferencesChanged = Self(rawValue: 1 << 12)
	static let scrollbackSaveLimit = Self(rawValue: 1 << 13)
	static let scrollbackVisibleLimit = Self(rawValue: 1 << 14)
	static let serverList = Self(rawValue: 1 << 15)
	static let serverListUnreadBadges = Self(rawValue: 1 << 16)
	static let style = Self(rawValue: 1 << 17)
	static let textDirection = Self(rawValue: 1 << 19)
	static let textFieldFontSize = Self(rawValue: 1 << 20)
}

/** What a changed preference makes the running application redo.

 A preference is read where it is used, so most changes need nothing. The ones
 that do are listed once, beside the key declaration each names, and a change to
 anything else carries only `preferencesChanged`. */
@MainActor
enum PreferenceReload {
	/// What a change to each key has to reload. A key that is not listed needs
	/// nothing beyond the notification every change carries.
	private static let actionsByKeyName: [String: PreferencesReloadAction] = {
		var actions: [String: PreferencesReloadAction] = [:]

		func reload(_ action: PreferencesReloadAction, on keys: [any AnyPreferenceKey]) {
			for key in keys {
				actions[key.name, default: []].formUnion(action)
			}
		}

		reload(.style, on: [
			Preferences.Theme.transcriptTheme,
			Preferences.Messages.filterUnicodeTextSpam,
			Preferences.Appearance.conversationTrackingIncludesModeSymbol,
			Preferences.Messages.disableNicknameColorHashing,
			Preferences.Messages.showDateChanges,
			Preferences.Messages.showInlineMedia,
			Preferences.Messages.showJoinLeave,
		])
		reload(.highlightKeywords, on: [
			Preferences.Highlights.matchKeywords,
			Preferences.Highlights.excludeKeywords,
		])
		reload(.highlightLogging, on: [Preferences.Logging.logHighlights])
		reload(.textDirection, on: [Preferences.Messages.rightToLeftFormatting])
		reload(.textFieldFontSize, on: [Preferences.Input.textViewFontSize])
		reload(.inputHistoryScope, on: [Preferences.Input.historyIsChannelSpecific])
		reload(.dockIconBadges, on: [
			Preferences.Notifications.displayDockBadge,
			Preferences.Notifications.publicMessageCountOnDockBadge,
		])
		reload(.appearance, on: [Preferences.Appearance.preferredAppearance])
		reload(.memberListSortOrder, on: [Preferences.Appearance.memberListSortFavorsServerStaff])
		reload([.memberList, .memberListUserBadges], on:
			UserListModeBadge.allCases.map(\.preferenceKey) + [Preferences.Appearance.memberListNoModeSymbol])
		reload(.serverListUnreadBadges, on: [Preferences.Badges.serverListUnreadHighlight])
		reload(.scrollbackSaveLimit, on: [Preferences.Logging.scrollbackSaveLimit])
		reload(.scrollbackVisibleLimit, on: [Preferences.Logging.scrollbackVisibleLimit])
		reload(.logTranscripts, on: [Preferences.Logging.logToDisk])
		reload(.serverList, on: [Preferences.Connection.clientList])

		return actions
	}()

	static func perform(forKeys keys: [String]) {
		perform(action(forKeys: keys))
	}

	/// The mapping is kept separate from performing it so it can be checked
	/// without a main window.
	static func action(forKeys keys: [String]) -> PreferencesReloadAction {
		var action: PreferencesReloadAction = .preferencesChanged

		for key in keys {
			action.formUnion(actionsByKeyName[key] ?? [])
		}

		return action
	}

	static func perform(_ reloadAction: PreferencesReloadAction) {
		perform(reloadAction, forKey: nil)
	}

	static func perform(_ reloadAction: PreferencesReloadAction, forKey key: String?) {
		let didReloadActiveStyle = reloadInterface(for: reloadAction, changedKey: key)
		reloadMemberOrderingAndHighlights(for: reloadAction)
		reloadInputAndStorage(for: reloadAction, didReloadActiveStyle: didReloadActiveStyle)
		notifyPreferenceObservers(for: reloadAction)
	}

	private static func reloadInterface(
		for reloadAction: PreferencesReloadAction,
		changedKey key: String?
	) -> Bool {
		let appController: ApplicationDelegate = AppServices.delegate
		// Reachable during preference import and during theme validation at
		// launch, both of which can run before the main window exists.
		guard let mainWindow = appController.mainWindow else {
			preferenceReloadLogger.debug("No main window to reload the interface of")
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
				memberList?.invalidatePresentation()
			}
		}

		if reloadAction.contains(.appearance) {
			AppServices.appearance.updateAppearance()
			/* Ahead of the redraws below: they resolve theme colours against the
			 snapshot the controller publishes, and the notification
			 `updateAppearance` posts would only reach it a turn later. */
			AppServices.theme.appearanceDidChange()
			didReloadUserInterface = true
		}

		if reloadAction.contains(.style) {
			AppServices.theme.reload()
			mainWindow.reloadTheme()
			didReloadActiveStyle = true
		}

		if reloadAction.contains(.serverList) {
			if didReloadUserInterface == false {
				serverList?.applicationAppearanceChanged()
			}
		} else if reloadAction.contains(.serverListUnreadBadges) {
			if didReloadUserInterface == false {
				serverList?.setNeedsRefresh()
			}
		}

		if reloadAction.contains(.memberList) {
			if didReloadUserInterface == false {
				memberList?.applicationAppearanceChanged()
			}
		}

		return didReloadActiveStyle
	}

	private static func reloadMemberOrderingAndHighlights(for reloadAction: PreferencesReloadAction) {
		let appController: ApplicationDelegate = AppServices.delegate
		let memberList = appController.mainWindow?.memberList

		var didReloadMemberListSortOrder = false

		if reloadAction.contains(.memberListSortOrder) {
			for client in appController.clientDirectory.clientList {
				for channel in client.channelList {
					channel.sortMembers()
				}
			}

			didReloadMemberListSortOrder = true
		}

		if reloadAction.contains(.memberList) {
			if didReloadMemberListSortOrder == false {
				memberList?.invalidatePresentation()
			}
		}

		if reloadAction.contains(.highlightKeywords) {
			Preferences.Highlights.cleanUpStoredKeywords()
		}

		if reloadAction.contains(.highlightLogging) {
			if Preferences.Logging.logHighlights.value == false {
				for client in appController.clientDirectory.clientList {
					client.clearCachedHighlights()
				}
			}
		}
	}

	private static func reloadInputAndStorage(
		for reloadAction: PreferencesReloadAction,
		didReloadActiveStyle: Bool
	) {
		let appController: ApplicationDelegate = AppServices.delegate
		guard let mainWindow = appController.mainWindow else {
			preferenceReloadLogger.debug("No main window to reload input and storage for")
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
			mainWindow.inputHistory.noteInputHistoryObjectScopeDidChange()
		}

		if reloadAction.contains(.logTranscripts) {
			for client in appController.clientDirectory.clientList {
				client.reopenLogFileIfNeeded()

				for channel in client.channelList {
					channel.reopenLogFileIfNeeded()
				}
			}
		}

		if reloadAction.contains(.scrollbackSaveLimit) {
			Scrollback.shared.resetMaximumLineCount()
		}

		if reloadAction.contains(.scrollbackVisibleLimit) {
			for client in appController.clientDirectory.clientList {
				client.transcriptController?.changeScrollbackLimit()

				for channel in client.channelList {
					channel.transcriptController?.changeScrollbackLimit()
				}
			}
		}
	}

	private static func notifyPreferenceObservers(for reloadAction: PreferencesReloadAction) {
		if reloadAction.contains(.preferencesChanged) {
			let appController: ApplicationDelegate = AppServices.delegate
			guard let mainWindow = appController.mainWindow else { return }

			appController.clientDirectory.preferencesChanged()
			mainWindow.preferencesChanged()
		}
	}
}
