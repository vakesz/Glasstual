// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit

/** Undo and redo are responder-chain actions AppKit answers without declaring
 them anywhere a `#selector` can name. Declaring them here keeps the two
 selectors checked against a signature instead of spelled as strings. */
@objc
private protocol StandardEditingActions {
	func undo(_ sender: Any?)
	func redo(_ sender: Any?)
}

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

private extension MenuGraph {
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
		/* Muting is an application-wide mode, not a document command: it sits
			beside Settings rather than in a File menu it has nothing to do with. */
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

	static let fileEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuFilePrint), .printLog, #selector(MenuActionController.printTranscript(_:)), key: "p"),
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
		.item(String(localized: .MainWindow.menuFileCloseWindow), .closeWindow, #selector(MenuActionController.closeWindow(_:)), key: "w"),
	]

	static let editEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuEditUndo), .undo, #selector(StandardEditingActions.undo(_:)), key: "z"),
		.item(
			String(localized: .MainWindow.menuEditRedo),
			.redo,
			#selector(StandardEditingActions.redo(_:)),
			key: "z",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(String(localized: .MainWindow.menuEditCut), .cut, #selector(NSText.cut(_:)), key: "x"),
		.item(String(localized: .MainWindow.menuEditCopy), .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(String(localized: .MainWindow.menuEditPaste), .paste, #selector(MenuActionController.paste(_:)), key: "v"),
		.item(
			String(localized: .MainWindow.menuEditPasteAndMatchStyle),
			nil,
			#selector(NSTextView.pasteAsPlainText(_:)),
			key: "v",
			modifiers: [.command, .option, .shift]
		),
		.item(String(localized: .MainWindow.menuEditDelete), .delete, #selector(NSText.delete(_:))),
		.item(String(localized: .MainWindow.menuEditSelectAll), .selectAll, #selector(NSText.selectAll(_:)), key: "a"),
		.separator(),
		.item(String(localized: .MainWindow.menuEditFind), .find, children: [
			.item(
				String(localized: .MainWindow.menuEditFindText),
				.findText,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "f"
			),
			.item(
				String(localized: .MainWindow.menuEditFindNext),
				.findNext,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "g"
			),
			.item(
				String(localized: .MainWindow.menuEditFindPrevious),
				.findPrevious,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "g",
				modifiers: [.command, .shift]
			),
			.item(
				String(localized: .MainWindow.menuEditUseSelectionForFind),
				.useSelectionForFind,
				#selector(MenuActionController.showFindPrompt(_:)),
				key: "e"
			),
		]),
		/* The standard AppKit editing commands, with the selectors AppKit's own
			menu uses: every one of them is answered by whatever text view is first
			responder, so the responder chain — not this application — decides
			which are available and which are ticked. They carry no `MenuCommand`
			because nothing here looks them up or updates them. */
		.item(String(localized: .MainWindow.menuEditSpellingAndGrammar), nil, children: [
			.item(
				String(localized: .MainWindow.menuEditShowSpellingAndGrammar),
				nil,
				#selector(NSText.showGuessPanel(_:)),
				key: ":"
			),
			.item(String(localized: .MainWindow.menuEditCheckDocumentNow), nil, #selector(NSText.checkSpelling(_:)), key: ";"),
			.separator(),
			.item(
				String(localized: .MainWindow.menuEditCheckSpellingWhileTyping),
				nil,
				#selector(NSTextView.toggleContinuousSpellChecking(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditCheckGrammarWithSpelling),
				nil,
				#selector(NSTextView.toggleGrammarChecking(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditCorrectSpellingAutomatically),
				nil,
				#selector(NSTextView.toggleAutomaticSpellingCorrection(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuEditSubstitutions), nil, children: [
			.item(
				String(localized: .MainWindow.menuEditShowSubstitutions),
				nil,
				#selector(NSTextView.orderFrontSubstitutionsPanel(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuEditSmartCopyPaste), nil, #selector(NSTextView.toggleSmartInsertDelete(_:))),
			.item(
				String(localized: .MainWindow.menuEditSmartQuotes),
				nil,
				#selector(NSTextView.toggleAutomaticQuoteSubstitution(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditSmartDashes),
				nil,
				#selector(NSTextView.toggleAutomaticDashSubstitution(_:))
			),
			.item(String(localized: .MainWindow.menuEditSmartLinks), nil, #selector(NSTextView.toggleAutomaticLinkDetection(_:))),
			.item(
				String(localized: .MainWindow.menuEditDataDetectors),
				nil,
				#selector(NSTextView.toggleAutomaticDataDetection(_:))
			),
			.item(
				String(localized: .MainWindow.menuEditTextReplacement),
				nil,
				#selector(NSTextView.toggleAutomaticTextReplacement(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuEditTransformations), nil, children: [
			.item(String(localized: .MainWindow.menuEditMakeUpperCase), nil, #selector(NSResponder.uppercaseWord(_:))),
			.item(String(localized: .MainWindow.menuEditMakeLowerCase), nil, #selector(NSResponder.lowercaseWord(_:))),
			.item(String(localized: .MainWindow.menuEditCapitalize), nil, #selector(NSResponder.capitalizeWord(_:))),
		]),
		.item(String(localized: .MainWindow.menuEditSpeech), nil, children: [
			.item(String(localized: .MainWindow.menuEditStartSpeaking), nil, #selector(NSTextView.startSpeaking(_:))),
			.item(String(localized: .MainWindow.menuEditStopSpeaking), nil, #selector(NSTextView.stopSpeaking(_:))),
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

	static let serverEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuServerConnect), .connect, #selector(MenuActionController.connect(_:))),
		/* Option reveals the proxy-free variant in place, which is how macOS
			offers a modified form of the command above it. AppKit swaps in an
			alternate whose modifiers differ from the primary's, and Connect has
			none. Option alone therefore has to be the whole mask, or the swap
			waits for Command as well. */
		.item(
			String(localized: .MainWindow.menuServerConnectWithoutProxy),
			.connectWithoutProxy,
			#selector(MenuActionController.connectBypassingProxy(_:)),
			modifiers: .option,
			isAlternate: true
		),
		.item(String(localized: .MainWindow.menuServerDisconnect), .disconnect, #selector(MenuActionController.disconnect(_:))),
		.item(
			String(localized: .MainWindow.menuServerCancelReconnect),
			.cancelReconnect,
			#selector(MenuActionController.cancelReconnection(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerChannelList),
			.channelList,
			#selector(MenuActionController.showServerChannelList(_:))
		),
		.item(
			String(localized: .MainWindow.menuServerChangeNickname),
			.changeNickname,
			#selector(MenuActionController.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuServerAddServer), .addServer, #selector(MenuActionController.addServer(_:))),
		.item(
			String(localized: .MainWindow.menuServerDuplicateServer),
			.duplicateServer,
			#selector(MenuActionController.duplicateServer(_:))
		),
		.item(String(localized: .MainWindow.menuServerDeleteServer), .deleteServer, #selector(MenuActionController.deleteServer(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerAddChannel),
			.addChannel,
			#selector(MenuActionController.addChannel(_:))
		),
		.separator(),
		/* ⌘U belongs to Underline now. The comma key already names "the
			settings of", so the three scopes read as one family: ⌘, for the
			application, ⇧⌘, for the server, ⌥⌘, for the channel. */
		.item(
			String(localized: .MainWindow.menuServerProperties),
			.serverProperties,
			#selector(MenuActionController.showServerPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .shift]
		),
	]

	static let channelEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuChannelJoin), .joinChannel, #selector(MenuActionController.joinChannel(_:))),
		.item(String(localized: .MainWindow.menuChannelLeave), .leaveChannel, #selector(MenuActionController.leaveConversation(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuServerAddChannel),
			.addChannel,
			#selector(MenuActionController.addChannel(_:)),
			key: "+",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelDelete),
			.deleteChannel,
			#selector(MenuActionController.deleteConversation(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelViewLogs),
			.viewChannelLogs,
			#selector(MenuActionController.openConversationLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelModifyTopic),
			.modifyTopic,
			#selector(MenuActionController.showChannelModifyTopicSheet(_:)),
			key: "t"
		),
		.item(String(localized: .MainWindow.menuChannelModes), .modes, children: [
			.item(
				String(localized: .MainWindow.menuChannelModeModerated),
				.channelModeModerated,
				#selector(MenuActionController.toggleChannelModerationMode(_:))
			),
			.item(
				String(localized: .MainWindow.menuChannelModeInviteOnly),
				.channelModeInviteOnly,
				#selector(MenuActionController.toggleChannelInviteMode(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuChannelModeManageAll),
				.channelModeManageAll,
				#selector(MenuActionController.showChannelModifyModesSheet(_:))
			),
		]),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelBans),
			.bans,
			#selector(MenuActionController.showChannelMaskList(_:)),
			key: "b",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelBanExceptions),
			.banExceptions,
			#selector(MenuActionController.showChannelBanExceptionList(_:)),
			key: "e",
			modifiers: [.command, .shift]
		),
		.item(
			String(localized: .MainWindow.menuChannelInviteExceptions),
			.inviteExceptions,
			#selector(MenuActionController.showChannelInviteExceptionList(_:)),
			key: "i",
			modifiers: [.command, .shift]
		),
		.item(String(localized: .MainWindow.menuChannelQuiets), .quiets, #selector(MenuActionController.showChannelQuietList(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelProperties),
			.channelProperties,
			#selector(MenuActionController.showChannelPropertiesSheet(_:)),
			key: ",",
			modifiers: [.command, .option]
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuChannelCopyUniqueIdentifier),
			.copyChannelIdentifier,
			#selector(MenuActionController.copyUniqueIdentifier(_:))
		),
	]

	/** The menu for a one-to-one conversation.

	 Query Logs carries no key equivalent. Channel ▸ View Logs sends the same
	 action, validates for a one-to-one conversation too, and already answers
	 Shift-Command-L. Two menu-bar items on one shortcut leave AppKit to pick
	 one of them. */
	static let directEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuQueryClose), .closeQuery, #selector(MenuActionController.leaveConversation(_:))),
		.separator(),
		.item(
			String(localized: .MainWindow.menuQueryLogs),
			.queryLogs,
			#selector(MenuActionController.openConversationLogs(_:))
		),
	]

	static let navigationEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuNavigationServers), .navigationServers, children: [
			.item(
				String(localized: .MainWindow.menuNavigationNextServer),
				.nextServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousServer),
				.previousServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextActiveServer),
				.nextActiveServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousActiveServer),
				.previousActiveServer,
				#selector(MenuActionController.performNavigationAction(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuNavigationChannels), .navigationChannels, children: [
			.item(
				String(localized: .MainWindow.menuNavigationNextChannel),
				.nextChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousChannel),
				.previousChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextActiveChannel),
				.nextActiveChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousActiveChannel),
				.previousActiveChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuNavigationNextUnreadChannel),
				.nextUnreadChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
			.item(
				String(localized: .MainWindow.menuNavigationPreviousUnreadChannel),
				.previousUnreadChannel,
				#selector(MenuActionController.performNavigationAction(_:))
			),
		]),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationMoveBackward),
			.moveBackward,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationMoveForward),
			.moveForward,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationPreviousSelection),
			.previousSelection,
			#selector(MenuActionController.performNavigationAction(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationNextHighlight),
			.nextHighlight,
			#selector(MenuActionController.onNextHighlight(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationPreviousHighlight),
			.previousHighlight,
			#selector(MenuActionController.onPreviousHighlight(_:))
		),
		.separator(),
		.item(
			String(localized: .MainWindow.menuNavigationJumpToCurrentSession),
			.jumpToCurrentSession,
			#selector(MenuActionController.jumpToCurrentSession(_:))
		),
		.item(
			String(localized: .MainWindow.menuNavigationJumpToPresent),
			.jumpToPresent,
			#selector(MenuActionController.jumpToPresent(_:))
		),
		.separator(),
		/* The untitled child is what gives the item a submenu to hand to
			`mainMenuNavigationConversationListMenu`, which is refilled wholesale
			whenever the sidebar changes. */
		.item(String(localized: .MainWindow.menuNavigationChannelList), .navigationChannelList, children: [.item("")]),
		.separator(),
		/* The sidebar filter moved into the window toolbar, so this focuses that
			field. Conversation Search keeps its own item below rather than being
			left with no way in. */
		.item(
			String(localized: .MainWindow.menuNavigationSearchChannels),
			.searchChannels,
			#selector(MenuActionController.focusSearchField(_:)),
			key: "f",
			modifiers: [.command, .option]
		),
		/* Shift-Command-O, the key Xcode's Open Quickly uses for the same kind
			of type-to-jump panel. Option-Command-D is the system's Dock hiding
			shortcut and never reached this item. */
		.item(
			String(localized: .MainWindow.menuNavigationChannelSpotlight),
			.channelSpotlight,
			#selector(MenuActionController.showChannelSpotlightWindow(_:)),
			key: "o",
			modifiers: [.command, .shift]
		),
	]

	static let windowEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuWindowMinimize), .minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
		.item(String(localized: .MainWindow.menuWindowZoom), .zoom, #selector(NSWindow.performZoom(_:))),
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
			String(localized: .MainWindow.menuWindowCenter),
			.centerWindow,
			#selector(MenuActionController.centerMainWindow(_:))
		),
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
			String(localized: .MainWindow.menuWindowViewLogs),
			.viewLogs,
			#selector(MenuActionController.openLogLocation(_:)),
			key: "3"
		),
		.item(
			String(localized: .MainWindow.menuWindowHighlightList),
			.highlightList,
			#selector(MenuActionController.showHighlightLog(_:)),
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
		/* No key equivalent. Command-? opens the Help menu's search field
		 everywhere on the Mac, and people press it out of habit. Bound here, the
		 same keys opened a network connection to a public IRC channel. */
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
		.item(String(localized: .MainWindow.menuHelpWelcome), .welcome, #selector(MenuActionController.showOnboardingWindow(_:))),
		.item(
			String(localized: .MainWindow.menuHelpAcknowledgements),
			.acknowledgements,
			#selector(MenuActionController.openAcknowledgements(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuHelpAdvanced), .advanced, children: [
			.item(
				String(localized: .MainWindow.menuHelpDeveloperMode),
				.developerMode,
				#selector(MenuActionController.toggleDeveloperMode(_:))
			),
			.item(
				String(localized: .MainWindow.menuHelpHiddenSettings),
				.hiddenSettings,
				#selector(MenuActionController.showHiddenSettings(_:))
			),
			.item(
				String(localized: .MainWindow.menuHelpResetWarnings),
				.resetWarnings,
				#selector(MenuActionController.resetSuppressedWarnings(_:))
			),
		]),
	]

	/** The transcript's own menu.

	 Change Nickname, Copy, Paste and Query Logs are the same commands the menu
	 bar offers, placed here as well: the title, the key equivalent and the menu
	 they hang in are this table's, while the identity -- and with it the
	 validator -- stays one. */
	static let transcriptEntries: [Entry] = [
		.item(
			String(localized: .MainWindow.menuServerChangeNickname),
			.changeNickname,
			#selector(MenuActionController.showServerChangeNicknameSheet(_:))
		),
		.separator(),
		.item(
			SystemWebSearch.menuTitle,
			.webSearch,
			#selector(MenuActionController.searchWeb(_:))
		),
		.item(
			String(localized: .MainWindow.menuTranscriptLookUpInDictionary),
			.transcriptDictionary,
			#selector(MenuActionController.lookUpInDictionary(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuEditCopy), .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(String(localized: .MainWindow.menuEditPaste), .paste, #selector(MenuActionController.paste(_:)), key: "v"),
		.separator(),
		.item(
			String(localized: .MainWindow.menuQueryLogs),
			.queryLogs,
			#selector(MenuActionController.openConversationLogs(_:)),
			key: "l",
			modifiers: [.command, .shift]
		),
		.item(String(localized: .MainWindow.menuBarChannel), .transcriptChannelMenu),
	]

	static let memberEntries: [Entry] = [
		.item(String(localized: .MainWindow.menuMemberAddIgnore), .addIgnore, #selector(MenuActionController.memberAddIgnore(_:))),
		.item(
			String(localized: .MainWindow.menuMemberModifyIgnore),
			.modifyIgnore,
			#selector(MenuActionController.memberModifyIgnore(_:))
		),
		.item(
			String(localized: .MainWindow.menuMemberRemoveIgnore),
			.removeIgnore,
			#selector(MenuActionController.memberRemoveIgnore(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberInviteTo), .inviteTo, #selector(MenuActionController.memberSendInvite(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberWhois), .whois, #selector(MenuActionController.memberSendWhois(_:))),
		.item(
			String(localized: .MainWindow.menuMemberPrivateMessage),
			.startDirectConversation,
			#selector(MenuActionController.memberStartDirectConversation(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberGiveOp), .giveOp, #selector(MenuActionController.memberModeGiveOp(_:))),
		.item(
			String(localized: .MainWindow.menuMemberGiveHalfop),
			.giveHalfop,
			#selector(MenuActionController.memberModeGiveHalfop(_:))
		),
		.item(String(localized: .MainWindow.menuMemberGiveVoice), .giveVoice, #selector(MenuActionController.memberModeGiveVoice(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberTakeOp), .takeOp, #selector(MenuActionController.memberModeTakeOp(_:))),
		.item(
			String(localized: .MainWindow.menuMemberTakeHalfop),
			.takeHalfop,
			#selector(MenuActionController.memberModeTakeHalfop(_:))
		),
		.item(String(localized: .MainWindow.menuMemberTakeVoice), .takeVoice, #selector(MenuActionController.memberModeTakeVoice(_:))),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberBan), .ban, #selector(MenuActionController.memberBanFromChannel(_:))),
		.item(String(localized: .MainWindow.menuMemberKick), .kick, #selector(MenuActionController.memberKickFromChannel(_:))),
		.item(
			String(localized: .MainWindow.menuMemberKickban),
			.kickban,
			#selector(MenuActionController.memberKickbanFromChannel(_:))
		),
		.separator(),
		.item(String(localized: .MainWindow.menuMemberCtcp), .ctcp, children: [
			.item(
				String(localized: .MainWindow.menuMemberSendFile),
				.ctcpSendFile,
				#selector(MenuActionController.memberSendFileRequest(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuMemberCtcpPing), .ctcpPing, #selector(MenuActionController.memberSendCTCPPing(_:))),
			.item(String(localized: .MainWindow.menuMemberCtcpTime), .ctcpTime, #selector(MenuActionController.memberSendCTCPTime(_:))),
			.separator(),
			.item(
				String(localized: .MainWindow.menuMemberCtcpClientInfo),
				.ctcpClientInfo,
				#selector(MenuActionController.memberSendCTCPClientInfo(_:))
			),
			.item(
				String(localized: .MainWindow.menuMemberCtcpVersion),
				.ctcpVersion,
				#selector(MenuActionController.memberSendCTCPVersion(_:))
			),
			.separator(),
			.item(
				String(localized: .MainWindow.menuMemberCtcpFinger),
				.ctcpFinger,
				#selector(MenuActionController.memberSendCTCPFinger(_:))
			),
			.item(
				String(localized: .MainWindow.menuMemberCtcpUserInfo),
				.ctcpUserInfo,
				#selector(MenuActionController.memberSendCTCPUserinfo(_:))
			),
		]),
		.item(String(localized: .MainWindow.menuMemberIrcOperator), .ircOperator, children: [
			.item(
				String(localized: .MainWindow.menuMemberSetVirtualHost),
				.operatorSetVirtualHost,
				#selector(MenuActionController.memberSetVirtualHost(_:))
			),
			.separator(),
			.item(String(localized: .MainWindow.menuMemberKill), .operatorKill, #selector(MenuActionController.memberKillFromServer(_:))),
			.item(String(localized: .MainWindow.menuMemberShun), .operatorShun, #selector(MenuActionController.memberShunOnServer(_:))),
			.item(String(localized: .MainWindow.menuMemberGline), .operatorGline, #selector(MenuActionController.memberBanFromServer(_:))),
		]),
		.item(String(localized: .MainWindow.menuMemberChangeColor), .changeColor, #selector(MenuActionController.memberChangeColor(_:))),
	]
}
