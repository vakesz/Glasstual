// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/// Owns the application's static menu graph. The conversation and member
/// entries that follow the sidebar are still filled in by
/// `MenuActionController`, but their insertion points are ordinary `NSMenu`
/// instances rather than nib outlets.
@MainActor
enum MenuGraph {
	struct Entry {
		let title: String
		let command: MenuCommand?
		let action: Selector?
		let key: String
		let modifiers: NSEvent.ModifierFlags
		let isAlternate: Bool
		let children: [Entry]
		let isSeparator: Bool

		static func item(
			_ title: String,
			_ command: MenuCommand? = nil,
			_ action: Selector? = nil,
			key: String = "",
			modifiers: NSEvent.ModifierFlags = .command,
			isAlternate: Bool = false,
			children: [Entry] = []
		) -> Entry {
			Entry(title: title, command: command, action: action, key: key,
			      modifiers: modifiers, isAlternate: isAlternate, children: children,
			      isSeparator: false)
		}

		static func separator() -> Entry {
			Entry(title: "", command: nil, action: nil, key: "", modifiers: [],
			      isAlternate: false, children: [], isSeparator: true)
		}
	}

	/** The commands the menu bar's own titles carry.

	 ``MenuCommand/isTopLevelMenu`` reads this instead of restating the list:
	 the table below is the one place a menu joins or leaves the bar. */
	static let topLevelCommands: Set<MenuCommand> = Set(mainMenuEntries.compactMap(\.command))

	static func install(on controller: MenuActionController) {
		controller.sidebarNoSelectionMenu = contextMenu([
			.item(String(localized: .MainWindow.menuServerAddServer), .addServer, #selector(MenuActionController.addServer(_:))),
		], controller)
		controller.transcriptChannelNameMenu = contextMenu([
			.item(
				String(localized: .MainWindow.menuChannelJoin),
				.channelNameJoinChannel,
				#selector(MenuActionController.joinChannelClicked(_:))
			),
		], controller)
		controller.transcriptURLMenu = contextMenu([
			.item(String(localized: .MainWindow.menuTranscriptCopyUrl), .copyLinkURL, #selector(MenuActionController.copyURL(_:))),
		], controller)
		controller.dockMenu = contextMenu([
			.item(
				String(localized: .MainWindow.menuMuteNotifications),
				.muteNotifications,
				#selector(MenuActionController.toggleMuteOnNotifications(_:))
			),
			.item(
				String(localized: .MainWindow.menuMuteNotificationSounds),
				.muteNotificationSounds,
				#selector(MenuActionController.toggleMuteOnNotificationSounds(_:))
			),
		], controller)
		controller.transcriptGeneralMenu = contextMenu(transcriptEntries, controller)
		controller.mainMenuChannelMenu = contextMenu(channelEntries, controller)
		controller.mainMenuDirectMenu = contextMenu(directEntries, controller)
		controller.userControlMenu = contextMenu(memberEntries, controller)

		let mainMenu = builtMainMenu(for: controller)
		controller.mainMenuServerMenuItem = mainMenu.item(for: .serverMenu)
		controller.mainMenuFormatMenuItem = mainMenu.item(for: .formatMenu)
		controller.mainMenuNavigationConversationListMenu =
			mainMenu.item(for: .navigationChannelList)?.submenu ?? NSMenu()
		controller.muteNotificationsFileMenuItem = mainMenu.item(for: .muteNotifications)
		controller.muteNotificationsSoundsFileMenuItem = mainMenu.item(for: .muteNotificationSounds)
		controller.muteNotificationsDockMenuItem = controller.dockMenu.item(for: .muteNotifications)
		controller.muteNotificationsSoundsDockMenuItem = controller.dockMenu.item(for: .muteNotificationSounds)

		/* The Channel and Query menus are installed once and stay installed:
		 a menu bar whose menus come and go with the selection is a menu bar
		 the reader cannot learn. Validation disables what the selection
		 cannot do. */
		mainMenu.item(for: .channelMenu)?.submenu = controller.mainMenuChannelMenu
		mainMenu.item(for: .queryMenu)?.submenu = controller.mainMenuDirectMenu

		NSApp.mainMenu = mainMenu
		NSApp.servicesMenu = mainMenu.item(for: .services)?.submenu
		NSApp.helpMenu = mainMenu.item(for: .helpMenu)?.submenu
		/* `NSApp.windowsMenu` is deliberately not set: AppKit would append its
		 own list of open windows to a menu that already names every window
		 this application opens, so each one appeared twice. */
	}

	/** A menu that is only ever popped up, never hung under a titled item.
	 AppKit draws no title for one, so it carries none to translate. */
	private static func contextMenu(_ entries: [Entry], _ controller: MenuActionController) -> NSMenu {
		menu("", entries, controller)
	}

	/** The menu graph as this factory builds it, before it is installed.

	 AppKit injects its own items -- Writing Tools, AutoFill, Emoji & Symbols,
	 Start Dictation -- into the Edit menu the moment `NSApp.mainMenu` is set, so
	 `NSApp.mainMenu` is the system's graph as much as this one's. A test that
	 asks what this factory decided asks for this. */
	static func builtMainMenu(for controller: MenuActionController) -> NSMenu {
		menu(String(localized: .MainWindow.menuBarApplication), mainMenuEntries, controller)
	}

	private static func menu(_ title: String, _ entries: [Entry], _ controller: MenuActionController) -> NSMenu {
		let result = NSMenu(title: title)
		result.delegate = controller
		for entry in entries {
			let item: NSMenuItem
			if entry.isSeparator {
				item = .separator()
			} else {
				item = NSMenuItem(title: entry.title, action: entry.action, keyEquivalent: entry.key)
				if let action = entry.action {
					if applicationActions.contains(action) {
						item.target = NSApp
					} else if responderActions.contains(action) {
						item.target = nil
					} else {
						item.target = controller
					}
				}
				item.keyEquivalentModifierMask =
					entry.key.isEmpty && entry.isAlternate == false ? [] : entry.modifiers
				item.isAlternate = entry.isAlternate
				if !entry.children.isEmpty {
					item.submenu = menu(entry.title, entry.children, controller)
				} else if entry.command == .services {
					item.submenu = menu(entry.title, [], controller)
				}
			}
			item.command = entry.command
			result.addItem(item)
		}
		return result
	}

	private static let applicationActions: Set<Selector> = [
		#selector(NSApplication.hide(_:)),
		#selector(NSApplication.hideOtherApplications(_:)),
		#selector(NSApplication.unhideAllApplications(_:)),
		#selector(NSApplication.terminate(_:)),
	]
}
