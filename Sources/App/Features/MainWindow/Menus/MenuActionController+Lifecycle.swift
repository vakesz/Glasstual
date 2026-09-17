// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension MenuActionController {
	func prepareInitialState() {
		if Preferences.Notifications.soundIsMuted.value {
			muteNotificationsSoundsDockMenuItem?.state = .on
			muteNotificationsSoundsFileMenuItem?.state = .on
		}

		/* The sidebar's overflow menu names its notification item from this;
		 `setNotificationsMuted(_:)` keeps it in step afterwards. */
		mainWindow.presentationModel.areNotificationsDisabled =
			AppServices.notifications.areNotificationsDisabled

		transcriptGeneralMenu.item(for: .webChannelMenu)?.submenu =
			mainMenuChannelMenu.copy() as? NSMenu

		/* Formatting applies to the message being written, and the formatter
		 belongs to the window that holds the field, so the Format menu can only
		 be filled in once that window exists. */
		mainMenuFormatMenuItem?.submenu = mainWindow.formattingMenu?.makeMenu()

		AppServices.fileTransfers.startUsingDownloadDestinationURL()
		applyMenuSymbols()

		notifications.observe(NSMenu.willSendActionNotification) { [weak self] notification in
			self?.menuItemWillPerformAction(notification)
		}
		notifications.observe(NSMenu.didSendActionNotification) { [weak self] notification in
			self?.menuItemDidPerformAction(notification)
		}
		notifications.observe(.mainWindowSelectionChanged) { [weak self] notification in
			self?.mainWindowSelectionChanged(notification)
		}
	}

	func prepareForApplicationTermination() {
		selectionResetTask?.cancel()
		selectionResetTask = nil
		serverDuplicationTasks.values.forEach { $0.cancel() }
		serverDuplicationTasks.removeAll()
		notifications.cancelAll()
		AppServices.fileTransfers.prepareForApplicationTermination()
	}

	func preferencesChanged() {
		AppServices.fileTransfers.clearIPAddress()
	}

	/** Only the menu the reader opened opens and closes a menu session.

	 Every submenu shares this delegate, and AppKit sends `menuWillOpen` and
	 `menuDidClose` for each of them as the pointer moves in and out. Treating a
	 submenu transition as a session boundary re-read the window's selection
	 half way through the menu -- so a command chosen from a submenu of a
	 right-clicked row acted on the row that was selected, not the one clicked
	 -- and closed the session while the root menu was still up. A root menu has
	 no supermenu; a submenu does. */
	func menuWillOpen(_ menu: NSMenu) {
		guard menu.supermenu == nil else { return }
		menuIsOpen = true
		pointedClient = mainWindow.selectedClient
		pointedChannel = mainWindow.selectedChannel
		menuPerformedActionLastOpen = false
	}

	func menuDidClose(_ menu: NSMenu) {
		guard menu.supermenu == nil else { return }
		menuIsOpen = false

		/* AppKit closes the menu before it sends the selected item's action.
		 Deferring to the next main-actor turn preserves the click-time
		 selection until that action has run. */
		selectionResetTask?.cancel()
		selectionResetTask = Task { [weak self] in
			guard let self, Task.isCancelled == false else {
				return
			}

			if menuPerformedActionLastOpen == false {
				resetSelectedItems()
			}
		}
	}

	func resetSelectedItems() {
		pointedClient = nil
		pointedChannel = nil
	}

	/** Symbols are for the menus that pop up under the pointer.

	 The menu bar is absent from this list, and that includes the Channel and
	 Query menus. Those two instances hang in the menu bar itself, so drawing
	 symbols into them put images beside menu-bar commands, which macOS never
	 does. The transcript menu's Channel submenu is a copy taken before this
	 runs, and it gets its symbols through `transcriptGeneralMenu`. */
	private func applyMenuSymbols() {
		let menus = [
			transcriptChannelNameMenu,
			transcriptGeneralMenu,
			transcriptURLMenu,
			dockMenu,
			serverListNoSelectionMenu,
			userControlMenu,
		]

		for menu in menus {
			MenuPresentation.apply(to: menu)
		}
	}

	private func mainWindowSelectionChanged(_: Notification) {
		if menuIsOpen == false {
			resetSelectedItems()
		}
	}

	private func menuItemWillPerformAction(_ notification: Notification) {
		guard notificationMenuItem(notification)?.target === self else {
			return
		}
		menuPerformedActionLastOpen = true
	}

	private func menuItemDidPerformAction(_ notification: Notification) {
		guard notificationMenuItem(notification)?.target === self else {
			return
		}
		resetSelectedItems()
	}

	private func notificationMenuItem(_ notification: Notification) -> NSMenuItem? {
		notification.userInfo?["MenuItem"] as? NSMenuItem
	}
}
