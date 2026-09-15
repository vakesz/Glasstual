/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import GlasstualPluginKit
import SwiftUI
import Testing

/// A validator that expresses availability the way the application's own menu
/// validators do: by hiding the item rather than by disabling it.
@MainActor
private final class MenuValidator: NSObject, NSMenuItemValidation {
	var hiddenTitles: Set<String> = []
	var disabledTitles: Set<String> = []
	private(set) var validationCount = 0

	@objc
	func invoke(_: Any?) {}

	func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
		validationCount += 1
		menuItem.isHidden = hiddenTitles.contains(menuItem.title)
		return disabledTitles.contains(menuItem.title) == false
	}
}

@MainActor
@Suite("SwiftUI rendering of AppKit menus", .serialized)
struct AppMenuContentTests {
	@Test(
		"Context JOIN retries the clicked channel after identification without reconnecting",
		arguments: [false, true]
	)
	func contextJoinAfterIdentification(otherClientSelected: Bool) async throws {
		try await withChannelMenu { controller, window, client, other in
			let coordinator = controller.actionCoordinator
			client.userNickname = "mynick"
			client.markAsLoggedIn()
			client.isConnected = true
			let channel = try #require(client.findChannelOrCreate("#retry"))
			let previousClient = otherClientSelected ? other : client
			previousClient.markAsLoggedIn()
			let previous = try #require(previousClient.findChannelOrCreate("#active"))
			previous.activate()
			window.select(previous)
			client.join(channel)
			try client.receiveNumericReply(#require(Message(
				line: ":irc.example.test 477 mynick #retry :You need to identify to a registered nick", on: client
			)))
			#expect(channel.status == .parted)

			for line in [
				":irc.example.test 900 mynick mynick!user@host account :You are now logged in",
				":irc.example.test 903 mynick :SASL authentication successful",
			] {
				try client.receiveNumericReply(#require(Message(line: line, on: client)))
			}
			try client.receiveMode(#require(Message(line: ":irc.example.test MODE mynick +r", on: client)))
			#expect(client.startup.authentication == .confirmed)
			let menu = try #require(window.serverList.menu(for: [channel.uniqueIdentifier]))
			let entries = AppMenuEntry.validating(menu.menu, context: menu.context)
			let join = try #require(entries.first { $0.item.command == .joinChannel })
			#expect(join.isEnabled)
			#expect(entries.contains { $0.item.command == .leaveChannel } == false)
			#expect(window.selectedChannel === previous)
			#expect(coordinator.selectedClient === previousClient)
			#expect(coordinator.selectedChannel === previous)

			// Revalidating the shared NSMenu must not retarget an existing snapshot.
			_ = AppMenuEntry.validating(controller.mainMenuChannelMenu)
			let performed = join.perform {
				window.serverList.selectFromSwiftUI(channel.uniqueIdentifier)
			}
			#expect(performed)
			/* Clicking the row publishes it, and the command runs against the
			 row the menu was opened on rather than against what the window was
			 showing before the click. */
			#expect(window.selectedChannel === channel)
			#expect(coordinator.selectedClient === client)
			#expect(coordinator.selectedChannel === channel)
			#expect(client.sentLines.compactMap { $0 as? String }.filter { $0.hasPrefix("JOIN ") }
				== ["JOIN #retry", "JOIN #retry"])
			#expect(other.sentLines.count == 0)
			#expect(channel.status == .joining)
			#expect(channel.errorOnLastJoinAttempt == false)
			#expect(client.isConnected && client.isLoggedIn)
			try client.receiveJoin(#require(Message(line: ":mynick!user@host JOIN :#retry", on: client)))
			#expect(channel.isActive)
			#expect(previous.isActive)
		}
	}

	@Test("Server and empty contexts never inherit the main window channel")
	func contextWithoutChannelDoesNotFallBack() async throws {
		try await withChannelMenu { controller, window, client, other in
			client.markAsLoggedIn()
			other.markAsLoggedIn()
			let channel = try #require(client.findChannelOrCreate("#selected"))
			window.select(channel)
			let coordinator = controller.actionCoordinator
			coordinator.pointedClient = client
			coordinator.pointedChannel = nil
			for item in [other as TreeItem?, nil] {
				let entries = AppMenuEntry.validating(
					controller.mainMenuChannelMenu,
					context: AppMenuContext(coordinator: coordinator, item: item)
				)
				/* Disabled, not absent: a menu whose shape follows the
				 selection is a menu nobody can learn. */
				let channelCommands = entries.filter {
					$0.item.command == .joinChannel || $0.item.command == .leaveChannel
				}
				#expect(channelCommands.isEmpty == false)
				#expect(channelCommands.allSatisfy { $0.isEnabled == false })
				coordinator.withContext(.treeItem(item)) {
					#expect(coordinator.selectedClient === item)
					#expect(coordinator.selectedChannel == nil)
					coordinator.withContext(.treeItem(channel)) {
						#expect(coordinator.selectedChannel === channel)
					}
					#expect(coordinator.selectedChannel == nil)
				}
				#expect(window.selectedChannel === channel)
				#expect(coordinator.selectedChannel === channel)
			}
		}
	}

