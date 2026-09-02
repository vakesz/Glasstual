/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
import Foundation
@testable import Glasstual
import Testing

/// The menu graph used to be assembled from English literals, so the menu bar
/// could not be translated at all — and two titles a validator rewrote from the
/// catalog made it a mixed one. These pin every title to the catalog instead.
@MainActor
@Suite("Menu graph titles")
struct MenuFactoryTests {
	/// Every English value the main window's catalog holds.
	private static func catalogValues() throws -> Set<String> {
		let url = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.deletingLastPathComponent()
			.appending(path: "Sources/App/Resources/Language Files/TVCMainWindow.xcstrings")
		let catalog = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
		let strings = catalog?["strings"] as? [String: Any] ?? [:]

		var values: Set<String> = []
		for entry in strings.values {
			guard let localizations = (entry as? [String: Any])?["localizations"] as? [String: Any],
			      let english = localizations["en"] as? [String: Any],
			      let unit = english["stringUnit"] as? [String: Any],
			      let value = unit["value"] as? String
			else { continue }
			values.insert(value)
		}
		return values
	}

	/// Only the items the factory built: macOS injects its own (Writing Tools,
	/// AutoFill, Emoji & Symbols) into the Edit menu as soon as the main menu
	/// is installed, and those are the system's to translate.
	private func factoryItems(of menu: NSMenu) -> [NSMenuItem] {
		menu.items.flatMap { item -> [NSMenuItem] in
			let nested = item.submenu.map(factoryItems(of:)) ?? []
			guard item.command != nil, item.isSeparatorItem == false else { return nested }
			return [item] + nested
		}
	}

	@Test("Every title the menu graph draws comes from the String Catalog")
	func everyMenuTitleIsLocalized() throws {
		let values = try Self.catalogValues()
		let controller = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let menus = [
			mainMenu,
			controller.channelViewChannelNameMenu,
			controller.channelViewGeneralMenu,
			controller.channelViewURLMenu,
			controller.dockMenu,
			controller.mainMenuChannelMenu,
			controller.mainMenuQueryMenu,
			controller.mainWindowSegmentedControllerCellMenu,
			controller.serverListNoSelectionMenu,
			controller.userControlMenu,
		]

		let unlocalized = menus
			.flatMap(factoryItems(of:))
			.map(\.title)
			.filter { values.contains($0) == false }

		#expect(unlocalized.isEmpty, "Untranslatable menu titles: \(Set(unlocalized).sorted())")
	}

	/** Search moved out of the sidebar and into the window toolbar, so the
	 command that used to open Channel Spotlight focuses that field instead.
	 Spotlight is a scene of its own and keeps an item of its own rather than
	 being left with no way in. */
	@Test("Search focuses the toolbar field while Channel Spotlight keeps its own item")
	func searchAndChannelSpotlightAreSeparateCommands() throws {
		let controller = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let search = try #require(mainMenu.item(for: .searchChannels))
		#expect(search.action == #selector(MenuController.focusSearchField(_:)))
		#expect(search.target === controller)

		let spotlight = try #require(mainMenu.item(for: .channelSpotlight))
		#expect(spotlight.action == #selector(MenuController.showChannelSpotlightWindow(_:)))
		#expect(spotlight.title == MenuStrings.Navigation.channelSpotlight)
	}

	/// The two titles menu validation rewrites have to start out reading the
	/// same way, or the item flips wording the first time it is validated.
	@Test("The visibility toggles start on the title their validator writes")
	func visibilityTogglesStartFromTheCatalog() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		#expect(
			mainMenu.item(for: .toggleMemberList)?.title
				== MainWindowStrings.Menu.memberList(isVisible: true)
		)
		#expect(
			mainMenu.item(for: .toggleServerList)?.title
				== MainWindowStrings.Menu.serverList(isVisible: true)
		)
	}

	/// A string selector compiled whatever it was spelled, so a renamed action
	/// shipped as an item that never fired. Every action now has to resolve on
	/// the object the factory targeted.
	@Test("Every menu action resolves on the object the item targets")
	func everyMenuActionResolves() throws {
		let controller = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let menus = [
			mainMenu,
			controller.channelViewChannelNameMenu,
			controller.channelViewGeneralMenu,
			controller.channelViewURLMenu,
			controller.dockMenu,
			controller.mainMenuChannelMenu,
			controller.mainMenuQueryMenu,
			controller.mainWindowSegmentedControllerCellMenu,
			controller.serverListNoSelectionMenu,
			controller.userControlMenu,
		]

		for item in menus.flatMap(factoryItems(of:)) {
			// An item with a submenu carries AppKit's own submenuAction:, and a
			// responder-chain command carries no target to check it against.
			guard item.hasSubmenu == false, let action = item.action, let target = item.target else {
				continue
			}
			#expect(
				(target as AnyObject).responds(to: action),
				"\(item.title) sends \(action) to an object that does not answer it"
			)
		}
	}
}
