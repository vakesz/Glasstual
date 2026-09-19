// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation

nonisolated extension Notification.Name {
	static let settingsReloadRequested = Notification.Name("Glasstual.settingsReloadRequested")
}

/** What the application has to redo, as a set of independent obligations.

 The raw values are runtime state only -- nothing persists, exports or sends
 them -- so they are renumbered freely whenever a case comes or goes. */
nonisolated struct SettingsReloadAction: OptionSet, Sendable {
	let rawValue: UInt

	static let appearance = Self(rawValue: 1 << 0)
	static let dockIconBadges = Self(rawValue: 1 << 1)
	static let highlightKeywords = Self(rawValue: 1 << 2)
	static let highlightLogging = Self(rawValue: 1 << 3)
	static let inputHistoryScope = Self(rawValue: 1 << 4)
	static let logTranscripts = Self(rawValue: 1 << 5)
	static let memberList = Self(rawValue: 1 << 6)
	static let memberListSortOrder = Self(rawValue: 1 << 7)
	static let memberListUserBadges = Self(rawValue: 1 << 8)
	static let settingsChanged = Self(rawValue: 1 << 9)
	static let scrollbackSaveLimit = Self(rawValue: 1 << 10)
	static let scrollbackVisibleLimit = Self(rawValue: 1 << 11)
	static let sidebar = Self(rawValue: 1 << 12)
	static let sidebarUnreadBadges = Self(rawValue: 1 << 13)
	static let style = Self(rawValue: 1 << 14)
	static let textDirection = Self(rawValue: 1 << 15)
	static let textFieldFontSize = Self(rawValue: 1 << 16)

	/** What one write does not ask for.

	 `settingsChanged` is the coarse "read everything again" broadcast, and
	 `highlightKeywords` rewrites the very list a control may still be editing --
	 dropping the blank row being typed into and reordering the rest under the
	 cursor. Both belong to the end of a settings session, which asks for them
	 when it closes, and to an import, which changes many keys at once. */
	static let wholeSessionOnly: Self = [.settingsChanged, .highlightKeywords]
}

/** The announcement each owner of live state listens for.

 A `MainActorMessage` rather than a bare notification because the reload has to
 be finished by the time the write that asked for it returns: Foundation calls
 these observers inline on the main actor, so a settings sheet that flips a
 switch sees the member list redrawn in the same turn, and a settings import
 finishes reloading before it reports that it is done. */
nonisolated struct SettingsReloadRequest: NotificationCenter.MainActorMessage, Sendable {
	/// Nothing owns the request -- it is about the defaults store, which is a
	/// value -- so it is posted without a subject and every observer sees it.
	typealias Subject = NSApplication

	private static let actionKey = "action"

	let action: SettingsReloadAction

	static var name: Notification.Name {
		.settingsReloadRequested
	}

	/** Spelled out rather than left to the default interop so that the bridge is
	 one readable pair: the action crosses as its raw value. */
	static func makeNotification(_ message: Self) -> Notification {
		Notification(
			name: name,
			object: nil,
			userInfo: [actionKey: message.action.rawValue]
		)
	}

	static func makeMessage(_ notification: Notification) -> Self? {
		guard let rawValue = notification.userInfo?[actionKey] as? UInt else {
			return nil
		}

		return Self(action: SettingsReloadAction(rawValue: rawValue))
	}
}

/** What a changed setting makes the running application redo.

 A setting is read where it is used, so most changes need nothing. The ones
 that do are listed once, beside the key declaration each names, and a change to
 anything else carries only `settingsChanged`.

 Nothing here reaches into a window, a list or a connection: the obligations are
 announced and each owner answers the ones that are its own. What this type
 still does itself are the two application-wide services -- the appearance and
 the transcript theme -- which have to have moved before anything redraws
 against them, and the keyword store, which is a setting. */
