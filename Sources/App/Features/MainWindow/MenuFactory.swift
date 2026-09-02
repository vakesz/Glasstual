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
		let children: [Entry]
		let isSeparator: Bool

		static func item(
			_ title: String,
			_ command: MenuCommand? = nil,
			_ action: Selector? = nil,
			key: String = "",
			modifiers: NSEvent.ModifierFlags = .command,
			children: [Entry] = []
		) -> Entry {
			Entry(title: title, command: command, action: action, key: key,
			      modifiers: modifiers, children: children, isSeparator: false)
		}

		static func separator(_ command: MenuCommand? = nil) -> Entry {
			Entry(title: "", command: command, action: nil, key: "", modifiers: [], children: [],
			      isSeparator: true)
		}
	}

	static func install(on controller: MenuController) {
		controller.serverListNoSelectionMenu = contextMenu([
			.item(MenuStrings.Server.addServer, .serverListAddServer, #selector(MenuController.addServer(_:))),
		], controller)
		controller.channelViewChannelNameMenu = contextMenu([
			.item(
				MenuStrings.Channel.joinChannel,
				.channelNameJoinChannel,
				#selector(MenuController.joinChannelClicked(_:))
			),
		], controller)
		controller.channelViewURLMenu = contextMenu([
			.item(MenuStrings.Transcript.copyURL, .copyLinkURL, #selector(MenuController.copyUrl(_:))),
		], controller)
		controller.dockMenu = contextMenu([
			.item(
				MenuStrings.File.disableNotifications,
				.dockDisableNotifications,
				#selector(MenuController.toggleMuteOnNotifications(_:))
			),
			.item(
				MenuStrings.File.disableNotificationSounds,
				.dockDisableNotificationSounds,
				#selector(MenuController.toggleMuteOnNotificationSounds(_:))
			),
		], controller)
		controller.channelViewGeneralMenu = contextMenu(channelViewEntries, controller)
		controller.mainMenuChannelMenu = contextMenu(channelEntries, controller)
		controller.mainMenuQueryMenu = contextMenu(queryEntries, controller)
		controller.mainWindowSegmentedControllerCellMenu = contextMenu(segmentedEntries, controller)
		controller.userControlMenu = contextMenu(memberEntries, controller)

		let mainMenu = menu(MenuStrings.MenuBar.application, mainMenuEntries, controller)
		controller.mainMenuServerMenuItem = mainMenu.item(for: .serverMenu)
		controller.mainMenuChannelMenuItem = mainMenu.item(for: .channelMenu)
		controller.mainMenuQueryMenuItem = mainMenu.item(for: .queryMenu)
		controller.mainMenuNavigationChannelListMenu = mainMenu.item(for: .navigationChannelList)?.submenu ?? NSMenu()
		controller.muteNotificationsFileMenuItem = mainMenu.item(for: .disableNotifications)
		controller.muteNotificationsSoundsFileMenuItem = mainMenu.item(for: .disableNotificationSounds)
		controller.muteNotificationsDockMenuItem = controller.dockMenu.item(for: .dockDisableNotifications)
		controller.muteNotificationsSoundsDockMenuItem = controller.dockMenu.item(for: .dockDisableNotificationSounds)

		NSApp.mainMenu = mainMenu
		NSApp.servicesMenu = mainMenu.item(for: .services)?.submenu
		NSApp.windowsMenu = mainMenu.item(for: .windowMenu)?.submenu
		NSApp.helpMenu = mainMenu.item(for: .helpMenu)?.submenu
	}

	/** A menu that is only ever popped up, never hung under a titled item.
	 AppKit draws no title for one, so it carries none to translate. */
	private static func contextMenu(_ entries: [Entry], _ controller: MenuController) -> NSMenu {
		menu("", entries, controller)
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
						item.target = controller
					}
				}
				item.keyEquivalentModifierMask = entry.key.isEmpty ? [] : entry.modifiers
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
		.item(MenuStrings.MenuBar.view, .viewMenu, children: viewEntries),
		.item(MenuStrings.MenuBar.server, .serverMenu, children: serverEntries),
		.item(MenuStrings.MenuBar.channel, .channelMenu),
		.item(MenuStrings.MenuBar.query, .queryMenu),
		.item(MenuStrings.MenuBar.navigation, .navigationMenu, children: navigationEntries),
		.item(MenuStrings.MenuBar.window, .windowMenu, children: windowEntries),
		.item(MenuStrings.MenuBar.help, .helpMenu, children: helpEntries),
	]

	static let applicationEntries: [Entry] = [
		.item(MenuStrings.Application.about, .about, #selector(MenuController.showAboutWindow(_:))),
		.separator(.aboutSeparator),
		.item(
			MenuStrings.Application.settings,
			.settings,
			#selector(MenuController.showPreferencesWindow(_:)),
			key: ","
		),
		.separator(.settingsSeparator),
		.item(MenuStrings.Application.services, .services, children: []),
		.separator(.servicesSeparator),
		.item(MenuStrings.Application.hide, .hideApplication, #selector(NSApplication.hide(_:)), key: "h"),
		.item(
			MenuStrings.Application.hideOthers,
			.hideOthers,
			#selector(NSApplication.hideOtherApplications(_:)),
			key: "h",
			modifiers: [.command, .option]
		),
		.item(MenuStrings.Application.showAll, .showAll, #selector(NSApplication.unhideAllApplications(_:))),
		.separator(.showAllSeparator),
		.item(MenuStrings.Application.quit, .quit, #selector(NSApplication.terminate(_:)), key: "q"),
	]

	static let fileEntries: [Entry] = [
		.item(
			MenuStrings.File.disableNotifications,
			.disableNotifications,
			#selector(MenuController.toggleMuteOnNotifications(_:))
		),
		.item(
			MenuStrings.File.disableNotificationSounds,
			.disableNotificationSounds,
			#selector(MenuController.toggleMuteOnNotificationSounds(_:)),
			key: "M"
		),
		.separator(.disableNotificationSoundsSeparator),
		.item(MenuStrings.File.print, .printLog, #selector(MenuController.print(_:)), key: "p"),
		.separator(.printLogSeparator),
		.item(MenuStrings.File.closeWindow, .closeWindow, #selector(MenuController.closeWindow(_:)), key: "w"),
	]

	static let editEntries: [Entry] = [
		.item(MenuStrings.Edit.undo, .undo, #selector(StandardEditingActions.undo(_:)), key: "z"),
		.item(MenuStrings.Edit.redo, .redo, #selector(StandardEditingActions.redo(_:)), key: "Z"),
		.separator(.redoSeparator),
		.item(MenuStrings.Edit.cut, .cut, #selector(NSText.cut(_:)), key: "x"),
		.item(MenuStrings.Edit.copy, .copy, #selector(NSText.copy(_:)), key: "c"),
		.item(MenuStrings.Edit.paste, .paste, #selector(MenuController.paste(_:)), key: "v"),
		.item(MenuStrings.Edit.delete, .delete, #selector(NSText.delete(_:))),
		.item(MenuStrings.Edit.selectAll, .selectAll, #selector(NSText.selectAll(_:)), key: "a"),
		.separator(.selectAllSeparator),
		.item(MenuStrings.Edit.find, .find, children: [
			.item(MenuStrings.Edit.findText, .findText, #selector(MenuController.showFindPrompt(_:)), key: "f"),
			.item(MenuStrings.Edit.findNext, .findNext, #selector(MenuController.showFindPrompt(_:)), key: "g"),
			.item(
				MenuStrings.Edit.findPrevious,
				.findPrevious,
				#selector(MenuController.showFindPrompt(_:)),
				key: "G",
				modifiers: [.command, .shift]
			),
		]),
	]

	static let viewEntries: [Entry] = [
		.item(MenuStrings.View.markScrollback, .markScrollback, #selector(MenuController.markScrollback(_:)), key: "l"),
		.item(
			MenuStrings.View.scrollbackMarker,
			.scrollbackMarker,
			#selector(MenuController.gotoScrollbackMarker(_:)),
			key: "l",
			modifiers: [.command, .control]
		),
		.separator(.scrollbackMarkerSeparator),
		.item(MenuStrings.View.markAllAsRead, .markAllRead, #selector(MenuController.markAllAsRead(_:)), key: "U"),
		.item(
			MenuStrings.View.clearScrollback,
			.clearScrollback,
			#selector(MenuController.clearScrollback(_:)),
			key: "k"
		),
		.separator(.clearScrollbackSeparator),
		.item(
			MenuStrings.View.increaseFontSize,
			.increaseFont,
			#selector(MenuController.increaseLogFontSize(_:)),
			key: "="
		),
		.item(
			MenuStrings.View.decreaseFontSize,
			.decreaseFont,
			#selector(MenuController.decreaseLogFontSize(_:)),
			key: "-"
		),
		.separator(.decreaseFontSeparator),
		.item(
			MenuStrings.View.enterFullScreen,
			.enterFullScreen,
			#selector(NSWindow.toggleFullScreen(_:)),
			key: "f",
			modifiers: [.command, .control]
		),
	]

	static let serverEntries: [Entry] = [
		.item(MenuStrings.Server.connect, .connect, #selector(MenuController.connect(_:))),
		.item(
			MenuStrings.Server.connectWithoutProxy,
			.connectWithoutProxy,
			#selector(MenuController.connectBypassingProxy(_:))
		),
		.item(MenuStrings.Server.disconnect, .disconnect, #selector(MenuController.disconnect(_:))),
		.item(
			MenuStrings.Server.cancelReconnect,
			.cancelReconnect,
			#selector(MenuController.cancelReconnection(_:))
		),
		.separator(.cancelReconnectSeparator),
		.item(MenuStrings.Server.channelList, .channelList, #selector(MenuController.showServerChannelList(_:))),
		.item(
			MenuStrings.Server.changeNickname,
			.changeNickname,
			#selector(MenuController.showServerChangeNicknameSheet(_:))
		),
		.separator(.changeNicknameSeparator),
		.item(MenuStrings.Server.addServer, .addServer, #selector(MenuController.addServer(_:))),
		.item(MenuStrings.Server.duplicateServer, .duplicateServer, #selector(MenuController.duplicateServer(_:))),
		.item(MenuStrings.Server.deleteServer, .deleteServer, #selector(MenuController.deleteServer(_:))),
		.separator(.deleteServerSeparator),
		.item(MenuStrings.Server.addChannel, .addChannelToServer, #selector(MenuController.addChannel(_:))),
		.separator(.addChannelToServerSeparator),
		.item(
			MenuStrings.Server.serverProperties,
			.serverProperties,
			#selector(MenuController.showServerPropertiesSheet(_:)),
			key: "u"
		),
	]

	static let channelEntries: [Entry] = [
		.item(MenuStrings.Channel.joinChannel, .joinChannel, #selector(MenuController.joinChannel(_:))),
		.item(MenuStrings.Channel.leaveChannel, .leaveChannel, #selector(MenuController.leaveChannel(_:))),
		.separator(.leaveChannelSeparator),
		.item(
			MenuStrings.Server.addChannel,
			.addChannel,
			#selector(MenuController.addChannel(_:)),
			key: "+",
			modifiers: [.command, .shift]
		),
		.item(MenuStrings.Channel.deleteChannel, .deleteChannel, #selector(MenuController.deleteChannel(_:))),
		.separator(.deleteChannelSeparator),
		.item(
			MenuStrings.Channel.viewLogs,
			.viewChannelLogs,
			#selector(MenuController.openChannelLogs(_:)),
			key: "L"
		),
		.separator(.viewChannelLogsSeparator),
		.item(
			MenuStrings.Channel.modifyTopic,
			.modifyTopic,
			#selector(MenuController.showChannelModifyTopicSheet(_:)),
			key: "t"
		),
		.item(MenuStrings.Channel.modes, .modes, children: [
			.item(
				MenuStrings.Channel.modeModerated,
				.channelModeModerated,
				#selector(MenuController.toggleChannelModerationMode(_:))
			),
			.item(
				MenuStrings.Channel.modeUnmoderated,
				.channelModeUnmoderated,
				#selector(MenuController.toggleChannelModerationMode(_:))
			),
			.item(
				MenuStrings.Channel.modeInviteOnly,
				.channelModeInviteOnly,
				#selector(MenuController.toggleChannelInviteMode(_:))
			),
			.item(
				MenuStrings.Channel.modeAnyoneCanJoin,
				.channelModeAnyoneCanJoin,
				#selector(MenuController.toggleChannelInviteMode(_:))
			),
			.item(
				MenuStrings.Channel.modeManageAll,
				.channelModeManageAll,
				#selector(MenuController.showChannelModifyModesSheet(_:))
			),
		]),
		.separator(.modesSeparator),
		.item(MenuStrings.Channel.bans, .bans, #selector(MenuController.showChannelBanList(_:)), key: "B"),
		.item(
			MenuStrings.Channel.banExceptions,
			.banExceptions,
			#selector(MenuController.showChannelBanExceptionList(_:)),
			key: "E"
		),
		.item(
			MenuStrings.Channel.inviteExceptions,
			.inviteExceptions,
			#selector(MenuController.showChannelInviteExceptionList(_:)),
			key: "I"
		),
		.item(MenuStrings.Channel.quiets, .quiets, #selector(MenuController.showChannelQuietList(_:))),
		.separator(.quietsSeparator),
		.item(
			MenuStrings.Channel.channelProperties,
			.channelProperties,
			#selector(MenuController.showChannelPropertiesSheet(_:)),
			key: "i"
		),
		.separator(.channelPropertiesSeparator),
		.item(
			MenuStrings.Channel.copyUniqueIdentifier,
			.copyChannelIdentifier,
			#selector(MenuController.copyUniqueIdentifier(_:))
		),
	]

	static let queryEntries: [Entry] = [
		.item(MenuStrings.Query.closeQuery, .closeQuery, #selector(MenuController.leaveChannel(_:))),
		.separator(.closeQuerySeparator),
		.item(MenuStrings.Query.queryLogs, .queryLogs, #selector(MenuController.openChannelLogs(_:)), key: "L"),
	]

	static let navigationEntries: [Entry] = [
		.item(MenuStrings.Navigation.servers, .navigationServers, children: [
			.item(
				MenuStrings.Navigation.nextServer,
				.nextServer,
				#selector(MenuController.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousServer,
				.previousServer,
				#selector(MenuController.performNavigationAction(_:))
			),
			.separator(.previousServerSeparator),
			.item(
				MenuStrings.Navigation.nextActiveServer,
				.nextActiveServer,
				#selector(MenuController.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousActiveServer,
				.previousActiveServer,
				#selector(MenuController.performNavigationAction(_:))
			),
		]),
		.item(MenuStrings.Navigation.channels, .navigationChannels, children: [
			.item(
				MenuStrings.Navigation.nextChannel,
				.nextChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousChannel,
				.previousChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
			.separator(.previousChannelSeparator),
			.item(
				MenuStrings.Navigation.nextActiveChannel,
				.nextActiveChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousActiveChannel,
				.previousActiveChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
			.separator(.previousActiveChannelSeparator),
			.item(
				MenuStrings.Navigation.nextUnreadChannel,
				.nextUnreadChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
			.item(
				MenuStrings.Navigation.previousUnreadChannel,
				.previousUnreadChannel,
				#selector(MenuController.performNavigationAction(_:))
			),
		]),
		.separator(.navigationChannelsSeparator),
		.item(
			MenuStrings.Navigation.moveBackward,
			.moveBackward,
			#selector(MenuController.performNavigationAction(_:))
		),
		.item(
			MenuStrings.Navigation.moveForward,
			.moveForward,
			#selector(MenuController.performNavigationAction(_:))
		),
		.separator(.moveForwardSeparator),
		.item(
			MenuStrings.Navigation.previousSelection,
			.previousSelection,
			#selector(MenuController.performNavigationAction(_:))
		),
		.separator(.previousSelectionSeparator),
		.item(MenuStrings.Navigation.nextHighlight, .nextHighlight, #selector(MenuController.onNextHighlight(_:))),
		.item(
			MenuStrings.Navigation.previousHighlight,
			.previousHighlight,
			#selector(MenuController.onPreviousHighlight(_:))
		),
		.separator(.previousHighlightSeparator),
		.item(
			MenuStrings.Navigation.jumpToCurrentSession,
			.jumpToCurrentSession,
			#selector(MenuController.jumpToCurrentSession(_:))
		),
		.item(MenuStrings.Navigation.jumpToPresent, .jumpToPresent, #selector(MenuController.jumpToPresent(_:))),
		.separator(.jumpToPresentSeparator),
		/* The untitled child is what gives the item a submenu to hand to
			`mainMenuNavigationChannelListMenu`; the tree replaces it wholesale. */
		.item(MenuStrings.Navigation.channelList, .navigationChannelList, children: [.item("")]),
		.separator(.navigationChannelListSeparator),
		/* The sidebar filter moved into the window toolbar, so this focuses that
			field. Channel Spotlight keeps its own item below rather than being
			left with no way in. */
		.item(
			MenuStrings.Navigation.searchChannels,
			.searchChannels,
			#selector(MenuController.focusSearchField(_:)),
			key: "d"
		),
		.item(
			MenuStrings.Navigation.channelSpotlight,
			.channelSpotlight,
			#selector(MenuController.showChannelSpotlightWindow(_:)),
			key: "d",
			modifiers: [.command, .option]
		),
	]

	static let windowEntries: [Entry] = [
		.item(MenuStrings.Window.minimize, .minimize, #selector(NSWindow.performMiniaturize(_:)), key: "m"),
		.item(MenuStrings.Window.zoom, .zoom, #selector(NSWindow.performZoom(_:))),
		.separator(.zoomSeparator),
		.item(
			MainWindowStrings.Menu.memberList(isVisible: true),
			.toggleMemberList,
			#selector(MenuController.toggleMemberListVisibility(_:)),
			key: "u",
			modifiers: [.command, .option]
		),
		.item(
			MainWindowStrings.Menu.serverList(isVisible: true),
			.toggleServerList,
			#selector(MenuController.toggleServerListVisibility(_:)),
			key: "s",
			modifiers: [.command, .option]
		),
		.item(
			MenuStrings.Window.toggleAppearance,
			.toggleAppearance,
			#selector(MenuController.toggleMainWindowAppearance(_:)),
			key: "D"
		),
		.separator(.toggleAppearanceSeparator),
		.item(
			MenuStrings.Window.sortChannelList,
			.sortChannelList,
			#selector(MenuController.sortChannelListNames(_:)),
			key: "r"
		),
		.separator(.sortChannelListSeparator),
		.item(MenuStrings.Window.centerWindow, .centerWindow, #selector(MenuController.centerMainWindow(_:))),
		.item(MenuStrings.Window.resetWindow, .resetWindow, #selector(MenuController.resetMainWindowFrame(_:))),
		.separator(.resetWindowSeparator),
		.item(
			MenuStrings.Window.mainWindow,
			.mainWindow,
			#selector(MenuController.showMainWindow(_:)),
			key: "1",
			modifiers: .control
		),
		.item(
			MenuStrings.Window.addressBook,
			.addressBook,
			#selector(MenuController.showAddressBook(_:)),
			key: "2",
			modifiers: .control
		),
		.item(
			MenuStrings.Window.ignoreList,
			.ignoreList,
			#selector(MenuController.showIgnoreList(_:)),
			key: "3",
			modifiers: .control
		),
		.item(
			MenuStrings.Window.viewLogs,
			.viewLogs,
			#selector(MenuController.openLogLocation(_:)),
			key: "4",
			modifiers: .control
		),
		.item(
			MenuStrings.Window.highlightList,
			.highlightList,
			#selector(MenuController.showServerHighlightList(_:)),
			key: "5",
			modifiers: .control
		),
		.item(
			MenuStrings.Window.fileTransfers,
			.fileTransfers,
			#selector(MenuController.showFileTransfersWindow(_:)),
			key: "6",
			modifiers: .control
		),
		.separator(.fileTransfersSeparator),
		.item(
			MenuStrings.Window.bringAllToFront,
			.bringAllToFront,
			#selector(NSApplication.arrangeInFront(_:))
		),
	]

	static let helpEntries: [Entry] = [
		.item(
			MenuStrings.Help.acknowledgements,
			.acknowledgements,
			#selector(MenuController.openAcknowledgements(_:))
		),
		.separator(.acknowledgementsSeparator),
		.item(
			MenuStrings.Help.connectToHelpChannel,
			.connectToHelpChannel,
			#selector(MenuController.connectToGlasstualHelpChannel(_:))
		),
		.item(
			MenuStrings.Help.connectToTestingChannel,
			.connectToTestingChannel,
			#selector(MenuController.connectToGlasstualTestingChannel(_:))
		),
		.separator(.connectToTestingChannelSeparator),
		.item(MenuStrings.Help.advanced, .advanced, children: [
			.item(
				MenuStrings.Help.developerMode,
				.developerMode,
				#selector(MenuController.toggleDeveloperMode(_:))
			),
			.item(
				MenuStrings.Help.hiddenSettings,
				.hiddenSettings,
				#selector(MenuController.showHiddenPreferences(_:))
			),
			.item(
				MenuStrings.Help.exportPreferences,
				.exportPreferences,
				#selector(MenuController.exportPreferences(_:))
			),
			.item(
				MenuStrings.Help.importPreferences,
				.importPreferences,
				#selector(MenuController.importPreferences(_:))
			),
			.item(
				MenuStrings.Help.resetDontAskMeWarnings,
				.resetDontAskMeWarnings,
				#selector(MenuController.resetDoNotAskMePopupWarnings(_:))
			),
		]),
		.separator(.advancedSeparator),
		.item(MenuStrings.Help.welcome, .welcome, #selector(MenuController.showOnboardingWindow(_:))),
	]

	static let channelViewEntries: [Entry] = [
		.item(
			MenuStrings.Server.changeNickname,
			.webChangeNickname,
			#selector(MenuController.showServerChangeNicknameSheet(_:))
		),
		.separator(.webChangeNicknameSeparator),
		.item(MenuStrings.Transcript.searchWithProvider, .webSearch, #selector(MenuController.searchGoogle(_:))),
		.item(
			MenuStrings.Transcript.lookUpInDictionary,
			.webDictionary,
			#selector(MenuController.lookUpInDictionary(_:))
		),
		.separator(.webDictionarySeparator),
		.item(MenuStrings.Edit.copy, .webCopy, #selector(NSText.copy(_:)), key: "c"),
		.item(MenuStrings.Edit.paste, .webPaste, #selector(MenuController.paste(_:)), key: "v"),
		.separator(.webPasteSeparator),
		.item(MenuStrings.Query.queryLogs, .webQueryLogs, #selector(MenuController.openChannelLogs(_:)), key: "L"),
		.item(MenuStrings.MenuBar.channel, .webChannelMenu),
	]

	static let segmentedEntries: [Entry] = [
		.item(MenuStrings.Server.addServer, .segmentedAddServer, #selector(MenuController.addServer(_:))),
		.separator(.segmentedAddServerSeparator),
		.item(MenuStrings.Server.addChannel, .segmentedAddChannel, #selector(MenuController.addChannel(_:))),
	]

	static let memberEntries: [Entry] = [
		.item(MenuStrings.Member.addIgnore, .addIgnore, #selector(MenuController.memberAddIgnore(_:))),
		.item(MenuStrings.Member.modifyIgnore, .modifyIgnore, #selector(MenuController.memberModifyIgnore(_:))),
		.item(MenuStrings.Member.removeIgnore, .removeIgnore, #selector(MenuController.memberRemoveIgnore(_:))),
		.separator(.removeIgnoreSeparator),
		.item(MenuStrings.Member.inviteTo, .inviteTo, #selector(MenuController.memberSendInvite(_:))),
		.separator(.inviteToSeparator),
		.item(MenuStrings.Member.whois, .whois, #selector(MenuController.memberSendWhois(_:))),
		.item(
			MenuStrings.Member.privateMessage,
			.privateMessage,
			#selector(MenuController.memberStartPrivateMessage(_:))
		),
		.separator(.privateMessageSeparator),
		.item(MenuStrings.Member.giveOp, .giveOp, #selector(MenuController.memberModeGiveOp(_:))),
		.item(MenuStrings.Member.giveHalfop, .giveHalfop, #selector(MenuController.memberModeGiveHalfop(_:))),
		.item(MenuStrings.Member.giveVoice, .giveVoice, #selector(MenuController.memberModeGiveVoice(_:))),
		.item(MenuStrings.Member.allModesGiven, .allModesGiven),
		.separator(.allModesGivenSeparator),
		.item(MenuStrings.Member.takeOp, .takeOp, #selector(MenuController.memberModeTakeOp(_:))),
		.item(MenuStrings.Member.takeHalfop, .takeHalfop, #selector(MenuController.memberModeTakeHalfop(_:))),
		.item(MenuStrings.Member.takeVoice, .takeVoice, #selector(MenuController.memberModeTakeVoice(_:))),
		.item(MenuStrings.Member.allModesTaken, .allModesTaken),
		.separator(.allModesTakenSeparator),
		.item(MenuStrings.Member.ban, .ban, #selector(MenuController.memberBanFromChannel(_:))),
		.item(MenuStrings.Member.kick, .kick, #selector(MenuController.memberKickFromChannel(_:))),
		.item(MenuStrings.Member.kickban, .kickban, #selector(MenuController.memberKickbanFromChannel(_:))),
		.separator(.kickbanSeparator),
		.item(MenuStrings.Member.ctcp, .ctcp, children: [
			.item(MenuStrings.Member.sendFile, .ctcpSendFile, #selector(MenuController.memberSendFileRequest(_:))),
			.separator(.ctcpSendFileSeparator),
			.item(MenuStrings.Member.ctcpPing, .ctcpPing, #selector(MenuController.memberSendCTCPPing(_:))),
			.item(MenuStrings.Member.ctcpTime, .ctcpTime, #selector(MenuController.memberSendCTCPTime(_:))),
			.separator(.ctcpTimeSeparator),
			.item(
				MenuStrings.Member.ctcpClientInfo,
				.ctcpClientInfo,
				#selector(MenuController.memberSendCTCPClientInfo(_:))
			),
			.item(MenuStrings.Member.ctcpVersion, .ctcpVersion, #selector(MenuController.memberSendCTCPVersion(_:))),
			.separator(.ctcpVersionSeparator),
			.item(MenuStrings.Member.ctcpFinger, .ctcpFinger, #selector(MenuController.memberSendCTCPFinger(_:))),
			.item(
				MenuStrings.Member.ctcpUserInfo,
				.ctcpUserInfo,
				#selector(MenuController.memberSendCTCPUserinfo(_:))
			),
		]),
		.item(MenuStrings.Member.ircOperator, .ircOperator, children: [
			.item(
				MenuStrings.Member.setVirtualHost,
				.operatorSetVirtualHost,
				#selector(MenuController.showSetVhostPrompt(_:))
			),
			.separator(.operatorSetVirtualHostSeparator),
			.item(MenuStrings.Member.kill, .operatorKill, #selector(MenuController.memberKillFromServer(_:))),
			.item(MenuStrings.Member.shun, .operatorShun, #selector(MenuController.memberShunOnServer(_:))),
			.item(MenuStrings.Member.gline, .operatorGline, #selector(MenuController.memberBanFromServer(_:))),
		]),
		.item(MenuStrings.Member.changeColor, .changeColor, #selector(MenuController.memberChangeColor(_:))),
	]
}
