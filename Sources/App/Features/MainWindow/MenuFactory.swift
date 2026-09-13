/* *********************************************************************
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit

/** Undo and redo are responder-chain actions AppKit answers without declaring
 them anywhere a `#selector` can name. Declaring them here keeps the two
 selectors checked against a signature instead of spelled as strings. */
@objc
private protocol StandardEditingActions {
	func undo(_ sender: Any?)
	func redo(_ sender: Any?)
}

/// Owns the application's static menu graph. Dynamic channel/member entries
/// are still populated by `MenuActionCoordinator`, but their insertion points
/// are ordinary `NSMenu` instances rather than nib outlets.
@MainActor
enum MenuFactory {
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

	static func install(on controller: MenuController) {
		controller.serverListNoSelectionMenu = contextMenu([
			.item(MenuStrings.Server.addServer, .serverListAddServer, #selector(MenuActionCoordinator.addServer(_:))),
		], controller)
		controller.channelViewChannelNameMenu = contextMenu([
			.item(
				MenuStrings.Channel.joinChannel,
				.channelNameJoinChannel,
				#selector(MenuActionCoordinator.joinChannelClicked(_:))
			),
		], controller)
		controller.channelViewURLMenu = contextMenu([
			.item(MenuStrings.Transcript.copyURL, .copyLinkURL, #selector(MenuActionCoordinator.copyURL(_:))),
		], controller)
		controller.dockMenu = contextMenu([
			.item(
				MenuStrings.Notifications.muteNotifications,
				.dockMuteNotifications,
				#selector(MenuActionCoordinator.toggleMuteOnNotifications(_:))
			),
			.item(
				MenuStrings.Notifications.muteNotificationSounds,
				.dockMuteNotificationSounds,
				#selector(MenuActionCoordinator.toggleMuteOnNotificationSounds(_:))
			),
		], controller)
		controller.channelViewGeneralMenu = contextMenu(channelViewEntries, controller)
		controller.mainMenuChannelMenu = contextMenu(channelEntries, controller)
		controller.mainMenuQueryMenu = contextMenu(queryEntries, controller)
		controller.mainWindowSegmentedControllerCellMenu = contextMenu(segmentedEntries, controller)
		controller.userControlMenu = contextMenu(memberEntries, controller)

		let mainMenu = builtMainMenu(for: controller)
		controller.mainMenuServerMenuItem = mainMenu.item(for: .serverMenu)
		controller.mainMenuChannelMenuItem = mainMenu.item(for: .channelMenu)
		controller.mainMenuQueryMenuItem = mainMenu.item(for: .queryMenu)
		controller.mainMenuFormatMenuItem = mainMenu.item(for: .formatMenu)
		controller.mainMenuNavigationChannelListMenu = mainMenu.item(for: .navigationChannelList)?.submenu ?? NSMenu()
		controller.muteNotificationsFileMenuItem = mainMenu.item(for: .muteNotifications)
		controller.muteNotificationsSoundsFileMenuItem = mainMenu.item(for: .muteNotificationSounds)
		controller.muteNotificationsDockMenuItem = controller.dockMenu.item(for: .dockMuteNotifications)
		controller.muteNotificationsSoundsDockMenuItem = controller.dockMenu.item(for: .dockMuteNotificationSounds)

		/* The Channel and Query menus are installed once and stay installed:
		 a menu bar whose menus come and go with the selection is a menu bar
		 the reader cannot learn. Validation disables what the selection
		 cannot do. */
		controller.mainMenuChannelMenuItem?.submenu = controller.mainMenuChannelMenu
		controller.mainMenuQueryMenuItem?.submenu = controller.mainMenuQueryMenu

		NSApp.mainMenu = mainMenu
		NSApp.servicesMenu = mainMenu.item(for: .services)?.submenu
		NSApp.helpMenu = mainMenu.item(for: .helpMenu)?.submenu
		/* `NSApp.windowsMenu` is deliberately not set: AppKit would append its
		 own list of open windows to a menu that already names every window
		 this application opens, so each one appeared twice. */
	}

	/** A menu that is only ever popped up, never hung under a titled item.
	 AppKit draws no title for one, so it carries none to translate. */
	private static func contextMenu(_ entries: [Entry], _ controller: MenuController) -> NSMenu {
		menu("", entries, controller)
	}

	/** The menu graph as this factory builds it, before it is installed.

	 AppKit injects its own items -- Writing Tools, AutoFill, Emoji & Symbols,
	 Start Dictation -- into the Edit menu the moment `NSApp.mainMenu` is set, so
	 `NSApp.mainMenu` is the system's graph as much as this one's. A test that
	 asks what this factory decided asks for this. */
	static func builtMainMenu(for controller: MenuController) -> NSMenu {
		menu(MenuStrings.MenuBar.application, mainMenuEntries, controller)
	}

	private static func menu(_ title: String, _ entries: [Entry], _ controller: MenuController) -> NSMenu {
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
						item.target = controller.actionCoordinator
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

	/// Commands AppKit routes down the responder chain. Their items carry no
	/// target, so the first responder both validates and performs them.
	private static let responderActions: Set<Selector> = [
		#selector(NSTextView.pasteAsPlainText(_:)),
		#selector(NSText.showGuessPanel(_:)),
		#selector(NSText.checkSpelling(_:)),
		#selector(NSTextView.toggleContinuousSpellChecking(_:)),
		#selector(NSTextView.toggleGrammarChecking(_:)),
		#selector(NSTextView.toggleAutomaticSpellingCorrection(_:)),
		#selector(NSTextView.orderFrontSubstitutionsPanel(_:)),
		#selector(NSTextView.toggleSmartInsertDelete(_:)),
		#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
		#selector(NSTextView.toggleAutomaticDashSubstitution(_:)),
		#selector(NSTextView.toggleAutomaticLinkDetection(_:)),
		#selector(NSTextView.toggleAutomaticDataDetection(_:)),
		#selector(NSTextView.toggleAutomaticTextReplacement(_:)),
		#selector(NSResponder.uppercaseWord(_:)),
		#selector(NSResponder.lowercaseWord(_:)),
		#selector(NSResponder.capitalizeWord(_:)),
		#selector(NSTextView.startSpeaking(_:)),
		#selector(NSTextView.stopSpeaking(_:)),
		#selector(StandardEditingActions.undo(_:)),
		#selector(StandardEditingActions.redo(_:)),
		#selector(NSText.cut(_:)),
		#selector(NSText.copy(_:)),
		#selector(NSText.delete(_:)),
		#selector(NSText.selectAll(_:)),
		#selector(NSWindow.toggleFullScreen(_:)),
		#selector(NSWindow.performMiniaturize(_:)),
		#selector(NSWindow.performZoom(_:)),
		#selector(NSApplication.arrangeInFront(_:)),
	]
}

// MARK: - Menu contents

private extension MenuFactory {
	static let mainMenuEntries: [Entry] = [
		.item(MenuStrings.MenuBar.application, .applicationMenu, children: applicationEntries),
		.item(MenuStrings.MenuBar.file, .fileMenu, children: fileEntries),
		.item(MenuStrings.MenuBar.edit, .editMenu, children: editEntries),
		/* The formatting commands belong to the message being written, so the
			window's formatter fills this in once it exists; see
			`MenuActionCoordinator.prepareInitialState()`. */
		.item(MenuStrings.MenuBar.format, .formatMenu, children: [.item("")]),
		.item(MenuStrings.MenuBar.view, .viewMenu, children: viewEntries),
		.item(MenuStrings.MenuBar.server, .serverMenu, children: serverEntries),
		.item(MenuStrings.MenuBar.channel, .channelMenu),
		.item(MenuStrings.MenuBar.query, .queryMenu),
		.item(MenuStrings.MenuBar.navigation, .navigationMenu, children: navigationEntries),
		.item(MenuStrings.MenuBar.window, .windowMenu, children: windowEntries),
		.item(MenuStrings.MenuBar.help, .helpMenu, children: helpEntries),
	]

	static let applicationEntries: [Entry] = [
		.item(MenuStrings.Application.about, .about, #selector(MenuActionCoordinator.showAboutWindow(_:))),
		.separator(),
		.item(
			MenuStrings.Application.settings,
			.settings,
			#selector(MenuActionCoordinator.showPreferencesWindow(_:)),
			key: ","
		),
		.separator(),
		/* Muting is an application-wide mode, not a document command: it sits
			beside Settings rather than in a File menu it has nothing to do with. */
		.item(
			MenuStrings.Notifications.muteNotifications,
			.muteNotifications,
			#selector(MenuActionCoordinator.toggleMuteOnNotifications(_:))
		),
		.item(
			MenuStrings.Notifications.muteNotificationSounds,
			.muteNotificationSounds,
			#selector(MenuActionCoordinator.toggleMuteOnNotificationSounds(_:)),
			key: "m",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(MenuStrings.Application.services, .services, children: []),
		.separator(),
		.item(MenuStrings.Application.hide, .hideApplication, #selector(NSApplication.hide(_:)), key: "h"),
		.item(
			MenuStrings.Application.hideOthers,
			.hideOthers,
			#selector(NSApplication.hideOtherApplications(_:)),
			key: "h",
			modifiers: [.command, .option]
		),
		.item(MenuStrings.Application.showAll, .showAll, #selector(NSApplication.unhideAllApplications(_:))),
		.separator(),
		.item(MenuStrings.Application.quit, .quit, #selector(NSApplication.terminate(_:)), key: "q"),
	]

	static let fileEntries: [Entry] = [
		.item(MenuStrings.File.print, .printLog, #selector(MenuActionCoordinator.printTranscript(_:)), key: "p"),
		.separator(),
		.item(
			MenuStrings.File.importSettings,
			.importSettings,
			#selector(MenuActionCoordinator.importSettings(_:))
		),
		.item(
			MenuStrings.File.exportSettings,
			.exportSettings,
			#selector(MenuActionCoordinator.exportSettings(_:))
		),
		.separator(),
		.item(MenuStrings.File.closeWindow, .closeWindow, #selector(MenuActionCoordinator.closeWindow(_:)), key: "w"),
	]

	static let editEntries: [Entry] = [
		.item(MenuStrings.Edit.undo, .undo, #selector(StandardEditingActions.undo(_:)), key: "z"),
		.item(
			MenuStrings.Edit.redo,
			.redo,
			#selector(StandardEditingActions.redo(_:)),
			key: "z",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(MenuStrings.Edit.cut, .cut, #selector(NSText.cut(_:)), key: "x"),
		.item(MenuStrings.Edit.copy, .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(MenuStrings.Edit.paste, .paste, #selector(MenuActionCoordinator.paste(_:)), key: "v"),
		.item(
			MenuStrings.Edit.pasteAndMatchStyle,
			nil,
			#selector(NSTextView.pasteAsPlainText(_:)),
			key: "v",
			modifiers: [.command, .option, .shift]
		),
		.item(MenuStrings.Edit.delete, .delete, #selector(NSText.delete(_:))),
		.item(MenuStrings.Edit.selectAll, .selectAll, #selector(NSText.selectAll(_:)), key: "a"),
		.separator(),
		.item(MenuStrings.Edit.find, .find, children: [
			.item(
				MenuStrings.Edit.findText,
				.findText,
				#selector(MenuActionCoordinator.showFindPrompt(_:)),
				key: "f"
			),
			.item(
				MenuStrings.Edit.findNext,
				.findNext,
				#selector(MenuActionCoordinator.showFindPrompt(_:)),
				key: "g"
			),
			.item(
				MenuStrings.Edit.findPrevious,
				.findPrevious,
				#selector(MenuActionCoordinator.showFindPrompt(_:)),
				key: "g",
				modifiers: [.command, .shift]
			),
			.item(
				MenuStrings.Edit.useSelectionForFind,
				.useSelectionForFind,
				#selector(MenuActionCoordinator.showFindPrompt(_:)),
				key: "e"
			),
		]),
		/* The standard AppKit editing commands, with the selectors AppKit's own
			menu uses: every one of them is answered by whatever text view is first
			responder, so the responder chain — not this application — decides
			which are available and which are ticked. They carry no `MenuCommand`
			because nothing here looks them up or updates them. */
		.item(MenuStrings.Edit.spellingAndGrammar, nil, children: [
			.item(
				MenuStrings.Edit.showSpellingAndGrammar,
				nil,
				#selector(NSText.showGuessPanel(_:)),
				key: ":"
			),
			.item(MenuStrings.Edit.checkDocumentNow, nil, #selector(NSText.checkSpelling(_:)), key: ";"),
			.separator(),
			.item(
				MenuStrings.Edit.checkSpellingWhileTyping,
				nil,
				#selector(NSTextView.toggleContinuousSpellChecking(_:))
			),
			.item(
				MenuStrings.Edit.checkGrammarWithSpelling,
				nil,
				#selector(NSTextView.toggleGrammarChecking(_:))
			),
			.item(
				MenuStrings.Edit.correctSpellingAutomatically,
				nil,
				#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
			),
		]),
		.item(MenuStrings.Edit.substitutions, nil, children: [
			.item(
				MenuStrings.Edit.showSubstitutions,
				nil,
				#selector(NSTextView.orderFrontSubstitutionsPanel(_:))
			),
			.separator(),
			.item(MenuStrings.Edit.smartCopyPaste, nil, #selector(NSTextView.toggleSmartInsertDelete(_:))),
			.item(
				MenuStrings.Edit.smartQuotes,
				nil,
				#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))
			),
			.item(
				MenuStrings.Edit.smartDashes,
				nil,
				#selector(NSTextView.toggleAutomaticDashSubstitution(_:))
			),
			.item(MenuStrings.Edit.smartLinks, nil, #selector(NSTextView.toggleAutomaticLinkDetection(_:))),
			.item(
				MenuStrings.Edit.dataDetectors,
				nil,
				#selector(NSTextView.toggleAutomaticDataDetection(_:))
			),
			.item(
				MenuStrings.Edit.textReplacement,
				nil,
				#selector(NSTextView.toggleAutomaticTextReplacement(_:))
			),
		]),
		.item(MenuStrings.Edit.transformations, nil, children: [
			.item(MenuStrings.Edit.makeUpperCase, nil, #selector(NSResponder.uppercaseWord(_:))),
			.item(MenuStrings.Edit.makeLowerCase, nil, #selector(NSResponder.lowercaseWord(_:))),
			.item(MenuStrings.Edit.capitalize, nil, #selector(NSResponder.capitalizeWord(_:))),
		]),
		.item(MenuStrings.Edit.speech, nil, children: [
			.item(MenuStrings.Edit.startSpeaking, nil, #selector(NSTextView.startSpeaking(_:))),
			.item(MenuStrings.Edit.stopSpeaking, nil, #selector(NSTextView.stopSpeaking(_:))),
			.separator(),
			/* Option+Command+Period, because Command+Period alone is the
				system's Cancel -- which is what this command was bound to, as a
				window registration no menu declared and nothing validated. */
			.item(
				MenuStrings.Edit.skipSpokenNotification,
				.skipSpokenNotification,
				#selector(MenuActionCoordinator.skipSpokenNotification(_:)),
				key: ".",
				modifiers: [.command, .option]
			),
		]),
		/* No Emoji & Symbols and no Start Dictation: AppKit adds both to this
			menu as soon as the main menu is installed -- that is what
			`NSDisabledCharacterPaletteMenuItem` and `NSDisabledDictationMenuItem`
			turn off, and neither key is in this app's Info.plist -- so declaring
			them here showed each one twice. They are the system's to translate too,
			and Start Dictation had no declared selector to send, only the string
			`startDictation:`. */
	]

	static let viewEntries: [Entry] = [
		/* Showing and hiding the sidebars is a View command everywhere else on
		 the system; the Window menu is for the windows themselves. */
		.item(
			MainWindowStrings.Menu.serverList(isVisible: true),
			.toggleServerList,
			#selector(MenuActionCoordinator.toggleServerListVisibility(_:)),
			key: "s",
			modifiers: [.command, .control]
		),
		.item(
			MainWindowStrings.Menu.memberList(isVisible: true),
			.toggleMemberList,
			#selector(MenuActionCoordinator.toggleMemberListVisibility(_:)),
			key: "i",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			MenuStrings.View.markScrollback,
			.markScrollback,
			#selector(MenuActionCoordinator.markScrollback(_:)),
			key: "l"
		),
		.item(
			MenuStrings.View.scrollbackMarker,
			.scrollbackMarker,
			#selector(MenuActionCoordinator.gotoScrollbackMarker(_:)),
			key: "l",
			modifiers: [.command, .control]
		),
		.separator(),
		.item(
			MenuStrings.View.markAllAsRead,
			.markAllRead,
			#selector(MenuActionCoordinator.markAllAsRead(_:)),
			key: "u",
			modifiers: [.command, .shift]
		),
		.item(
			MenuStrings.View.clearScrollback,
			.clearScrollback,
			#selector(MenuActionCoordinator.clearScrollback(_:)),
			key: "k"
		),
		.separator(),
		.item(
			MenuStrings.View.increaseFontSize,
			.increaseFont,
			#selector(MenuActionCoordinator.increaseLogFontSize(_:)),
			key: "="
		),
		.item(
			MenuStrings.View.decreaseFontSize,
			.decreaseFont,
			#selector(MenuActionCoordinator.decreaseLogFontSize(_:)),
			key: "-"
		),
		/* The third of the triple Safari, Mail, Xcode and Preview all ship:
			without it there is no way back to the size the reader started at. */
		.item(
			MenuStrings.View.actualSize,
			.actualSize,
			#selector(MenuActionCoordinator.resetLogFontSize(_:)),
			key: "0"
		),
		.separator(),
		/* One ticked choice per appearance, not a toggle: a command named
			"Toggle" cannot say which appearance is in force, and the three-way
			preference has no "toggle" to express. */
		.item(MenuStrings.View.appearance, nil, children: [
			.item(
				MenuStrings.View.appearanceSystem,
				.appearanceSystem,
				#selector(MenuActionCoordinator.changeAppearance(_:))
			),
			.item(
				MenuStrings.View.appearanceLight,
				.appearanceLight,
				#selector(MenuActionCoordinator.changeAppearance(_:))
			),
			.item(
				MenuStrings.View.appearanceDark,
				.appearanceDark,
				#selector(MenuActionCoordinator.changeAppearance(_:))
			),
		]),
		.separator(),
		.item(
			MenuStrings.View.enterFullScreen,
			.enterFullScreen,
			#selector(NSWindow.toggleFullScreen(_:)),
			key: "f",
			modifiers: [.command, .control]
		),
	]

	static let serverEntries: [Entry] = [
		.item(MenuStrings.Server.connect, .connect, #selector(MenuActionCoordinator.connect(_:))),
		/* Option reveals the proxy-free variant in place, which is how macOS
			offers a modified form of the command above it. */
		.item(
			MenuStrings.Server.connectWithoutProxy,
			.connectWithoutProxy,
			#selector(MenuActionCoordinator.connectBypassingProxy(_:)),
			modifiers: [.command, .option],
			isAlternate: true
		),
		.item(MenuStrings.Server.disconnect, .disconnect, #selector(MenuActionCoordinator.disconnect(_:))),
		.item(
			MenuStrings.Server.cancelReconnect,
			.cancelReconnect,
			#selector(MenuActionCoordinator.cancelReconnection(_:))
		),
		.separator(),
		.item(
			MenuStrings.Server.channelList,
			.channelList,
			#selector(MenuActionCoordinator.showServerChannelList(_:))
		),
		.item(
			MenuStrings.Server.changeNickname,
			.changeNickname,
			#selector(MenuActionCoordinator.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(MenuStrings.Server.addServer, .addServer, #selector(MenuActionCoordinator.addServer(_:))),
		.item(
			MenuStrings.Server.duplicateServer,
			.duplicateServer,
			#selector(MenuActionCoordinator.duplicateServer(_:))
		),
		.item(MenuStrings.Server.deleteServer, .deleteServer, #selector(MenuActionCoordinator.deleteServer(_:))),
		.separator(),
		.item(
			MenuStrings.Server.addChannel,
			.addChannelToServer,
			#selector(MenuActionCoordinator.addChannel(_:))
		),
		.separator(),
		/* ⌘U belongs to Underline now. The comma key already names "the
			settings of", so the three scopes read as one family: ⌘, for the
			application, ⇧⌘, for the server, ⌥⌘, for the channel. */
		.item(
			MenuStrings.Server.serverProperties,
			.serverProperties,
			#selector(MenuActionCoordinator.showServerPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .shift]
		),
	]

	static let channelEntries: [Entry] = [
		.item(MenuStrings.Channel.joinChannel, .joinChannel, #selector(MenuActionCoordinator.joinChannel(_:))),
		.item(MenuStrings.Channel.leaveChannel, .leaveChannel, #selector(MenuActionCoordinator.leaveChannel(_:))),
		.separator(),
		.item(
			MenuStrings.Server.addChannel,
			.addChannel,
			#selector(MenuActionCoordinator.addChannel(_:)),
			key: "+",
			modifiers: [.command, .shift]
		),
		.item(
			MenuStrings.Channel.deleteChannel,
			.deleteChannel,
			#selector(MenuActionCoordinator.deleteChannel(_:))
		),
		.separator(),
		.item(
			MenuStrings.Channel.viewLogs,
			.viewChannelLogs,
			#selector(MenuActionCoordinator.openChannelLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(
			MenuStrings.Channel.modifyTopic,
			.modifyTopic,
			#selector(MenuActionCoordinator.showChannelModifyTopicSheet(_:)),
			key: "t"
		),
		.item(MenuStrings.Channel.modes, .modes, children: [
			.item(
				MenuStrings.Channel.modeModerated,
				.channelModeModerated,
				#selector(MenuActionCoordinator.toggleChannelModerationMode(_:))
			),
			.item(
				MenuStrings.Channel.modeInviteOnly,
				.channelModeInviteOnly,
				#selector(MenuActionCoordinator.toggleChannelInviteMode(_:))
			),
			.separator(),
			.item(
				MenuStrings.Channel.modeManageAll,
				.channelModeManageAll,
				#selector(MenuActionCoordinator.showChannelModifyModesSheet(_:))
			),
		]),
		.separator(),
		.item(
			MenuStrings.Channel.bans,
			.bans,
			#selector(MenuActionCoordinator.showChannelBanList(_:)),
			key: "b",
			modifiers: [.command, .shift]
		),
		.item(
			MenuStrings.Channel.banExceptions,
			.banExceptions,
			#selector(MenuActionCoordinator.showChannelBanExceptionList(_:)),
			key: "e",
			modifiers: [.command, .shift]
		),
		.item(
			MenuStrings.Channel.inviteExceptions,
			.inviteExceptions,
			#selector(MenuActionCoordinator.showChannelInviteExceptionList(_:)),
			key: "i",
			modifiers: [.command, .shift]
		),
		.item(MenuStrings.Channel.quiets, .quiets, #selector(MenuActionCoordinator.showChannelQuietList(_:))),
		.separator(),
		.item(
			MenuStrings.Channel.channelProperties,
			.channelProperties,
			#selector(MenuActionCoordinator.showChannelPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			MenuStrings.Channel.copyUniqueIdentifier,
			.copyChannelIdentifier,
			#selector(MenuActionCoordinator.copyUniqueIdentifier(_:))
		),
	]

	static let queryEntries: [Entry] = [
		.item(MenuStrings.Query.closeQuery, .closeQuery, #selector(MenuActionCoordinator.leaveChannel(_:))),
		.separator(),
		.item(
			MenuStrings.Query.queryLogs,
			.queryLogs,
			#selector(MenuActionCoordinator.openChannelLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
	]

	static let navigationEntries: [Entry] = [
		.item(MenuStrings.Navigation.servers, .navigationServers, children: [
			.item(
				MenuStrings.Navigation.nextServer,
				.nextServer,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousServer,
				.previousServer,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.separator(),
			.item(
				MenuStrings.Navigation.nextActiveServer,
				.nextActiveServer,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousActiveServer,
				.previousActiveServer,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
		]),
		.item(MenuStrings.Navigation.channels, .navigationChannels, children: [
			.item(
				MenuStrings.Navigation.nextChannel,
				.nextChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousChannel,
				.previousChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.separator(),
			.item(
				MenuStrings.Navigation.nextActiveChannel,
				.nextActiveChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousActiveChannel,
				.previousActiveChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.separator(),
			.item(
				MenuStrings.Navigation.nextUnreadChannel,
				.nextUnreadChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousUnreadChannel,
				.previousUnreadChannel,
				#selector(MenuActionCoordinator.performNavigationAction(_:))
			),
		]),
		.separator(),
		.item(
			MenuStrings.Navigation.moveBackward,
			.moveBackward,
			#selector(MenuActionCoordinator.performNavigationAction(_:))
		),
		.item(
			MenuStrings.Navigation.moveForward,
			.moveForward,
			#selector(MenuActionCoordinator.performNavigationAction(_:))
		),
		.separator(),
		.item(
			MenuStrings.Navigation.previousSelection,
			.previousSelection,
			#selector(MenuActionCoordinator.performNavigationAction(_:))
		),
		.separator(),
		.item(
			MenuStrings.Navigation.nextHighlight,
			.nextHighlight,
			#selector(MenuActionCoordinator.onNextHighlight(_:))
		),
		.item(
			MenuStrings.Navigation.previousHighlight,
			.previousHighlight,
			#selector(MenuActionCoordinator.onPreviousHighlight(_:))
		),
		.separator(),
		.item(
			MenuStrings.Navigation.jumpToCurrentSession,
			.jumpToCurrentSession,
			#selector(MenuActionCoordinator.jumpToCurrentSession(_:))
		),
		.item(
			MenuStrings.Navigation.jumpToPresent,
			.jumpToPresent,
			#selector(MenuActionCoordinator.jumpToPresent(_:))
		),
		.separator(),
		/* The untitled child is what gives the item a submenu to hand to
			`mainMenuNavigationChannelListMenu`; the tree replaces it wholesale. */
		.item(MenuStrings.Navigation.channelList, .navigationChannelList, children: [.item("")]),
		.separator(),
		/* The sidebar filter moved into the window toolbar, so this focuses that
			field. Channel Search keeps its own item below rather than being
			left with no way in. */
		.item(
			MenuStrings.Navigation.searchChannels,
			.searchChannels,
			#selector(MenuActionCoordinator.focusSearchField(_:)),
			key: "f",
			modifiers: [.command, .option]
		),
		.item(
			MenuStrings.Navigation.channelSpotlight,
			.channelSpotlight,
			#selector(MenuActionCoordinator.showChannelSpotlightWindow(_:)),
			key: "d",
			modifiers: [.command, .option]
		),
	]

	static let windowEntries: [Entry] = [
		.item(MenuStrings.Window.minimize, .minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
		.item(MenuStrings.Window.zoom, .zoom, #selector(NSWindow.performZoom(_:))),
		.separator(),
		/* No key equivalent: ⌘R reads as Reload everywhere else on the system,
			and this rearranges the sidebar. */
		.item(
			MenuStrings.Window.sortChannelList,
			.sortChannelList,
			#selector(MenuActionCoordinator.sortChannelListNames(_:))
		),
		.separator(),
		.item(
			MenuStrings.Window.centerWindow,
			.centerWindow,
			#selector(MenuActionCoordinator.centerMainWindow(_:))
		),
		.item(
			MenuStrings.Window.resetWindow,
			.resetWindow,
			#selector(MenuActionCoordinator.resetMainWindowFrame(_:))
		),
		.separator(),
		.item(
			MenuStrings.Window.mainWindow,
			.mainWindow,
			#selector(MenuActionCoordinator.showMainWindow(_:)),
			key: "1"
		),
		.item(
			MenuStrings.Window.addressBook,
			.addressBook,
			#selector(MenuActionCoordinator.showAddressBook(_:)),
			key: "2"
		),
		.item(
			MenuStrings.Window.viewLogs,
			.viewLogs,
			#selector(MenuActionCoordinator.openLogLocation(_:)),
			key: "3"
		),
		.item(
			MenuStrings.Window.highlightList,
			.highlightList,
			#selector(MenuActionCoordinator.showServerHighlightList(_:)),
			key: "4"
		),
		.item(
			MenuStrings.Window.fileTransfers,
			.fileTransfers,
			#selector(MenuActionCoordinator.showFileTransfersWindow(_:)),
			key: "l",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			MenuStrings.Window.bringAllToFront,
			.bringAllToFront,
			#selector(NSApplication.arrangeInFront(_:))
		),
	]

	static let helpEntries: [Entry] = [
		/* ⌘? is the system's help key, and the support channel is where this
		 application's help actually is: there is no help book to open. */
		.item(
			MenuStrings.Help.connectToHelpChannel,
			.connectToHelpChannel,
			#selector(MenuActionCoordinator.connectToGlasstualHelpChannel(_:)),
			key: "?"
		),
		.item(
			MenuStrings.Help.connectToTestingChannel,
			.connectToTestingChannel,
			#selector(MenuActionCoordinator.connectToGlasstualTestingChannel(_:))
		),
		.separator(),
		.item(MenuStrings.Help.welcome, .welcome, #selector(MenuActionCoordinator.showOnboardingWindow(_:))),
		.item(
			MenuStrings.Help.acknowledgements,
			.acknowledgements,
			#selector(MenuActionCoordinator.openAcknowledgements(_:))
		),
		.separator(),
		.item(MenuStrings.Help.advanced, .advanced, children: [
			.item(
				MenuStrings.Help.developerMode,
				.developerMode,
				#selector(MenuActionCoordinator.toggleDeveloperMode(_:))
			),
			.item(
				MenuStrings.Help.hiddenSettings,
				.hiddenSettings,
				#selector(MenuActionCoordinator.showHiddenPreferences(_:))
			),
			.item(
				MenuStrings.Help.resetWarnings,
				.resetWarnings,
				#selector(MenuActionCoordinator.resetSuppressedWarnings(_:))
			),
		]),
	]

	static let channelViewEntries: [Entry] = [
		.item(
			MenuStrings.Server.changeNickname,
			.webChangeNickname,
			#selector(MenuActionCoordinator.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(
			MenuSearchProvider.menuTitle,
			.webSearch,
			#selector(MenuActionCoordinator.searchWeb(_:))
		),
		.item(
			MenuStrings.Transcript.lookUpInDictionary,
			.webDictionary,
			#selector(MenuActionCoordinator.lookUpInDictionary(_:))
		),
		.separator(),
		.item(MenuStrings.Edit.copy, .webCopy, #selector(NSText.copy(_:)), key: "c"),
		.item(MenuStrings.Edit.paste, .webPaste, #selector(MenuActionCoordinator.paste(_:)), key: "v"),
		.separator(),
		.item(
			MenuStrings.Query.queryLogs,
			.webQueryLogs,
			#selector(MenuActionCoordinator.openChannelLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.item(MenuStrings.MenuBar.channel, .webChannelMenu),
	]

	static let segmentedEntries: [Entry] = [
		.item(
			MenuStrings.Server.addServer,
			.segmentedAddServer,
			#selector(MenuActionCoordinator.addServer(_:))
		),
		.separator(),
		.item(
			MenuStrings.Server.addChannel,
			.segmentedAddChannel,
			#selector(MenuActionCoordinator.addChannel(_:))
		),
	]

	static let memberEntries: [Entry] = [
		.item(MenuStrings.Member.addIgnore, .addIgnore, #selector(MenuActionCoordinator.memberAddIgnore(_:))),
		.item(
			MenuStrings.Member.modifyIgnore,
			.modifyIgnore,
			#selector(MenuActionCoordinator.memberModifyIgnore(_:))
		),
		.item(
			MenuStrings.Member.removeIgnore,
			.removeIgnore,
			#selector(MenuActionCoordinator.memberRemoveIgnore(_:))
		),
		.separator(),
		.item(MenuStrings.Member.inviteTo, .inviteTo, #selector(MenuActionCoordinator.memberSendInvite(_:))),
		.separator(),
		.item(MenuStrings.Member.whois, .whois, #selector(MenuActionCoordinator.memberSendWhois(_:))),
		.item(
			MenuStrings.Member.privateMessage,
			.privateMessage,
			#selector(MenuActionCoordinator.memberStartPrivateMessage(_:))
		),
		.separator(),
		.item(MenuStrings.Member.giveOp, .giveOp, #selector(MenuActionCoordinator.memberModeGiveOp(_:))),
		.item(
			MenuStrings.Member.giveHalfop,
			.giveHalfop,
			#selector(MenuActionCoordinator.memberModeGiveHalfop(_:))
		),
		.item(MenuStrings.Member.giveVoice, .giveVoice, #selector(MenuActionCoordinator.memberModeGiveVoice(_:))),
		.separator(),
		.item(MenuStrings.Member.takeOp, .takeOp, #selector(MenuActionCoordinator.memberModeTakeOp(_:))),
		.item(
			MenuStrings.Member.takeHalfop,
			.takeHalfop,
			#selector(MenuActionCoordinator.memberModeTakeHalfop(_:))
		),
		.item(MenuStrings.Member.takeVoice, .takeVoice, #selector(MenuActionCoordinator.memberModeTakeVoice(_:))),
		.separator(),
		.item(MenuStrings.Member.ban, .ban, #selector(MenuActionCoordinator.memberBanFromChannel(_:))),
		.item(MenuStrings.Member.kick, .kick, #selector(MenuActionCoordinator.memberKickFromChannel(_:))),
		.item(
			MenuStrings.Member.kickban,
			.kickban,
			#selector(MenuActionCoordinator.memberKickbanFromChannel(_:))
		),
		.separator(),
		.item(MenuStrings.Member.ctcp, .ctcp, children: [
			.item(
				MenuStrings.Member.sendFile,
				.ctcpSendFile,
				#selector(MenuActionCoordinator.memberSendFileRequest(_:))
			),
			.separator(),
			.item(MenuStrings.Member.ctcpPing, .ctcpPing, #selector(MenuActionCoordinator.memberSendCTCPPing(_:))),
			.item(MenuStrings.Member.ctcpTime, .ctcpTime, #selector(MenuActionCoordinator.memberSendCTCPTime(_:))),
			.separator(),
			.item(
				MenuStrings.Member.ctcpClientInfo,
				.ctcpClientInfo,
				#selector(MenuActionCoordinator.memberSendCTCPClientInfo(_:))
			),
			.item(
				MenuStrings.Member.ctcpVersion,
				.ctcpVersion,
				#selector(MenuActionCoordinator.memberSendCTCPVersion(_:))
			),
			.separator(),
			.item(
				MenuStrings.Member.ctcpFinger,
				.ctcpFinger,
				#selector(MenuActionCoordinator.memberSendCTCPFinger(_:))
			),
			.item(
				MenuStrings.Member.ctcpUserInfo,
				.ctcpUserInfo,
				#selector(MenuActionCoordinator.memberSendCTCPUserinfo(_:))
			),
		]),
		.item(MenuStrings.Member.ircOperator, .ircOperator, children: [
			.item(
				MenuStrings.Member.setVirtualHost,
				.operatorSetVirtualHost,
				#selector(MenuActionCoordinator.memberSetVirtualHost(_:))
			),
			.separator(),
			.item(MenuStrings.Member.kill, .operatorKill, #selector(MenuActionCoordinator.memberKillFromServer(_:))),
			.item(MenuStrings.Member.shun, .operatorShun, #selector(MenuActionCoordinator.memberShunOnServer(_:))),
			.item(MenuStrings.Member.gline, .operatorGline, #selector(MenuActionCoordinator.memberBanFromServer(_:))),
		]),
		.item(MenuStrings.Member.changeColor, .changeColor, #selector(MenuActionCoordinator.memberChangeColor(_:))),
	]
}
