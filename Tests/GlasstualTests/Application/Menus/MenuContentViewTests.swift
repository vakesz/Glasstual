// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import SwiftUI
import Testing

/// A validator that expresses availability the way the application's own menu
/// validators do: by hiding the item rather than by disabling it.
@MainActor
private final class MenuValidator: NSObject, NSMenuItemValidation {
	var hiddenTitles: Set<String> = []
	var disabledTitles: Set<String> = []
	private(set) var validationCount = 0
	private(set) var invokedItems: [NSMenuItem] = []

	@objc
	func invoke(_ sender: Any?) {
		if let item = sender as? NSMenuItem {
			invokedItems.append(item)
		}
	}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		validationCount += 1
		menuItem.isHidden = hiddenTitles.contains(menuItem.title)
		return disabledTitles.contains(menuItem.title) == false
	}
}

@MainActor
@Suite("Contextual rendering of AppKit menus", .serialized)
struct MenuContentViewTests {
	@Test(
		"Context JOIN retries the clicked channel after identification without reconnecting",
		arguments: [false, true], [false, true]
	)
	func contextJoinAfterIdentification(otherSessionSelected: Bool, usesNativeMenu: Bool) async throws {
		try await withChannelMenu { controller, window, session, other in
			let context = controller.context
			session.userNickname = "mynick"
			session.markAsLoggedIn()
			session.isConnected = true
			let channel = try #require(session.findConversationOrCreate("#retry"))
			let previousSession = otherSessionSelected ? other : session
			previousSession.markAsLoggedIn()
			let previous = try #require(previousSession.findConversationOrCreate("#active"))
			previous.activate()
			window.select(previous)
			session.join(channel)
			try session.receiveNumericReply(#require(Message(
				line: ":irc.example.test 477 mynick #retry :You need to identify to a registered nick", on: session
			)))
			#expect(channel.status == .parted)

