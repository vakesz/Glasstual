// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2020 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

/** The menus the application shows, and every command they issue.

 The menu items target this object, so a command is the `@objc` method the item
 sends and nothing else: no forwarder stands in front of it. A command is still
 named twice -- once as a `MenuCommand` case that carries its title, key,
 symbol and validation group, and once as the selector the item sends -- and
 ``validateMenuItem(_:)`` switches on the first to decide the second's
 availability.

 What a command acts on, whether it may run and how a sheet it raises is put on
 screen are three questions of their own: ``MenuContextResolver``,
 ``MenuItemValidator`` and ``MenuSheetPresenter`` answer them, and what is left
 here is the AppKit target the items send to. */
@MainActor
final class MenuActionController: NSObject, NSMenuDelegate, NSMenuItemValidation {
	// MARK: - The menus themselves

	/* AppKit pops these up, and `MenuGraph` fills them. They sit on the same
	 object the items target, so a command is one `@objc` method: there is no
	 forwarder, no enum case naming it a second time, and no switch taking the
	 two apart again. */
	var transcriptChannelNameMenu = NSMenu()
	var transcriptGeneralMenu = NSMenu()
	var transcriptURLMenu = NSMenu()
	var dockMenu = NSMenu()
	var mainMenuNavigationConversationListMenu = NSMenu()
	var mainMenuChannelMenu = NSMenu()
	var mainMenuDirectMenu = NSMenu()
	var mainMenuServerMenuItem: NSMenuItem?
	var mainMenuFormatMenuItem: NSMenuItem?
	var sidebarNoSelectionMenu = NSMenu()
	var userControlMenu = NSMenu()
	var muteNotificationsDockMenuItem: NSMenuItem?
	var muteNotificationsFileMenuItem: NSMenuItem?
	var muteNotificationsSoundsDockMenuItem: NSMenuItem?
	var muteNotificationsSoundsFileMenuItem: NSMenuItem?

	/// What every command here acts on, and the menu session that freezes it.
	let context = MenuContextResolver()

	/// Whether a command may run, asked of the same context the command reads.
	/// It carries no state of its own, so it is made where it is asked.
	var validator: MenuItemValidator {
		MenuItemValidator(context: context)
	}

	var serverDuplicationTasks: [UUID: Task<Void, Never>] = [:]

	override init() {
		super.init()
		MenuGraph.install(on: self)
	}

	var mainWindow: MainWindow {
		AppServices.delegate.mainWindow
	}

	/// The connections the menu acts on. They are set once the application has finished
	/// launching, which is before any menu command can run.
	var chatSession: ChatSession? {
		AppServices.chatSession
	}

	/// AppKit asks the item's target, which is this object: the menu controller
	/// is the menus' delegate, and a delegate is not consulted about
	/// enablement.
	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		validator.validate(menuItem)
	}
}

// MARK: - Dropped files

extension MenuActionController {
	/// Files dropped on the transcript go to the person on the other side, so
	/// this applies to a one-to-one conversation and to nothing else.
	func sendDroppedFilesToSelectedConversation(_ files: [String]) {
		guard let session = context.selectedSession, let conversation = context.selectedConversation,
		      session.isLoggedIn, conversation.isDirect
		else { return }
		sendDroppedFiles(files, nickname: conversation.name)
	}

	func sendDroppedFiles(_ files: [String], nickname: String) {
		guard let session = context.selectedSession, session.isLoggedIn else { return }
		for file in files {
			var isDirectory: ObjCBool = false
			guard FileManager.default.fileExists(atPath: file, isDirectory: &isDirectory),
			      isDirectory.boolValue == false
			else { continue }
			AppServices.fileTransfers.offerSender(for: session, nickname: nickname, path: file, autoOpen: true)
		}
	}
}

// MARK: - Navigation

extension MenuActionController {
	/// Selects the conversation a `glasstual://` link names, which is one of the
	/// identifiers the sidebar's rows carry.
	func navigate(to url: URL) {
		let identifier = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
		guard identifier.count == 36,
		      let item = chatSession?.findItem(withId: identifier)
		else { return }
		mainWindow.select(item)
	}

