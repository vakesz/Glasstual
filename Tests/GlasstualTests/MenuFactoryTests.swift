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

	/** Every item the factory built, separators aside.

	 It used to skip the items that carry no `MenuCommand`, which is most of the
	 Edit menu, because macOS injects its own (Writing Tools, AutoFill, Emoji &
	 Symbols, Start Dictation) into `NSApp.mainMenu` as soon as it is installed
	 and those are the system's to translate. The graph is built uninstalled
	 instead, so there is nothing to skip and the titles and selectors of the
	 command-less items are covered too. */
	private func factoryItems(of menu: NSMenu) -> [NSMenuItem] {
		menu.items.flatMap { item -> [NSMenuItem] in
			let nested = item.submenu.map(factoryItems(of:)) ?? []
			guard item.isSeparatorItem == false else { return nested }
			return [item] + nested
		}
	}

	@Test("Every title the menu graph draws comes from the String Catalog")
	func everyMenuTitleIsLocalized() throws {
		let values = try Self.catalogValues()
		let controller = MenuController()
		let mainMenu = MenuFactory.builtMainMenu(for: controller)

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
			/* One item is deliberately untitled: the placeholder that gives
			 Navigation ▸ Channel List a submenu to hand to
			 `mainMenuNavigationChannelListMenu`, which the tree replaces
			 wholesale before anyone reads it. An empty title is not an
			 untranslated one. */
			.filter { $0.title.isEmpty == false }
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

	/** Showing and hiding the sidebars is a View command on macOS.

	 Both lived in the Window menu, which is where the system puts commands
	 about windows, not about what is inside one. */
	@Test("The sidebar toggles hang under View, with their own shortcuts")
	func sidebarTogglesLiveInTheViewMenu() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let view = try #require(mainMenu.item(for: .viewMenu)?.submenu)
		let window = try #require(mainMenu.item(for: .windowMenu)?.submenu)

		for command in [MenuCommand.toggleServerList, .toggleMemberList] {
			#expect(view.item(for: command) != nil)
			#expect(window.item(for: command) == nil)
		}

		let serverList = try #require(view.item(for: .toggleServerList))
		#expect(serverList.keyEquivalent == "s")
		#expect(serverList.keyEquivalentModifierMask == [.command, .option])

		let memberList = try #require(view.item(for: .toggleMemberList))
		#expect(memberList.keyEquivalent == "u")
		#expect(memberList.keyEquivalentModifierMask == [.command, .option])
	}

	/// Command-D is the system's own "add bookmark"-shaped shortcut and the
	/// spotlight window already owns a variant of it; searching is a find.
	@Test("Search Channels is bound to Option-Command-F")
	func searchChannelsUsesTheFindShortcut() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let search = try #require(mainMenu.item(for: .searchChannels))
		#expect(search.keyEquivalent == "f")
		#expect(search.keyEquivalentModifierMask == [.command, .option])
	}

	/** The standard editing commands are AppKit's, not this application's.

	 Each carries the selector AppKit's own Edit menu sends and no target, so
	 whatever text view is first responder both validates and performs it. */
	@Test("The Edit menu offers the standard system commands, down the responder chain")
	func editMenuCarriesTheStandardCommands() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let edit = try #require(mainMenu.item(for: .editMenu)?.submenu)

		let expected: [String: Selector] = [
			MenuStrings.Edit.pasteAndMatchStyle: #selector(NSTextView.pasteAsPlainText(_:)),
			MenuStrings.Edit.showSpellingAndGrammar: #selector(NSText.showGuessPanel(_:)),
			MenuStrings.Edit.checkSpellingWhileTyping: #selector(NSTextView.toggleContinuousSpellChecking(_:)),
			MenuStrings.Edit.smartQuotes: #selector(NSTextView.toggleAutomaticQuoteSubstitution(_:)),
			MenuStrings.Edit.makeUpperCase: #selector(NSResponder.uppercaseWord(_:)),
			MenuStrings.Edit.startSpeaking: #selector(NSTextView.startSpeaking(_:)),
		]

		let items = allItems(of: edit)
		for (title, action) in expected {
			let item = try #require(items.first { $0.title == title }, "Missing Edit item: \(title)")
			#expect(item.action == action)
			#expect(item.target == nil, "\(title) must be answered by the first responder")
		}

		let paste = try #require(items.first { $0.title == MenuStrings.Edit.pasteAndMatchStyle })
		#expect(paste.keyEquivalent == "V")
		#expect(paste.keyEquivalentModifierMask == [.command, .option, .shift])
	}

	/** Emoji & Symbols and Start Dictation are AppKit's own.

	 It adds both to the Edit menu as soon as the main menu is installed --
	 `NSDisabledCharacterPaletteMenuItem` and `NSDisabledDictationMenuItem` are
	 what suppress them, and this app sets neither -- so the two the factory
	 declared as well appeared a second time, the second copy carrying a
	 selector spelled as a string. */
	@Test("The system's own Edit items are left to AppKit to inject")
	func editMenuLeavesTheSystemItemsToAppKit() throws {
		let controller = MenuController()
		let built = try #require(MenuFactory.builtMainMenu(for: controller).item(for: .editMenu)?.submenu)
		let titles = allItems(of: built).map(\.title)

		#expect(allItems(of: built).contains {
			$0.action == #selector(NSApplication.orderFrontCharacterPalette(_:))
		} == false)
		#expect(titles.contains { $0.hasPrefix("Start Dictation") } == false)
		#expect(titles.contains { $0.hasPrefix("Emoji") } == false)
		/* What the installed menu holds is not asserted: AppKit injects into
		 `NSApp.mainMenu` every time it is set, and every suite that builds a
		 `MenuController` sets it again, so the installed graph accumulates the
		 system's items across the run. What this factory declares is the only
		 half of it this repository decides. */
	}

	/// The transcript uses the system find bar, so the Find submenu carries the
	/// standard command that seeds it from the selection.
	@Test("Find offers Use Selection for Find on Command-E")
	func findOffersUseSelectionForFind() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let item = try #require(mainMenu.item(for: .useSelectionForFind))
		#expect(item.title == MenuStrings.Edit.useSelectionForFind)
		#expect(item.keyEquivalent == "e")
		#expect(item.keyEquivalentModifierMask == .command)
		#expect(mainMenu.item(for: .find)?.submenu?.item(for: .useSelectionForFind) != nil)
	}

	/// A title that opens a sheet ends in an ellipsis, and one that only asks
	/// for confirmation does not.
	@Test("Menu titles say whether more is being asked for")
	func menuTitlesUseEllipsesForSheets() {
		for title in [
			MenuStrings.File.print,
			MenuStrings.Channel.modifyTopic,
			MenuStrings.Channel.bans,
			MenuStrings.Server.changeNickname,
			MenuStrings.Navigation.searchChannels,
		] {
			#expect(title.hasSuffix("…"), "\(title) opens a sheet, so it needs an ellipsis")
		}

		#expect(MenuStrings.Server.deleteServer.hasSuffix("…") == false)
		#expect(MenuStrings.Navigation.searchChannels.hasPrefix("Search Channels"))
	}

	private func allItems(of menu: NSMenu) -> [NSMenuItem] {
		menu.items.flatMap { item in
			[item] + (item.submenu.map(allItems(of:)) ?? [])
		}
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
	func everyMenuActionResolves() {
		let controller = MenuController()
		let mainMenu = MenuFactory.builtMainMenu(for: controller)

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

		/* A responder-chain item carries no target, so there is no one object to
		 ask -- but the selector still has to exist somewhere, which is what a
		 string-spelled one did not. Between them these three answer every
		 standard editing, window and application command the graph sends:
		 `undo:` and `redo:` are `NSWindow`'s, the text commands are
		 `NSTextView`'s, and `arrangeInFront:` is the application's. */
		let responderClasses: [AnyClass] = [NSTextView.self, NSWindow.self, NSApplication.self]

		for item in menus.flatMap(factoryItems(of:)) {
			// An item with a submenu carries AppKit's own submenuAction:.
			guard item.hasSubmenu == false, let action = item.action else { continue }
			guard let target = item.target else {
				#expect(
					responderClasses.contains { $0.instancesRespond(to: action) },
					"\(item.title) sends \(action) down the responder chain, and nothing answers it"
				)
				continue
			}
			#expect(
				(target as AnyObject).responds(to: action),
				"\(item.title) sends \(action) to an object that does not answer it"
			)
		}
	}
}
