// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@Suite("Menu command vocabulary")
@MainActor
struct MenuCommandTests {
	@Test("The main menu is built in code without command tags")
	func mainMenuIsProgrammatic() throws {
		let controller = MenuActionController()
		let mainMenu = try #require(NSApp.mainMenu)
		#expect(mainMenu.items.allSatisfy { $0.tag == 0 })
		#expect(controller.mainMenuServerMenuItem?.command == .serverMenu)
	}

	@Test("The programmatic graph carries the commands the application looks up")
	func mainMenuContainsExpectedCommands() throws {
		let controller = MenuActionController()
		let menu = try #require(NSApp.mainMenu)
		let menus = [menu, controller.mainMenuChannelMenu, controller.mainMenuDirectMenu]
		// A sample from each validation group, so a renumbered nib is caught.
		let expected: [MenuCommand] = [
			.applicationMenu, .settings, .closeWindow, .paste, .markAllRead,
			.connect, .serverProperties, .joinChannel, .bans, .toggleMemberList,
			.mainWindow, .highlightList, .developerMode,
		]
		for command in expected {
			#expect(menus.contains { $0.item(for: command) != nil }, "\(command) is missing from the menu graph")
		}
	}

	@Test("Every symbol the menus draw exists in the system catalog")
	func symbolNamesResolve() {
		let unavailable = MenuCommand.symbolNames.values.filter {
			NSImage(systemSymbolName: $0, accessibilityDescription: $0) == nil
		}
		#expect(unavailable.isEmpty, "Unavailable symbols: \(unavailable.sorted())")
	}

	/// The validator used to be chosen by the tag's numeric band, so a command
	/// filed in the wrong hundred silently got the wrong checks. These assert
	/// the explicit mapping that replaced it.
	@Test(
		"Commands route to the validator that owns them",
		arguments: [
			(MenuCommand.connect, MenuCommand.ValidationGroup.server),
			(.deleteServer, .server),
			(.joinChannel, .channel),
			(.quiets, .channel),
			(.toggleMemberList, .window),
			(.highlightList, .window),
			(.webSearch, .transcript),
			(.transcriptReact, .transcript),
			(.addIgnore, .member),
			(.changeColor, .member),
			(.settings, .general),
			(.markAllRead, .general),
			(.queryLogs, .general),
		]
	)
	func validationGroups(command: MenuCommand, group: MenuCommand.ValidationGroup) {
		#expect(command.validationGroup == group)
	}

	/// `muteNotifications` and `queryLogs` sit inside bands the old range
	/// switch claimed, which is exactly the class of mistake the enum removes.
	@Test("Grouping does not follow the tag's numeric band")
	func groupingIsNotDerivedFromBand() {
		#expect(MenuCommand.muteNotifications.validationGroup == .general)
		#expect(MenuCommand.queryLogs.validationGroup == .general)
	}

	/** A command offered in two menus is one command.

	 Each of these used to carry a second case named for its placement -- a
	 `dockMuteNotifications` beside `muteNotifications`, a `transcriptCopy`
	 beside `copy` -- which gave one command two validators to keep in
	 agreement. The placement now lives on the factory's entry, so the same
	 identity has to be reachable from both menus. */
	@Test("The same command is offered from both of its menus")
	func placementDoesNotForkIdentity() throws {
		let controller = MenuActionController()
		let mainMenu = try #require(NSApp.mainMenu)

		for command in [MenuCommand.changeNickname, .copy, .paste, .queryLogs] {
			#expect(controller.transcriptGeneralMenu.item(for: command) != nil, "\(command) is missing from the transcript menu")
		}
		#expect(mainMenu.item(for: .changeNickname) != nil)
		#expect(mainMenu.item(for: .copy) != nil)
		#expect(controller.mainMenuDirectMenu.item(for: .queryLogs) != nil)
		#expect(controller.sidebarNoSelectionMenu.item(for: .addServer) != nil)
		#expect(controller.dockMenu.item(for: .muteNotifications) != nil)
		#expect(controller.dockMenu.item(for: .muteNotificationSounds) != nil)
	}

