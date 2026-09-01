/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

@Suite("Menu command vocabulary")
@MainActor
struct MenuCommandTests {
	@Test("The main menu is built in code without command tags")
	func mainMenuIsProgrammatic() throws {
		let controller = TXMenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		#expect(mainMenu.items.allSatisfy { $0.tag == 0 })
		#expect(controller.mainMenuServerMenuItem?.command == .serverMenu)
		#expect(Bundle.main.path(forResource: "TXCMainMenu", ofType: "nib") == nil)
	}

	@Test("The programmatic graph carries the commands the application looks up")
	func mainMenuContainsExpectedCommands() throws {
		let controller = TXMenuController()
		let menu = try #require(NSApp.mainMenu)
		let menus = [menu, controller.mainMenuChannelMenu, controller.mainMenuQueryMenu]
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

	/// Raw values are the nib's tags. Two cases sharing one would make the
	/// second unreachable, and `MenuCommand(rawValue:)` would silently pick the
	/// first.
	@Test("Command raw values are unique")
	func rawValuesAreUnique() {
		let rawValues = MenuCommand.allCases.map(\.rawValue)
		#expect(Set(rawValues).count == rawValues.count)
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
			(.webSearch, .web),
			(.webReact, .web),
			(.addIgnore, .member),
			(.changeColor, .member),
			(.settings, .general),
			(.markAllRead, .general),
			(.queryLogs, .general),
			(.segmentedAddChannel, .general),
		]
	)
	func validationGroups(command: MenuCommand, group: MenuCommand.ValidationGroup) {
		#expect(command.validationGroup == group)
	}

	/// `changeColor` and `segmentedAddChannel` sit inside bands the old range
	/// switch claimed, which is exactly the class of mistake the enum removes.
	@Test("Grouping does not follow the tag's numeric band")
	func groupingIsNotDerivedFromBand() {
		#expect(MenuCommand.segmentedAddChannel.validationGroup == .general)
		#expect(MenuCommand.dockDisableNotifications.validationGroup == .general)
		#expect(MenuCommand.queryLogs.validationGroup == .general)
	}

	@Test("Top-level menus stay enabled before the application finishes launching")
	func topLevelMenusAlwaysValidate() {
		for command in MenuCommand.allCases where command.isTopLevelMenu {
			#expect(
				MenuValidationPolicy.validate(
					command: command,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: true,
					mainWindowIsFocused: false,
					mainWindowIsBeneathMouse: false
				)
			)
		}
		#expect(MenuCommand.allCases.count(where: \.isTopLevelMenu) == 10)
	}

	@Test("A sheet leaves the settings commands live and the channel commands dead")
	func sheetPolicy() {
		func validate(_ command: MenuCommand) -> Bool {
			MenuValidationPolicy.validate(
				command: command,
				commandSpecificResult: true,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: true,
				mainWindowIsFocused: true,
				mainWindowIsBeneathMouse: false
			)
		}

		#expect(validate(.settings))
		#expect(validate(.disableNotifications))
		#expect(validate(.joinChannel) == false)
	}

	@Test("Essential commands stay live before launch")
	func essentialCommands() {
		for command in MenuCommand.allCases where command.isEssential {
			#expect(
				MenuValidationPolicy.validate(
					command: command,
					commandSpecificResult: true,
					applicationIsLaunched: false,
					mainWindowHasAttachedSheet: false,
					mainWindowIsFocused: true,
					mainWindowIsBeneathMouse: false
				)
			)
		}
	}

	@Test("A failed command-specific check is never overridden by the policy")
	func commandSpecificFailureWins() {
		#expect(
			MenuValidationPolicy.validate(
				command: .about,
				commandSpecificResult: false,
				applicationIsLaunched: true,
				mainWindowHasAttachedSheet: false,
				mainWindowIsFocused: true,
				mainWindowIsBeneathMouse: false
			) == false
		)
	}

	@Test("Setting a command uses an identifier and leaves AppKit's tag free")
	func menuItemCommandAccessor() {
		let item = NSMenuItem()
		item.command = .webReply
		#expect(item.tag == 0)
		#expect(item.command == .webReply)

		item.command = nil
		#expect(item.command == nil)
	}

	@Test("The formatting menu keeps its own vocabulary")
	func formatterCommandsAreSeparate() {
		#expect(TextFormatterCommand.monospace.rawValue == 102)
		#expect(MenuCommand.settings.rawValue == 102)
		#expect(Set(TextFormatterCommand.allCases.map(\.rawValue)).count == TextFormatterCommand.allCases.count)
	}
}