@MainActor
enum SettingsReload {
	/// What a change to each key has to reload. A key that is not listed needs
	/// nothing beyond the notification every change carries.
	private static let actionsByKeyName: [String: SettingsReloadAction] = {
		var actions: [String: SettingsReloadAction] = [:]

		func reload(_ action: SettingsReloadAction, on keys: [any AnySettingsKey]) {
			for key in keys {
				actions[key.name, default: []].formUnion(action)
			}
		}

		reload(.style, on: [
			SettingsKeys.Theme.transcriptTheme,
			SettingsKeys.Messages.filterUnicodeTextSpam,
			SettingsKeys.Appearance.conversationTrackingIncludesModeSymbol,
			SettingsKeys.Messages.disableNicknameColorHashing,
			SettingsKeys.Messages.showDateChanges,
			SettingsKeys.Messages.showInlineMedia,
			SettingsKeys.Messages.showJoinLeave,
			// The transcript lays a line out for the direction it is written in,
			// so the direction is a style change as well as an input one.
			SettingsKeys.Messages.rightToLeftFormatting,
		])
		reload(.highlightKeywords, on: [
			SettingsKeys.Highlights.matchKeywords,
			SettingsKeys.Highlights.excludeKeywords,
		])
		reload(.highlightLogging, on: [SettingsKeys.Logging.logHighlights])
		reload(.textDirection, on: [SettingsKeys.Messages.rightToLeftFormatting])
		reload(.textFieldFontSize, on: [SettingsKeys.Input.textViewFontSize])
		reload(.inputHistoryScope, on: [SettingsKeys.Input.historyIsPerSelection])
		reload(.dockIconBadges, on: [
			SettingsKeys.Notifications.displayDockBadge,
			SettingsKeys.Notifications.publicMessageCountOnDockBadge,
		])
		reload(.appearance, on: [SettingsKeys.Appearance.preferredAppearance])
		reload(.memberListSortOrder, on: [SettingsKeys.Appearance.memberListSortFavorsServerStaff])
		reload([.memberList, .memberListUserBadges], on:
			UserListModeBadge.allCases.map(\.settingsKey) + [SettingsKeys.Appearance.memberListNoModeSymbol])
		reload(.sidebarUnreadBadges, on: [SettingsKeys.Badges.sidebarUnreadHighlight])
		reload(.scrollbackSaveLimit, on: [SettingsKeys.Logging.scrollbackSaveLimit])
		reload(.scrollbackVisibleLimit, on: [SettingsKeys.Logging.scrollbackVisibleLimit])
		reload(.logTranscripts, on: [SettingsKeys.Logging.logToDisk])
		reload(.sidebar, on: [SettingsKeys.Sessions.serverSessions])

		return actions
	}()

	static func perform(forKeys keys: [String]) {
		perform(action(forKeys: keys))
	}

	/// The mapping is kept separate from performing it so it can be checked
	/// without a main window.
	static func action(forKeys keys: [String]) -> SettingsReloadAction {
		var action: SettingsReloadAction = .settingsChanged

		for key in keys {
			action.formUnion(actionsByKeyName[key] ?? [])
		}

		return action
	}

	/** Reloads what `reloadAction` names.

	 The order is the only reason this is a sequence rather than one post: the
	 appearance and the theme are what everything else resolves its colours
	 against, and the connections hold the counts and the orderings the window
	 draws, so both have to be current before an owner is told to redraw. What an
	 owner does with the announcement is that owner's own business. */
	static func perform(_ reloadAction: SettingsReloadAction) {
		guard reloadAction.isEmpty == false else { return }

		if reloadAction.contains(.appearance) {
			AppServices.appearance.updateAppearance()
			/* Ahead of the redraws: they resolve theme colours against the
			 snapshot the controller publishes, and the notification
			 `updateAppearance` posts would only reach it a turn later. */
			AppServices.theme.appearanceDidChange()
		}

		if reloadAction.contains(.style) {
			AppServices.theme.reload()
		}

		if reloadAction.contains(.highlightKeywords) {
			SettingsKeys.Highlights.cleanUpStoredKeywords()
		}

		AppServices.chatSession?.settingsChanged(reloadAction)

		NotificationCenter.default.post(SettingsReloadRequest(action: reloadAction))
	}
}
