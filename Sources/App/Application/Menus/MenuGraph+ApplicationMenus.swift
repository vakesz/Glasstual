// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

extension MenuGraph {
	static let mainMenuEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuBarApplication), .applicationMenu, children: applicationEntries),
		.item(String(localized: .MainWindow.menuBarFile), .fileMenu, children: fileEntries),
		.item(String(localized: .MainWindow.menuBarEdit), .editMenu, children: editEntries),
		/* The formatting commands belong to the message being written, so the
			window's formatter fills this in once it exists; see
			`MenuActionController.prepareInitialState()`. */
		.item(String(localized: .MainWindow.menuBarFormat), .formatMenu, children: [.item("")]),
		.item(String(localized: .MainWindow.menuBarView), .viewMenu, children: viewEntries),
		.item(String(localized: .MainWindow.menuBarServer), .serverMenu, children: serverEntries),
		.item(String(localized: .MainWindow.menuBarChannel), .channelMenu),
		.item(String(localized: .MainWindow.menuBarQuery), .queryMenu),
		.item(String(localized: .MainWindow.menuBarNavigation), .navigationMenu, children: navigationEntries),
		.item(String(localized: .MainWindow.menuBarWindow), .windowMenu, children: windowEntries),
		.item(String(localized: .MainWindow.menuBarHelp), .helpMenu, children: helpEntries),
	]

	static let applicationEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuApplicationAbout), .about, #selector(MenuActionController.showAboutWindow(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuApplicationSettings),
			.settings,
			#selector(MenuActionController.showSettingsWindow(_:)),
			key: ","
		),
		.separator(),
		/* Muting is an application-wide mode, not a way of looking at content,
			so it sits with the other application commands. The Dock menu
			offers it as well. */
		.item(
			String(localized: .MainWindow.menuMuteNotifications),
			.muteNotifications,
			#selector(MenuActionController.toggleMuteOnNotifications(_:))
		),
		.item(
			String(localized: .MainWindow.menuMuteNotificationSounds),
			.muteNotificationSounds,
			#selector(MenuActionController.toggleMuteOnNotificationSounds(_:)),
			key: "m",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(String(localized: .MainWindow.menuApplicationServices), .services, children: []),
		.separator(),
		.item(String(localized: .MainWindow.menuApplicationHide), .hideApplication, #selector(NSApplication.hide(_:)), key: "h"),
		.item(
			String(localized: .MainWindow.menuApplicationHideOthers),
			.hideOthers,
			#selector(NSApplication.hideOtherApplications(_:)),
			key: "h",
			modifiers: [.command, .option]
		),
		.item(String(localized: .MainWindow.menuApplicationShowAll), .showAll, #selector(NSApplication.unhideAllApplications(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuApplicationQuit), .quit, #selector(NSApplication.terminate(_:)), key: "q"),
	]

	/** The order the system's own File menus use: what adds something, then
	 Close, then what moves data in and out, then Print last. */
	static let fileEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuServerAddServer), .addServer, #selector(MenuActionController.addServer(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuFileCloseWindow), .closeWindow, #selector(MenuActionController.closeWindow(_:)), key: "w"),
		.separator(),
		.item(
			String(localized: .MainWindow.menuFileImportSettings),
			.importSettings,
			#selector(MenuActionController.importSettings(_:))
		),
		.item(
			String(localized: .MainWindow.menuFileExportSettings),
			.exportSettings,
			#selector(MenuActionController.exportSettings(_:))
		),
		.separator(),
		/* No key equivalent: the Command-digit keys name windows in the
			Window menu. */
		.item(
			String(localized: .MainWindow.menuWindowViewLogs),
			.viewLogs,
			#selector(MenuActionController.openLogLocation(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuFilePrint), .printLog, #selector(MenuActionController.printTranscript(_:)), key: "p"),
	]

	static let viewEntries: [Entry] = [
		/* Showing and hiding the sidebars is a View command everywhere else on
		 the system; the Window menu is for the windows themselves. */
		.item(
			MenuCommand.sidebarTitle(isVisible: true),
			.toggleSidebar,
			#selector(MenuActionController.toggleSidebarVisibility(_:)),
			key: "s",
			modifiers: [.command, .control]
		),
		.item(
			MenuCommand.memberListTitle(isVisible: true),
			.toggleMemberList,
			#selector(MenuActionController.toggleMemberListVisibility(_:)),
			key: "i",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuViewMarkScrollback),
			.setUnreadMarker,
			#selector(MenuActionController.setUnreadMarker(_:)),
			key: "l"
		),
		.item(
			String(localized: .MainWindow.menuViewScrollbackMarker),
			.gotoUnreadMarker,
			#selector(MenuActionController.gotoUnreadMarker(_:)),
			key: "l",
			modifiers: [.command, .control]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuViewMarkAllAsRead),
			.markAllRead,
			#selector(MenuActionController.markAllAsRead(_:)),
			key: "u",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuViewClearScrollback),
			.clearScrollback,
			#selector(MenuActionController.clearScrollback(_:)),
			key: "k"
		),
		.separator(),
		/* No key equivalent: ⌘R reads as Reload everywhere else on the system,
			and this rearranges the sidebar. */
		.item(
			String(localized: .MainWindow.menuWindowSortChannelList),
			.sortChannelList,
			#selector(MenuActionController.sortConversationList(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuViewIncreaseFontSize),
			.increaseFont,
			#selector(MenuActionController.increaseLogFontSize(_:)),
			key: "="
		),
		.item(
			String(localized: .MainWindow.menuViewDecreaseFontSize),
			.decreaseFont,
			#selector(MenuActionController.decreaseLogFontSize(_:)),
			key: "-"
		),
		/* The third of the triple Safari, Mail, Xcode and Preview all ship:
			without it there is no way back to the size the reader started at. */
		.item(
			String(localized: .MainWindow.menuViewActualSize),
			.actualSize,
			#selector(MenuActionController.resetLogFontSize(_:)),
			key: "0"
		),
		.separator(),
		/* One ticked choice per appearance, not a toggle: a command named
			"Toggle" cannot say which appearance is in force, and the three-way
			setting has no "toggle" to express. */
		.item(String(localized: .MainWindow.menuViewAppearance), nil, children: [
			.item(
				String(localized: .MainWindow.menuViewAppearanceSystem),
				.appearanceSystem,
				#selector(MenuActionController.changeAppearance(_:))
			),
			.item(
				String(localized: .MainWindow.menuViewAppearanceLight),
				.appearanceLight,
				#selector(MenuActionController.changeAppearance(_:))
			),
			.item(
				String(localized: .MainWindow.menuViewAppearanceDark),
				.appearanceDark,
				#selector(MenuActionController.changeAppearance(_:))
			),
		]),
		.separator(),
		.item(
			String(localized: .MainWindow.menuViewEnterFullScreen),
			.enterFullScreen,
			#selector(NSWindow.toggleFullScreen(_:)),
			key: "f",
			modifiers: [.command, .control]
		),
	]

	/** `NSApp.windowsMenu` is this menu, so AppKit adds Fill, Center, Move &
	 Resize and the tiling commands after Zoom, and lists the open windows
	 after Bring All to Front. The application's own windows come between,
	 numbered in the order they are listed. */
	static let windowEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuWindowMinimize), .minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
		.item(String(localized: .MainWindow.menuWindowZoom), .zoom, #selector(NSWindow.performZoom(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuWindowResetSize),
			.resetWindow,
			#selector(MenuActionController.resetMainWindowFrame(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuWindowMainWindow),
			.mainWindow,
			#selector(MenuActionController.showMainWindow(_:)),
			key: "1"
		),
		.item(
			String(localized: .MainWindow.menuWindowAddressBook),
			.addressBook,
			#selector(MenuActionController.showAddressBook(_:)),
			key: "2"
		),
		.item(
			String(localized: .MainWindow.menuWindowHighlightList),
			.highlightList,
			#selector(MenuActionController.showHighlightLog(_:)),
			key: "3"
		),
		.item(
			String(localized: .TranscriptLogViewer.menuTitle),
			.browseTranscriptLogs,
			#selector(MenuActionController.showTranscriptLogViewer(_:)),
			key: "4"
		),
		.item(
			String(localized: .MainWindow.menuWindowFileTransfers),
			.fileTransfers,
			#selector(MenuActionController.showFileTransfersWindow(_:)),
			key: "l",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuWindowBringAllToFront),
			.bringAllToFront,
			#selector(NSApplication.arrangeInFront(_:))
		),
	]

	static let helpEntries: [Entry] = [
		/* First, with Command-?, where every Mac app puts its help. AppKit adds
		 the menu's search field above it and opens the field on Command-?. */
		.item(
			String(localized: .MainWindow.menuHelpGlasstualHelp),
			.glasstualHelp,
			#selector(MenuActionController.showHelpBook(_:)),
			key: "?"
		),
		.separator(),
		/* No key equivalent. Command-? belongs to Glasstual Help above, and
			people press it out of habit. Bound here, the same keys opened a
			network connection to a public IRC channel. */
		.item(
			String(localized: .MainWindow.menuHelpConnectToHelpChannel),
			.connectToHelpChannel,
			#selector(MenuActionController.connectToGlasstualHelpChannel(_:))
		),
		.item(
			String(localized: .MainWindow.menuHelpConnectToTestingChannel),
			.connectToTestingChannel,
			#selector(MenuActionController.connectToGlasstualTestingChannel(_:))
		),
		.separator(),
		/* The acknowledgements are in the About panel's credits, where the
			system puts them. */
		.item(String(localized: .MainWindow.menuHelpWelcome), .welcome, #selector(MenuActionController.showOnboardingWindow(_:))),
	]

	/*  The transcript's own menu.

	 Change Nickname, Copy, Paste and View Logs are the same commands the menu
	 bar offers, placed here as well: the title, the key equivalent and the menu
	 they hang in are this table's, while the identity -- and with it the
	 validator -- stays one. */
}
