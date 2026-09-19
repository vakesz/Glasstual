// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension MenuActionController {
	func prepareInitialState() {
		if SettingsKeys.Notifications.soundIsMuted.value {
			muteNotificationsSoundsDockMenuItem?.state = .on
			muteNotificationsSoundsFileMenuItem?.state = .on
		}

		/* The sidebar's overflow menu names its notification item from this;
		 `setNotificationsMuted(_:)` keeps it in step afterwards. */
		mainWindow.chrome.areNotificationsDisabled =
			AppServices.notifications.areNotificationsDisabled

		transcriptGeneralMenu.item(for: .transcriptChannelMenu)?.submenu =
			mainMenuChannelMenu.copy() as? NSMenu

		/* Formatting applies to the message being written, and the formatter
		 belongs to the window that holds the field, so the Format menu can only
		 be filled in once that window exists. */
		mainMenuFormatMenuItem?.submenu = mainWindow.formattingMenu?.makeMenu()

		AppServices.fileTransfers.startUsingDownloadDestinationURL()
		applyMenuSymbols()

		context.observeMenuSessions(sentBy: self)
	}

	func prepareForApplicationTermination() {
		context.prepareForApplicationTermination()
		serverDuplicationTasks.values.forEach { $0.cancel() }
		serverDuplicationTasks.removeAll()
		AppServices.fileTransfers.prepareForApplicationTermination()
	}

	func settingsChanged() {
		AppServices.fileTransfers.clearIPAddress()
	}

	/** Which menu the sidebar pops up over a row, and what that row means while
	 it does.

	 Placement is the menu layer's: all four menus are built here, and a row
	 model that chose between them would be the only part of the sidebar that
	 knows the command graph exists. */
	func contextMenu(for item: ChatItem?) -> (menu: NSMenu, context: MenuTargetContext)? {
		let menu: NSMenu? = if let item {
			if item.isSession {
				mainMenuServerMenuItem?.submenu
			} else {
				item.isChannel ? mainMenuChannelMenu : mainMenuDirectMenu
			}
		} else {
			sidebarNoSelectionMenu
		}
		guard let menu else { return nil }
		return (menu, MenuTargetContext(coordinator: self, item: item))
	}

	/// The menu session belongs to the context the commands read, so the delegate
	/// only hands the menus on: see ``MenuContextResolver/beginMenuSession(for:)``.
	func menuWillOpen(_ menu: NSMenu) {
		context.beginMenuSession(for: menu)
	}

	func menuDidClose(_ menu: NSMenu) {
		context.endMenuSession(for: menu)
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
			sidebarNoSelectionMenu,
			userControlMenu,
		]

		for menu in menus {
			MenuPresentation.apply(to: menu)
		}
	}
}