	/// Right-clicking a member the list has not selected used to validate and
	/// run the command against whoever was selected before the click.
	@Test("A member-list menu answers for the row it was opened on, not the list's selection")
	func memberContextOverridesTheListSelection() async throws {
		try await withChannelMenu { controller, window, client, _ in
			client.markAsLoggedIn()
			let channel = try #require(client.findChannelOrCreate("#members"))
			channel.activate()
			window.select(channel)
			let membership = try #require(channel.memberInfo)
			let selected = ChannelUser(
				user: client.findUserOrCreate("selected"),
				prefixes: client.currentUserPrefixes
			)
			let clicked = ChannelUser(
				user: client.findUserOrCreate("clicked"),
				prefixes: client.currentUserPrefixes
			)
			membership.addMember(selected)
			membership.addMember(clicked)
			window.memberList.assign(to: channel)
			window.memberList.selectedMemberIDs = [selected.id]
			let coordinator = controller.actionCoordinator
			let sender = NSObject()

			#expect(coordinator.selectedNicknames(for: sender) == ["selected"])

			coordinator.withContext(.members([clicked])) {
				#expect(coordinator.selectedClient === client)
				#expect(coordinator.selectedChannel === channel)
				#expect(coordinator.selectedNicknames(for: sender) == ["clicked"])
				#expect(coordinator.selectedMembers(for: sender).map(\.user.nickname) == ["clicked"])
				#expect(coordinator.hasExplicitMenuContext)
			}

			#expect(coordinator.selectedNicknames(for: sender) == ["selected"])
			#expect(coordinator.hasExplicitMenuContext == false)
		}
	}

	@Test("A JOIN snapshot cannot act after the client starts disconnecting")
	func joinActionRechecksEligibility() async throws {
		try await withChannelMenu { controller, _, client, _ in
			client.markAsLoggedIn()
			let channel = try #require(client.findChannelOrCreate("#retry"))
			let entries = AppMenuEntry.validating(
				controller.mainMenuChannelMenu,
				context: AppMenuContext(coordinator: controller.actionCoordinator, item: channel)
			)
			let join = try #require(entries.first { $0.item.command == .joinChannel })
			#expect(join.isEnabled)
			client.isDisconnecting = true
			#expect(join.perform {})
			#expect(client.sentLines.count == 0)
			#expect(channel.status == .parted)
		}
	}