	/// The menu bar's own titles are the factory's table, not a second list.
	@Test("Top-level menus are the ones the factory hangs in the bar")
	func topLevelCommandsFollowTheFactory() {
		let controller = MenuActionController()
		let mainMenu = MenuGraph.builtMainMenu(for: controller)
		let titles = Set(mainMenu.items.compactMap(\.command))

		#expect(MenuGraph.topLevelCommands == titles)
		/* A closure rather than a key path: `\.isTopLevelMenu` reads a main-actor
		 property, which through a `rethrows` generic is a call that can throw. */
		#expect(titles.allSatisfy { command in command.isTopLevelMenu })
	}

	@Test("Top-level menus stay enabled before the application finishes launching")
	func topLevelMenusAlwaysValidate() {
		for command in MenuCommand.allCases where command.isTopLevelMenu {
			#expect(
				MenuItemValidator.isAvailable(
					command: command,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: true,
					mainWindowIsFocused: false,
					hasExplicitMenuContext: false
				)
			)
		}
		#expect(MenuCommand.allCases.count(where: { $0.isTopLevelMenu }) == 11)
	}

	@Test("A sheet leaves the settings commands live and the channel commands dead")
	func sheetPolicy() {
		func validate(_ command: MenuCommand) -> Bool {
			MenuItemValidator.isAvailable(
				command: command,
				commandSpecificResult: true,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: true,
				mainWindowIsFocused: true,
				hasExplicitMenuContext: false
			)
		}

		#expect(validate(.settings))
		#expect(validate(.muteNotifications))
		#expect(validate(.joinChannel) == false)
	}

	@Test("Essential commands stay live before launch")
	func essentialCommands() {
		for command in MenuCommand.allCases where command.isEssential {
			#expect(
				MenuItemValidator.isAvailable(
					command: command,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: false,
					mainWindowIsFocused: true,
					hasExplicitMenuContext: false
				)
			)
		}
	}

	@Test("A clicked context remains usable without focus but never bypasses sheets or eligibility")
	func contextDoesNotBypassSafety() {
		for (eligible, launched, sheet, expected) in [
			(true, true, false, true),
			(false, true, false, false),
			(true, false, false, false),
			(true, true, true, false),
		] {
			#expect(MenuItemValidator.isAvailable(
				command: .joinChannel, commandSpecificResult: eligible,
				applicationIsLaunched: launched, mainWindowHasAttachedSheet: sheet,
				mainWindowIsFocused: false,
				hasExplicitMenuContext: true
			) == expected)
		}
	}

	@Test("A failed command-specific check is never overridden by the policy")
	func commandSpecificFailureWins() {
		#expect(
			MenuItemValidator.isAvailable(
				command: .about,
				commandSpecificResult: false,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: false,
				mainWindowIsFocused: true,
				hasExplicitMenuContext: false
			) == false
		)
	}

	@Test("Setting a command uses an identifier and leaves AppKit's tag free")
	func menuItemCommandAccessor() {
		let item = NSMenuItem()
		item.command = .transcriptReply
		#expect(item.tag == 0)
		#expect(item.command == .transcriptReply)

		item.command = nil
		#expect(item.command == nil)
	}

	/// The formatting menu's commands are real AppKit tags; a `MenuCommand` is a
	/// string in the item's identifier, so the two cannot collide at all.
	@Test("Every formatting tag is its own")
	func formatterCommandsAreSeparate() {
		#expect(Set(TextFormatterCommand.allCases.map(\.rawValue)).count == TextFormatterCommand.allCases.count)
	}

	/// Settings stayed dimmed until the launch sequence finished, although
	/// nothing in it waits on the rest of launch.
	@Test("Settings, About and Welcome open before launching finishes", arguments: [
		MenuCommand.settings, .about, .welcome,
	])
	func applicationCommandsOpenBeforeLaunchFinishes(command: MenuCommand) {
		#expect(MenuItemValidator.isAvailable(
			command: command,
			commandSpecificResult: true,
			applicationIsLaunched: false,
			mainWindowHasAttachedSheet: false,
			mainWindowIsFocused: true,
			hasExplicitMenuContext: false
		))
	}

	/// A switch names what the next press does, not the state it is in.
	@Test("The member list title follows the pane's state")
	func memberListTitleFollowsState() {
		let shown = MenuCommand.memberListTitle(isVisible: true)
		let hidden = MenuCommand.memberListTitle(isVisible: false)

		#expect(shown != hidden)
		#expect(shown.isEmpty == false)
		#expect(hidden.isEmpty == false)
	}
}
