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
			.appending(path: "Sources/App/Features/MainWindow/MainWindow.xcstrings")
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
			controller.serverListNoSelectionMenu,
			controller.userControlMenu,
		]

		let unlocalized = menus
			.flatMap(factoryItems(of:))
			/* Two items are deliberately untitled: the placeholders that give
			 Navigation ▸ Channel List and Format submenus to hand to the tree
			 and to the window's formatter, both of which replace them wholesale
			 before anyone reads them. An empty title is not an untranslated
			 one. */
			.filter { $0.title.isEmpty == false }
			/* The transcript's Search item names whichever service the system
			 is set to use, dropped into `search-provider-menu-title` in
			 the Application catalog rather than held whole in this one. */
			.filter { $0.command != .webSearch }
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
		#expect(search.action == #selector(MenuActionController.focusSearchField(_:)))
		#expect(search.target === controller.actionCoordinator)

		let spotlight = try #require(mainMenu.item(for: .channelSpotlight))
		#expect(spotlight.action == #selector(MenuActionController.showChannelSpotlightWindow(_:)))
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

		/* Control-Command-S shows and hides the sidebar in Finder, Mail, Notes
		 and Freeform; Option-Command-I is the system's inspector shortcut, and
		 the member list is one. */
		let serverList = try #require(view.item(for: .toggleServerList))
		#expect(serverList.keyEquivalent == "s")
		#expect(serverList.keyEquivalentModifierMask == [.command, .control])

		let memberList = try #require(view.item(for: .toggleMemberList))
		#expect(memberList.keyEquivalent == "i")
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

		/* Shift is in the modifier mask and never in the character: spelling it
		 three different ways across the graph is what made it unreadable. */
		let paste = try #require(items.first { $0.title == MenuStrings.Edit.pasteAndMatchStyle })
		#expect(paste.keyEquivalent == "v")
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
			MenuStrings.Navigation.channelSpotlight,
			MenuStrings.Member.addIgnore,
			MenuStrings.Member.setVirtualHost,
		] {
			#expect(title.hasSuffix("…"), "\(title) opens a sheet, so it needs an ellipsis")
		}

		/* A confirmation alert is not more input being asked for, and the
		 sidebar filter is a field that is already on screen. */
		#expect(MenuStrings.Server.deleteServer.hasSuffix("…") == false)
		#expect(MenuStrings.Navigation.searchChannels.hasSuffix("…") == false)
	}

	/** Formatting is a menu of its own, with the shortcuts every macOS text
	 editor uses. The commands used to exist only in the input field's context
	 menu, with no key equivalent and no menu-bar home. */
	@Test("The Format menu carries the three standard text shortcuts")
	func formatMenuCarriesTheStandardShortcuts() throws {
		let controller = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let format = try #require(mainMenu.item(for: .formatMenu))
		#expect(format.title == MenuStrings.MenuBar.format)

		/* The window's formatter fills the submenu in; before that it is the
		 placeholder the factory leaves behind. */
		let formatter = TextViewIRCFormattingMenu()
		let menu = try #require(formatter.makeMenu())
		controller.mainMenuFormatMenuItem?.submenu = menu

		let expected: [(TextFormatterCommand, String)] = [(.bold, "b"), (.italics, "i"), (.underline, "u")]
		for (command, key) in expected {
			let item = try #require(menu.items.first { $0.tag == command.rawValue })
			#expect(item.keyEquivalent == key)
			#expect(item.keyEquivalentModifierMask == .command)
		}

		/* The same menu, so the input field's context menu offers the same
		 commands with the same shortcuts. */
		let contextMenu = try #require(formatter.formatterMenu.submenu)
		#expect(contextMenu.items.map(\.tag) == menu.items.map(\.tag))
	}

	/** The Window menu names windows; a digit that means "the fourth channel in
	 whatever order the sidebar happens to be in" does not. */
	@Test("The Window menu owns the Command-digit shortcuts")
	func windowMenuOwnsTheDigitShortcuts() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		let expected: [(MenuCommand, String)] = [
			(.mainWindow, "1"), (.addressBook, "2"), (.viewLogs, "3"), (.highlightList, "4"),
		]
		for (command, key) in expected {
			let item = try #require(mainMenu.item(for: command))
			#expect(item.keyEquivalent == key)
			#expect(item.keyEquivalentModifierMask == .command)
		}

		let transfers = try #require(mainMenu.item(for: .fileTransfers))
		#expect(transfers.keyEquivalent == "l")
		#expect(transfers.keyEquivalentModifierMask == [.command, .option])

		/* "Ignore List" opened the address book, which is where ignores live:
		 one command with two names and two shortcuts. */
		#expect(MenuCommand.allCases.contains { $0 == .addressBook })
		#expect(mainMenu.items.contains { $0.title == "Ignore List" } == false)
	}

	/// Importing and exporting are file commands, not help topics.
	@Test("Settings import and export live in the File menu")
	func settingsTransferLivesInTheFileMenu() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let file = try #require(mainMenu.item(for: .fileMenu)?.submenu)
		let help = try #require(mainMenu.item(for: .helpMenu)?.submenu)

		#expect(file.item(for: .importSettings) != nil)
		#expect(file.item(for: .exportSettings) != nil)
		#expect(help.item(for: .importSettings) == nil)
		#expect(help.item(for: .exportSettings) == nil)
		#expect(MenuStrings.File.importSettings == "Import Settings…")
		#expect(MenuStrings.File.exportSettings == "Export Settings…")
	}

	/** Muting is an application-wide mode, and a mode is ticked rather than
	 renamed. It used to sit in the File menu under two different names. */
	@Test("The mute toggles sit in the application menu")
	func muteTogglesLiveInTheApplicationMenu() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let application = try #require(mainMenu.item(for: .applicationMenu)?.submenu)
		let file = try #require(mainMenu.item(for: .fileMenu)?.submenu)

		#expect(application.item(for: .muteNotifications) != nil)
		#expect(application.item(for: .muteNotificationSounds) != nil)
		#expect(file.item(for: .muteNotifications) == nil)
		#expect(MenuStrings.Notifications.muteNotifications == "Mute Notifications")
	}

	/// A menu whose shape follows the selection cannot be learned, so the
	/// Channel and Query menus are installed once and stay installed.
	@Test("The Channel and Query menus are always in the menu bar")
	func channelAndQueryMenusStayInstalled() throws {
		let controller = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)

		#expect(mainMenu.item(for: .channelMenu)?.submenu === controller.mainMenuChannelMenu)
		#expect(mainMenu.item(for: .queryMenu)?.submenu === controller.mainMenuQueryMenu)
		#expect(mainMenu.item(for: .channelMenu)?.isHidden == false)
		#expect(mainMenu.item(for: .queryMenu)?.isHidden == false)
	}

	/// AppKit would append its own list of open windows to a menu that already
	/// names every window this application opens.
	@Test("The Window menu is not handed to AppKit to fill in")
	func windowMenuIsNotDelegatedToAppKit() {
		_ = MenuController()
		#expect(NSApp.windowsMenu == nil)
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

	/// Option-Command-D hides and shows the Dock everywhere on the Mac, so the
	/// item bound to it never received the key.
	@Test("Channel Spotlight answers Shift-Command-O, the key of Xcode's Open Quickly")
	func channelSpotlightUsesOpenQuicklyShortcut() throws {
		_ = MenuController()
		let spotlight = try #require(NSApp.mainMenu?.item(for: .channelSpotlight))

		#expect(spotlight.keyEquivalent == "o")
		#expect(spotlight.keyEquivalentModifierMask == [.command, .shift])
	}

	/// Command-? opens the Help menu's search field, and people press it out of
	/// habit. It opened a network connection to a public channel instead.
	@Test("Connect to Help Channel leaves Command-? to the Help menu")
	func helpChannelHasNoShortcut() throws {
		_ = MenuController()
		let help = try #require(NSApp.mainMenu?.item(for: .connectToHelpChannel))

		#expect(help.keyEquivalent.isEmpty)
	}

	/// AppKit swaps in an alternate whose modifiers differ from the primary's.
	/// Connect has none, so an alternate on Option-Command waited for Command.
	@Test("Option alone reveals Connect Without Proxy in place of Connect")
	func connectWithoutProxyIsTheOptionAlternate() throws {
		_ = MenuController()
		let mainMenu = try #require(NSApp.mainMenu)
		let connect = try #require(mainMenu.item(for: .connect))
		let withoutProxy = try #require(mainMenu.item(for: .connectWithoutProxy))

		#expect(withoutProxy.isAlternate)
		#expect(withoutProxy.keyEquivalent == connect.keyEquivalent)
		#expect(connect.keyEquivalentModifierMask.isEmpty)
		#expect(withoutProxy.keyEquivalentModifierMask == .option)
	}

	/// Channel ▸ View Logs and Query ▸ Query Logs both answered Shift-Command-L,
	/// which left AppKit to pick one of them.
	@Test("No two menu-bar commands share a shortcut")
	func menuBarShortcutsAreUnique() throws {
		let controller = MenuController()
		let formatMenu = try #require(TextViewIRCFormattingMenu().makeMenu())
		let menus = [
			MenuFactory.builtMainMenu(for: controller),
			controller.mainMenuChannelMenu,
			controller.mainMenuQueryMenu,
			formatMenu,
		]

		var owners: [String: [String]] = [:]
		for item in menus.flatMap(allItems(of:))
			where item.keyEquivalent.isEmpty == false && item.isAlternate == false
		{
			let modifiers = item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask)
			owners["\(modifiers.rawValue) \(item.keyEquivalent.lowercased())", default: []].append(item.title)
		}

		let shared = owners.values.filter { $0.count > 1 }
		#expect(shared.isEmpty, "Shortcuts with more than one command: \(shared)")
	}

	/// The Channel and Query menus hang in the menu bar, where macOS draws no
	/// images, and the symbol pass drew them there anyway.
	@Test("The menu bar's Channel and Query menus carry no symbols")
	func menuBarChannelAndQueryMenusAreDrawnPlain() throws {
		let controller = try #require(AppServices.delegate?.menuController)

		for menu in [controller.mainMenuChannelMenu, controller.mainMenuQueryMenu] {
			#expect(allItems(of: menu).allSatisfy { $0.image == nil })
		}
	}
}