			for line in [
				":irc.example.test 900 mynick mynick!user@host account :You are now logged in",
				":irc.example.test 903 mynick :SASL authentication successful",
			] {
				try session.receiveNumericReply(#require(Message(line: line, on: session)))
			}
			try session.receiveMode(#require(Message(line: ":irc.example.test MODE mynick +r", on: session)))
			#expect(session.startup.authentication == .confirmed)
			let menu = try #require(controller.contextMenu(for: channel))
			let entries = MenuItemSnapshot.validating(menu.menu, context: menu.context)
			let join = try #require(entries.first { $0.command == .joinChannel })
			#expect(join.isEnabled)
			#expect(entries.contains { $0.command == .leaveChannel } == false)
			#expect(window.selectedConversation === previous)
			#expect(context.selectedSession === previousSession)
			#expect(context.selectedConversation === previous)
			let native = MenuContentView.nativeMenu(menu: menu.menu, context: menu.context) {
				window.sidebar.selectFromView(channel.uniqueIdentifier)
			}
			let nativeJoin = try #require(native.item(for: .joinChannel))
			let combined = NSMenu()
			native.removeItem(nativeJoin)
			combined.addItem(nativeJoin)
			#expect(window.selectedConversation === previous)

			// Revalidating the shared NSMenu must not retarget an existing snapshot.
			_ = MenuItemSnapshot.validating(controller.mainMenuChannelMenu)
			let performed: Bool = if usesNativeMenu {
				try NSApp.sendAction(#require(nativeJoin.action), to: nativeJoin.target, from: nativeJoin)
			} else {
				join.perform {
					window.sidebar.selectFromView(channel.uniqueIdentifier)
				}
			}
			#expect(performed)
			/* Clicking the row publishes it, and the command runs against the
			 row the menu was opened on rather than against what the window was
			 showing before the click. */
			#expect(window.selectedConversation === channel)
			#expect(context.selectedSession === session)
			#expect(context.selectedConversation === channel)
			#expect(session.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("JOIN ") }
				== ["JOIN #retry", "JOIN #retry"])
			#expect(other.sentLines.count == 0)
			#expect(channel.status == .joining)
			#expect(channel.errorOnLastJoinAttempt == false)
			#expect(session.isConnected && session.isLoggedIn)
			try session.receiveJoin(#require(Message(line: ":mynick!user@host JOIN :#retry", on: session)))
			#expect(channel.isActive)
			#expect(previous.isActive)
		}
	}

	@Test("Server and empty contexts never inherit the main window channel")
	func contextWithoutChannelDoesNotFallBack() async throws {
		try await withChannelMenu { controller, window, session, other in
			session.markAsLoggedIn()
			other.markAsLoggedIn()
			let channel = try #require(session.findConversationOrCreate("#selected"))
			window.select(channel)
			let context = controller.context
			context.pointedSession = session
			context.pointedConversation = nil
			for item in [other as ChatItem?, nil] {
				let entries = MenuItemSnapshot.validating(
					controller.mainMenuChannelMenu,
					context: MenuTargetContext(coordinator: controller, item: item)
				)
				/* Disabled, not absent: a menu whose shape follows the
				 selection is a menu nobody can learn. */
				let channelCommands = entries.filter {
					$0.command == .joinChannel || $0.command == .leaveChannel
				}
				#expect(channelCommands.isEmpty == false)
				#expect(channelCommands.allSatisfy { $0.isEnabled == false })
				context.withContext(.sidebarItem(item)) {
					#expect(context.selectedSession === item)
					#expect(context.selectedConversation == nil)
					context.withContext(.sidebarItem(channel)) {
						#expect(context.selectedConversation === channel)
					}
					#expect(context.selectedConversation == nil)
				}
				#expect(window.selectedConversation === channel)
				#expect(context.selectedConversation === channel)
			}
		}
	}

	/// Right-clicking a member the list has not selected used to validate and
	/// run the command against whoever was selected before the click.
	@Test("A member-list menu answers for the row it was opened on, not the list's selection")
	func memberContextOverridesTheListSelection() async throws {
		try await withChannelMenu { controller, window, session, _ in
			session.markAsLoggedIn()
			let channel = try #require(session.findConversationOrCreate("#members"))
			channel.activate()
			window.select(channel)
			let membership = try #require(channel.memberInfo)
			let selected = Member(
				user: session.findUserOrCreate("selected"),
				prefixes: session.currentUserPrefixes
			)
			let clicked = Member(
				user: session.findUserOrCreate("clicked"),
				prefixes: session.currentUserPrefixes
			)
			membership.addMember(selected)
			membership.addMember(clicked)
			window.memberList.assign(to: channel)
			window.memberList.selectedMemberIDs = [selected.id]
			let context = controller.context
			/* A member-list menu carries no item of its own: the rows it was
			 opened on are the context, not a nickname on a menu item. */
			let sender: NSMenuItem? = nil

			#expect(context.selectedNicknames(for: sender) == ["selected"])

			context.withContext(.members([clicked])) {
				#expect(context.selectedSession === session)
				#expect(context.selectedConversation === channel)
				#expect(context.selectedNicknames(for: sender) == ["clicked"])
				#expect(context.selectedMembers(for: sender).map(\.user.nickname) == ["clicked"])
				#expect(context.hasExplicitMenuContext)
			}

			#expect(context.selectedNicknames(for: sender) == ["selected"])
			#expect(context.hasExplicitMenuContext == false)
		}
	}

	@Test("A JOIN snapshot cannot act after the session starts disconnecting")
	func joinActionRechecksEligibility() async throws {
		try await withChannelMenu { controller, _, session, _ in
			session.markAsLoggedIn()
			let channel = try #require(session.findConversationOrCreate("#retry"))
			let entries = MenuItemSnapshot.validating(
				controller.mainMenuChannelMenu,
				context: MenuTargetContext(coordinator: controller, item: channel)
			)
			let join = try #require(entries.first { $0.command == .joinChannel })
			#expect(join.isEnabled)
			session.isDisconnecting = true
			#expect(join.perform {})
			#expect(session.sentLines.count == 0)
			#expect(channel.status == .parted)
		}
	}

	/** HIG: disable, do not remove.

	 Availability used to be expressed by hiding, so the menus changed shape as
	 the selection moved and nobody could learn where a command lived. State pairs
	 are the exception: Connect and Disconnect, Join and Leave, Mute and Unmute. Each
	 pair is one command in two states and showing both offers a choice that
	 does not exist. */
	@Test("Only commands with mutually exclusive states are ever hidden")
	func availabilityIsExpressedByEnablement() async throws {
		try await withChannelMenu { controller, _, _, _ in
			let menus = try [
				#require(NSApp.mainMenu),
				controller.mainMenuChannelMenu,
				controller.mainMenuDirectMenu,
				controller.userControlMenu,
				controller.transcriptGeneralMenu,
			]
			let allowedToHide: Set<MenuCommand> = [
				.connect, .connectWithoutProxy, .disconnect, .joinChannel, .leaveChannel,
				.muteUser, .unmuteUser,
			]

			var hidden: [String] = []
			for menu in menus {
				/* Only the items this application validates: AppKit owns the
				 visibility of the ones it answers itself, and it hides Enter
				 Full Screen for a window that cannot go full screen. */
				for item in Self.items(of: menu) where item.target != nil {
					_ = controller.validateMenuItem(item)
					guard let command = item.command, item.isHidden else { continue }
					if allowedToHide.contains(command) == false {
						hidden.append("\(command) (\(item.title))")
					}
				}
			}

			#expect(hidden.isEmpty, "Commands answering availability by hiding: \(hidden.sorted())")
		}
	}

	/** A sheet command took down the sheet already on screen before it checked
	 whether it could act. With nothing it could act on, the reader lost the
	 sheet and whatever they had typed into it, and nothing replaced it. */
	@Test("A sheet command that cannot act leaves the sheet on screen alone")
	func sheetCommandThatCannotActKeepsTheSheet() async throws {
		try await withChannelMenu { controller, window, _, _ in
			let owner = NSObject()
			var dismissed = false
			window.sheetModel.presentSheet(MainWindowSheet(owner: owner, content: EmptyView()) {
				dismissed = true
			})
			defer { window.sheetModel.dismissSheet(ownedBy: owner) }
			try #require(window.selectedItem == nil)

			controller.showChannelPropertiesSheet(nil)
			controller.showChannelModifyTopicSheet(nil)
			controller.showChannelModifyModesSheet(nil)
			controller.showServerChangeNicknameSheet(nil)
			controller.addChannel(nil)
			controller.showNicknameColorSheet(for: "someone")

			#expect(dismissed == false)
			#expect(window.sheetModel.presentedSheet?.owner === owner)
		}
	}

	/// A mode is a state, so the item that sets it is ticked while it is in
	/// force rather than paired with an opposite that says nothing.
	@Test("A channel mode is one ticked item, not two commands")
	func channelModesAreTicked() async throws {
		try await withChannelMenu { controller, window, session, _ in
			session.markAsLoggedIn()
			let channel = try #require(session.findConversationOrCreate("#modes"))
			channel.activate()
			window.select(channel)

			let moderated = try #require(controller.mainMenuChannelMenu.item(for: .channelModeModerated))
			_ = controller.validateMenuItem(moderated)
			#expect(moderated.state == .off)

			_ = channel.modeInfo?.updateModes("+m")
			_ = controller.validateMenuItem(moderated)
			#expect(moderated.state == .on)
			#expect(controller.context.channelModeIsSet("m"))
		}
	}

	/// The SwiftUI mirror used to drop the tick and the shortcut, so the same
	/// menu said less than the AppKit one it was built from.
	@Test("A snapshot carries the item's tick and its key equivalent")
	func snapshotCarriesStateAndShortcut() {
		let menu = NSMenu(title: "Root")
		let ticked = NSMenuItem(title: "Muted", action: nil, keyEquivalent: "m")
		ticked.keyEquivalentModifierMask = [.command, .shift]
		ticked.state = .on
		let plain = NSMenuItem(title: "Plain", action: nil, keyEquivalent: "")
		menu.addItem(ticked)
		menu.addItem(plain)

		let entries = MenuItemSnapshot.validating(menu)

		#expect(entries[0].isOn)
		#expect(entries[0].shortcut == KeyboardShortcut("m", modifiers: [.command, .shift]))
		#expect(entries[1].isOn == false)
		#expect(entries[1].shortcut == nil)
	}

	@Test("Reparented native menu items preserve mixed state, shortcuts and their original sender")
	func nativeItemsRetainDispatchAndPresentation() throws {
		let validator = MenuValidator()
		validator.disabledTitles = ["Disabled"]
		validator.hiddenTitles = ["Hidden"]
		let source = menu(["Action", "Disabled", "Hidden"], validatedBy: validator)
		let original = try #require(source.item(at: 0))
		let payload = NSObject()
		original.representedObject = payload
		original.state = .mixed
		original.keyEquivalent = "m"
		original.keyEquivalentModifierMask = [.command, .shift]
		original.toolTip = "Details"
		var selectionCount = 0
		let combined = NSMenu()
		do {
			let native = MenuContentView.nativeMenu(menu: source) { selectionCount += 1 }
			#expect(native.items.map(\.title) == ["Action", "Disabled"])
			#expect(native.item(at: 1)?.isEnabled == false)
			let item = try #require(native.item(at: 0))
			native.removeItem(item)
			combined.addItem(item)
		}
		let item = try #require(combined.item(at: 0))
		#expect(item.state == .mixed)
		#expect(item.keyEquivalent == "m")
		#expect(item.keyEquivalentModifierMask == [.command, .shift])
		#expect(item.toolTip == "Details")
		#expect(selectionCount == 0)
		#expect(try NSApp.sendAction(#require(item.action), to: item.target, from: item))
		#expect(selectionCount == 1)
		#expect(validator.invokedItems.first === original)
		#expect(validator.invokedItems.first?.representedObject as? NSObject === payload)
	}

	@Test("Keyboard sidebar menus use the selected row and background menus preserve it")
	func sidebarSelectionAndBackgroundMenus() async throws {
		try await withChannelMenu { _, window, session, _ in
			session.markAsLoggedIn()
			let channel = try #require(session.findConversationOrCreate("#keyboard"))
			channel.activate()
			window.select(channel)
			window.sidebar.filterText = ""
			let outline = SidebarOutlineView(model: window.sidebar, redirectTyping: { _ in })
			defer { outline.stopUpdates() }
			outline.apply(SidebarOutlineSnapshot(model: window.sidebar))
			let selectionMenu = try #require(outline.selectionContextMenu())
			#expect(selectionMenu.item(for: .leaveChannel)?.isEnabled == true)
			#expect(window.selectedConversation === channel)
			let background = try #require(outline.contextMenu(for: nil))
			#expect(background.item(for: .addServer) != nil)
			#expect(background.item(for: .leaveChannel) == nil)
			#expect(window.selectedConversation === channel)
		}
	}

	private static func items(of menu: NSMenu) -> [NSMenuItem] {
		menu.items.flatMap { [$0] + ($0.submenu.map(items(of:)) ?? []) }
	}

	func withChannelMenu(
		_ body: (MenuActionController, MainWindow, TestServerSession, TestServerSession) throws -> Void
	) async throws {
		let app = try #require(AppServices.delegate)
		try #require(app.applicationIsLaunched)
		let window = MainWindow(
			contentRect: NSRect(x: 100, y: 100, width: 640, height: 480),
			styleMask: .titled, backing: .buffered, defer: false
		)
		window.isReleasedWhenClosed = false
		window.tabbingMode = .disallowed
		defer {
			window.close()
		}

		// A clicked context remains valid without owning global window focus.
		let originalWindow = app.mainWindow
		let originalChatSession = app.chatSession
		let originalMenu = app.menuController
		let originalMainMenu = NSApp.mainMenu
		let originalServicesMenu = NSApp.servicesMenu
		let originalWindowsMenu = NSApp.windowsMenu
		let originalHelpMenu = NSApp.helpMenu
		let fixture = ChatEnvironmentFixture()
		let session = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let other = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		fixture.chatSession.sessions = [session, other]
		window.inputContentView.configure()
		let controller = MenuActionController()
		app.mainWindow = window
		app.chatSession = fixture.chatSession
		app.menuController = controller
		defer {
			app.mainWindow = originalWindow
			app.chatSession = originalChatSession
			app.menuController = originalMenu
			NSApp.mainMenu = originalMainMenu
			NSApp.servicesMenu = originalServicesMenu
			NSApp.windowsMenu = originalWindowsMenu
			NSApp.helpMenu = originalHelpMenu
		}
		try #require(controller.mainWindow === window)
		try #require(window.attachedSheet == nil)
		try body(controller, window, session, other)
	}

	private func menu(
		_ titles: [String],
		validatedBy validator: MenuValidator
	) -> NSMenu {
		let menu = NSMenu(title: "")
		for title in titles {
			let item = NSMenuItem(
				title: title,
				action: #selector(MenuValidator.invoke(_:)),
				keyEquivalent: ""
			)
			item.target = validator
			menu.addItem(item)
		}
		return menu
	}

	/// The menus handed to `MenuContentView` are the shared AppKit ones, whose
	/// validators hide mutually exclusive commands instead of disabling them.
	/// Rendering every item showed "Connect" beside "Disconnect".
	@Test("An item the validator hid is not rendered")
	func hiddenItemsAreDropped() {
		let validator = MenuValidator()
		validator.hiddenTitles = ["Disconnect"]

		let entries = MenuItemSnapshot.validating(menu(["Connect", "Disconnect"], validatedBy: validator))

		#expect(entries.map(\.title) == ["Connect"])
	}

	@Test("Enablement is read back from the item the validator settled")
	func enablementComesFromValidation() {
		let validator = MenuValidator()
		validator.disabledTitles = ["Kick"]

		let entries = MenuItemSnapshot.validating(menu(["Ban", "Kick"], validatedBy: validator))

		#expect(entries.count == 2)
		#expect(entries.first(where: { $0.title == "Ban" })?.isEnabled == true)
		#expect(entries.first(where: { $0.title == "Kick" })?.isEnabled == false)
	}

	/// Validation used to run from inside `body`, so every evaluation of the
	/// view mutated titles, hidden flags and submenu attachment again.
	@Test("The menu is validated once, before the content is described")
	func validationRunsOnceOutsideTheViewBody() {
		let validator = MenuValidator()
		let menu = menu(["Ban", "Kick"], validatedBy: validator)

		let entries = MenuItemSnapshot.validating(menu)
		let afterFirstPass = validator.validationCount

		#expect(entries.count == 2)
		#expect(afterFirstPass == 2)

		/* Reading the snapshot again asks AppKit nothing. */
		#expect(entries.map(\.isEnabled) == [true, true])
		#expect(validator.validationCount == afterFirstPass)
	}

	@Test("Separators and submenus keep their shape")
	func separatorsAndSubmenusAreDescribed() {
		let validator = MenuValidator()
		let parent = menu(["Client-to-Client"], validatedBy: validator)
		parent.addItem(.separator())
		parent.item(at: 0)?.submenu = menu(["Lag (PING)"], validatedBy: validator)

		let entries = MenuItemSnapshot.validating(parent)

		#expect(entries.count == 2)
		guard case let .submenu(children) = entries[0].content else {
			Issue.record("The first entry should carry a submenu")
			return
		}
		#expect(children.map(\.title) == ["Lag (PING)"])
		guard case .separator = entries[1].content else {
			Issue.record("The second entry should be a separator")
			return
		}
	}

	@Test("A hidden item inside a submenu is dropped too")
	func hiddenSubmenuItemsAreDropped() {
		let validator = MenuValidator()
		validator.hiddenTitles = ["Take Op (-o)"]

		let parent = menu(["Modes"], validatedBy: validator)
		parent.item(at: 0)?.submenu = menu(["Give Op (+o)", "Take Op (-o)"], validatedBy: validator)

		let entries = MenuItemSnapshot.validating(parent)

		guard case let .submenu(children) = entries[0].content else {
			Issue.record("The entry should carry a submenu")
			return
		}
		#expect(children.map(\.title) == ["Give Op (+o)"])
	}
}
