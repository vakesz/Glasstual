// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Importing a settings file that turns transcript logging on did not
/// reopen the log files until the next launch, because the key-driven path had
/// no branch for it. `.sidebar` had the same gap.
@Suite("Settings reload action mapping")
@MainActor
struct SettingsReloadActionMappingTests {
	@Test("Every action a key can request has a bit of its own")
	func actionsAreDistinct() {
		let actions: [SettingsReloadAction] = [
			.appearance, .dockIconBadges, .highlightKeywords,
			.highlightLogging, .inputHistoryScope, .logTranscripts,
			.memberList, .memberListSortOrder, .memberListUserBadges, .settingsChanged,
			.scrollbackSaveLimit, .scrollbackVisibleLimit, .sidebar, .sidebarUnreadBadges,
			.style, .textDirection, .textFieldFontSize,
		]

		#expect(Set(actions.map(\.rawValue)).count == actions.count)
	}

	@Test("LogTranscript and the session list reach an action")
	func newlyMappedKeys() {
		#expect(SettingsReload.action(forKeys: [SettingsKeys.Logging.logToDisk.name]).contains(.logTranscripts))
		#expect(SettingsReload.action(forKeys: [SettingsKeys.Sessions.serverSessions.name]).contains(.sidebar))
	}

	@Test("An unrelated key still asks observers to re-read preferences")
	func unrelatedKeyStillNotifies() {
		let action = SettingsReload.action(forKeys: ["SomeKeyNothingMaps"])
		#expect(action.contains(.settingsChanged))
		#expect(action.contains(.logTranscripts) == false)
		#expect(action.contains(.sidebar) == false)
	}

	@Test("Keys that already had a mapping keep it")
	func existingMappingsAreIntact() {
		#expect(SettingsReload.action(forKeys: [SettingsKeys.Logging.logHighlights.name]).contains(.highlightLogging))
		#expect(
			SettingsReload.action(forKeys: [SettingsKeys.Logging.scrollbackSaveLimit.name])
				.contains(.scrollbackSaveLimit)
		)
		#expect(
			SettingsReload.action(forKeys: [SettingsKeys.Theme.transcriptTheme.name]).contains(.style)
		)
	}

	/** The table is the only place a key's obligations are stated, now that the
	 setting controls no longer name their own reload. Each of these used to be
	 spelled out in a pane's `didSet`, and one of them — the writing direction,
	 which relays out the transcript as well as the input field — was the reason
	 the panes could disagree with the table. */
	@Test("The key table states everything the panes used to name themselves")
	func tableCoversWhatThePanesNamed() {
		let direction = SettingsReload.action(forKeys: [SettingsKeys.Messages.rightToLeftFormatting.name])
		#expect(direction.contains(.style))
		#expect(direction.contains(.textDirection))

		let badge = SettingsReload.action(forKeys: [UserListModeBadge.normalOperator.settingsKey.name])
		#expect(badge.contains(.memberList))
		#expect(badge.contains(.memberListUserBadges))

		let noModeSymbol = SettingsReload
			.action(forKeys: [SettingsKeys.Appearance.memberListNoModeSymbol.name])
		#expect(noModeSymbol.contains(.memberList))
		#expect(noModeSymbol.contains(.memberListUserBadges))

		for (key, expected) in [
			(SettingsKeys.Appearance.preferredAppearance.name, SettingsReloadAction.appearance),
			(SettingsKeys.Appearance.memberListSortFavorsServerStaff.name, .memberListSortOrder),
			(SettingsKeys.Badges.sidebarUnreadHighlight.name, .sidebarUnreadBadges),
			(SettingsKeys.Input.historyIsPerSelection.name, .inputHistoryScope),
			(SettingsKeys.Input.textViewFontSize.name, .textFieldFontSize),
			(SettingsKeys.Logging.logHighlights.name, .highlightLogging),
			(SettingsKeys.Logging.scrollbackVisibleLimit.name, .scrollbackVisibleLimit),
			(SettingsKeys.Notifications.displayDockBadge.name, .dockIconBadges),
		] {
			#expect(SettingsReload.action(forKeys: [key]).contains(expected), "\(key)")
		}
	}

	/// The keyboard toggles read their keys when a key is pressed, so a change to
	/// one reloads nothing. Copying the history-scope reload onto them threw the
	/// whole input history away every time either was flipped.
	@Test("A key that needs no reload asks for none", arguments: [
		SettingsKeys.Input.commandReturnSendsAction.name,
		SettingsKeys.Input.controlEnterSendsMessage.name,
	])
	func keysWithoutObligations(key: String) {
		#expect(SettingsReload.action(forKeys: [key]) == .settingsChanged)
		#expect(SettingsReload.action(forKeys: [key]).subtracting(.wholeSessionOnly).isEmpty)
	}

	/** The announcement each owner listens for. A `MainActorMessage` is what
	 makes the reload finish inside the turn that asked for it, and the bridge to
	 and from the notification is spelled out, so it is worth proving that an
	 observer sees the action the poster sent. */
	@Test("The reload request reaches a synchronous observer with its action intact")
	func requestIsDeliveredSynchronously() {
		let center = NotificationCenter()
		let subscriptions = NotificationSubscriptions()
		var received: [SettingsReloadAction] = []

		subscriptions.observeSynchronously(SettingsReloadRequest.self, center: center) { request in
			received.append(request.action)
		}

		let announced: SettingsReloadAction = [.style, .memberList, .settingsChanged]
		center.post(SettingsReloadRequest(action: announced))

		#expect(received == [announced])
		subscriptions.cancelAll()
	}
}