	/** The Navigation menu's list of every conversation.

	 No key equivalents: the list is ordered by where a conversation happens to
	 sit in the sidebar, so ⌘1 meant a different one as soon as a server
	 connected or a channel was joined — and it took the digits the Window menu
	 names windows with. */
	func populateNavigationConversationList() {
		let menu = mainMenuNavigationConversationListMenu
		guard let chatSession else { return }
		menu.removeAllItems()
		for session in chatSession.sessions {
			let submenu = NSMenu()
			let sessionItem = NSMenuItem()
			sessionItem.title = session.name
			sessionItem.submenu = submenu
			for conversation in session.conversationList {
				let item = NSMenuItem(
					title: conversation.name,
					action: #selector(navigateToConversationInSidebar(_:)),
					keyEquivalent: ""
				)
				item.target = self
				// The identifier travels through the menu item's string payload.
				item.userInfoString = conversation.uniqueIdentifier
				submenu.addItem(item)
			}
			menu.addItem(sessionItem)
		}
	}

	@objc func navigateToConversationInSidebar(_ sender: NSMenuItem) {
		guard let itemIdentifier = sender.userInfoString,
		      let item = chatSession?.findItem(withId: itemIdentifier)
		else { return }
		mainWindow.select(item)
	}

	/// The menu items used to be dispatched by selector string onto the main
	/// window, whose handlers are declared `(NSEvent)` and were handed an
	/// `NSMenuItem`. They are called directly now, with no event.
	@objc func performNavigationAction(_ sender: Any?) {
		guard context.selectedSession != nil, let menuItem = sender as? NSMenuItem else { return }

		switch menuItem.command {
		case .nextServer: mainWindow.selectNextServer(nil)
		case .previousServer: mainWindow.selectPreviousServer(nil)
		case .nextActiveServer: mainWindow.selectNextActiveServer(nil)
		case .previousActiveServer: mainWindow.selectPreviousActiveServer(nil)
		case .nextChannel: mainWindow.selectNextConversation(nil)
		case .previousChannel: mainWindow.selectPreviousConversation(nil)
		case .nextActiveChannel: mainWindow.selectNextActiveConversation(nil)
		case .previousActiveChannel: mainWindow.selectPreviousActiveConversation(nil)
		case .nextUnreadChannel: mainWindow.selectNextUnreadConversation(nil)
		case .previousUnreadChannel: mainWindow.selectPreviousUnreadConversation(nil)
		case .moveBackward: mainWindow.selectPreviousWindow(nil)
		case .moveForward: mainWindow.selectNextWindow(nil)
		case .previousSelection: mainWindow.selectPreviousSelection(nil)
		default: break
		}
	}

	@objc func onNextHighlight(_: Any?) {
		context.selectedViewController?.nextHighlight()
	}

	@objc func onPreviousHighlight(_: Any?) {
		context.selectedViewController?.previousHighlight()
	}

	@objc func jumpToCurrentSession(_: Any?) {
		context.selectedViewController?.jumpToCurrentSession()
	}

	@objc func jumpToPresent(_: Any?) {
		context.selectedViewController?.jumpToPresent()
	}
}

/** The menus the sidebar feeds. The chat session tells the controller when the
 shape of the sidebar changed rather than being called into. */
extension MenuActionController: ChatSessionPresenting {
	func chatSessionSidebarDidChange(_: ChatSession) {
		populateNavigationConversationList()
	}

	func chatSessionSettingsDidChange(_: ChatSession) {
		settingsChanged()
	}
}

/// The sheets the IRC layer raises, and the one folder it asks to be shown.
extension MenuActionController: MenuPresenting {
	func revealInFinder(_ url: URL) {
		NSWorkspace.shared.open(url)
	}

	func toggleMuteOnNotificationSoundsShortcut(on muted: Bool) {
		setNotificationSoundsMuted(muted)
	}

	func showServerPropertiesSheet(for session: ServerSession, selection: ServerPropertiesDestination) {
		MenuSheetPresenter.presentServerProperties(for: session, at: selection)
	}

	func showNicknameColorSheet(forNickname nickname: String) {
		showNicknameColorSheet(for: nickname)
	}
}
