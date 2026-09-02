/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import AppKit
@testable import Glasstual
import Testing

/// A validator that expresses availability the way the application's own menu
/// validators do: by hiding the item rather than by disabling it.
@MainActor
private final class GLTMenuValidator: NSObject, NSMenuItemValidation {
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
@Suite("SwiftUI rendering of AppKit menus")
struct AppMenuContentTests {
	private func menu(
		_ titles: [String],
		validatedBy validator: GLTMenuValidator
	) -> NSMenu {
		let menu = NSMenu(title: "")
		for title in titles {
			let item = NSMenuItem(
				title: title,
				action: #selector(GLTMenuValidator.invoke(_:)),
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
		let validator = GLTMenuValidator()
		validator.hiddenTitles = ["Disconnect"]

		let entries = AppMenuEntry.validating(menu(["Connect", "Disconnect"], validatedBy: validator))

		#expect(entries.map(\.title) == ["Connect"])
	}

	@Test("Enablement is read back from the item the validator settled")
	func enablementComesFromValidation() {
		let validator = GLTMenuValidator()
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
		let validator = GLTMenuValidator()
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
		let validator = GLTMenuValidator()
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
		let validator = GLTMenuValidator()
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