	/** HIG: disable, do not remove.

	 Availability used to be expressed by hiding, so the menus changed shape as
	 the selection moved and nobody could learn where a command lived. Two pairs
	 are the exception — Connect and Disconnect, Join and Leave — because each
	 pair is one command in two states and showing both offers a choice that
	 does not exist. */
	@Test("Only the two state pairs are ever hidden")
	func availabilityIsExpressedByEnablement() async throws {
		try await withChannelMenu { controller, _, _, _ in
			let menus = try [
				#require(NSApp.mainMenu),
				controller.mainMenuChannelMenu,
				controller.mainMenuQueryMenu,
				controller.userControlMenu,
				controller.channelViewGeneralMenu,
			]
			let allowedToHide: Set<MenuCommand> = [
				.connect, .connectWithoutProxy, .disconnect, .joinChannel, .leaveChannel,
			]

			var hidden: [String] = []
			for menu in menus {
				/* Only the items this application validates: AppKit owns the
				 visibility of the ones it answers itself, and it hides Enter
				 Full Screen for a window that cannot go full screen. */
				for item in Self.items(of: menu) where item.target != nil {
					_ = controller.actionCoordinator.validateMenuItem(item)
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
			let coordinator = controller.actionCoordinator
			let owner = NSObject()
			var dismissed = false
			window.presentationModel.presentSheet(MainWindowSheetPresentation(owner: owner, content: EmptyView()) {
				dismissed = true
			})
			defer { window.presentationModel.dismissSheet(ownedBy: owner) }
			try #require(window.selectedItem == nil)

			coordinator.showChannelPropertiesSheet(nil)
			coordinator.showChannelModifyTopicSheet(nil)
			coordinator.showChannelModifyModesSheet(nil)
			coordinator.showServerChangeNicknameSheet(nil)
			coordinator.addChannel(nil)
			coordinator.showNicknameColorSheet(for: "someone")

			#expect(dismissed == false)
			#expect(window.presentationModel.presentedSheet?.owner === owner)
		}
	}

	/// A mode is a state, so the item that sets it is ticked while it is in
	/// force rather than paired with an opposite that says nothing.
	@Test("A channel mode is one ticked item, not two commands")
	func channelModesAreTicked() async throws {
		try await withChannelMenu { controller, window, client, _ in
			client.markAsLoggedIn()
			let channel = try #require(client.findChannelOrCreate("#modes"))
			channel.activate()
			window.select(channel)

			let moderated = try #require(controller.mainMenuChannelMenu.item(for: .channelModeModerated))
			_ = controller.actionCoordinator.validateMenuItem(moderated)
			#expect(moderated.state == .off)

			_ = channel.modeInfo?.updateModes("+m")
			_ = controller.actionCoordinator.validateMenuItem(moderated)
			#expect(moderated.state == .on)
			#expect(controller.actionCoordinator.channelModeIsSet("m"))
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

		let entries = AppMenuEntry.validating(menu)

		#expect(entries[0].isOn)
		#expect(entries[0].shortcut == KeyboardShortcut("m", modifiers: [.command, .shift]))
		#expect(entries[1].isOn == false)
		#expect(entries[1].shortcut == nil)
	}

	private static func items(of menu: NSMenu) -> [NSMenuItem] {
		menu.items.flatMap { [$0] + ($0.submenu.map(items(of:)) ?? []) }
	}

	private func withChannelMenu(
		_ body: (MenuController, MainWindow, TestClient, TestClient) throws -> Void
	) async throws {
		let app = try #require(AppController.shared)
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
		let originalWorld = app.world
		let originalMenu = app.menuController
		let originalMainMenu = NSApp.mainMenu
		let originalServicesMenu = NSApp.servicesMenu
		let originalWindowsMenu = NSApp.windowsMenu
		let originalHelpMenu = NSApp.helpMenu
		let fixture = ClientEnvironmentFixture()
		let client = TestClient(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		let other = TestClient(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		fixture.world.clientList = [client, other]
		window.inputContentView.configure()
		let controller = MenuController()
		app.mainWindow = window
		app.world = fixture.world
		app.menuController = controller
		defer {
			app.mainWindow = originalWindow
			app.world = originalWorld
			app.menuController = originalMenu
			NSApp.mainMenu = originalMainMenu
			NSApp.servicesMenu = originalServicesMenu
			NSApp.windowsMenu = originalWindowsMenu
			NSApp.helpMenu = originalHelpMenu
		}
		try #require(controller.actionCoordinator.mainWindow === window)
		try #require(window.attachedSheet == nil)
		try body(controller, window, client, other)
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

	/// The menus handed to `AppMenuContent` are the shared AppKit ones, whose
	/// validators hide mutually exclusive commands instead of disabling them.
	/// Rendering every item showed "Connect" beside "Disconnect".
	@Test("An item the validator hid is not rendered")
	func hiddenItemsAreDropped() {
		let validator = MenuValidator()
		validator.hiddenTitles = ["Disconnect"]

		let entries = AppMenuEntry.validating(menu(["Connect", "Disconnect"], validatedBy: validator))

		#expect(entries.map(\.title) == ["Connect"])
	}

	@Test("Enablement is read back from the item the validator settled")
	func enablementComesFromValidation() {
		let validator = MenuValidator()
		validator.disabledTitles = ["Kick"]

		let entries = AppMenuEntry.validating(menu(["Ban", "Kick"], validatedBy: validator))

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

		let entries = AppMenuEntry.validating(menu)
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

		let entries = AppMenuEntry.validating(parent)

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

		let entries = AppMenuEntry.validating(parent)

		guard case let .submenu(children) = entries[0].content else {
			Issue.record("The entry should carry a submenu")
			return
		}
		#expect(children.map(\.title) == ["Give Op (+o)"])
	}
}
