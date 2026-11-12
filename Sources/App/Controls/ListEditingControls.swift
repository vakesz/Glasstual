// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** The add and remove buttons under an editable list, with an optional menu of
 the list's other commands, as System Settings draws them.

 Every editable list in the app uses this one row, so adding is always the
 plus, removing is always the minus beside it and anything else is in the
 action menu after them. Editing an item is the list's primary action --
 double-click or Return -- rather than a button of its own. A list that holds
 more than one kind of item makes the plus a menu of those kinds. */
struct ListEditingControls<AddMenu: View, Actions: View>: View {
	private let addLabel: Text
	private let removeLabel: Text
	private let canAdd: Bool
	private let canRemove: Bool
	private let add: (() -> Void)?
	private let addMenu: AddMenu?
	private let remove: () -> Void
	private let identifiers: ListEditingIdentifiers
	private let actions: Actions?

	var body: some View {
		HStack(spacing: UISpacing.tight) {
			addControl
				.disabled(canAdd == false)
				.help(addLabel)
				.accessibilityIdentifier(identifiers.add)

			Button(action: remove) {
				Label { removeLabel } icon: { Image(systemName: "minus") }
			}
			.disabled(canRemove == false)
			.help(removeLabel)
			.accessibilityIdentifier(identifiers.remove)

			if let actions {
				Menu {
					actions
				} label: {
					Label {
						Text(.Accessibility.listEditingMoreActions)
					} icon: {
						Image(systemName: "ellipsis.circle")
					}
				}
				.menuIndicator(.hidden)
				.fixedSize()
				.help(Text(.Accessibility.listEditingMoreActions))
				.accessibilityIdentifier(identifiers.actions)
			}
		}
		.labelStyle(.iconOnly)
		.buttonStyle(.borderless)
		.menuStyle(.borderlessButton)
		.frame(maxWidth: .infinity, alignment: .leading)
	}

	@ViewBuilder
	private var addControl: some View {
		let label = Label { addLabel } icon: { Image(systemName: "plus") }
		if let addMenu {
			Menu {
				addMenu
			} label: {
				label
			}
			.menuIndicator(.hidden)
			.fixedSize()
		} else {
			Button { add?() } label: { label }
		}
	}
}

extension ListEditingControls where AddMenu == EmptyView {
	/**
	 - Parameters:
	   - addLabel: What VoiceOver and the tooltip call the plus button.
	   - removeLabel: What VoiceOver and the tooltip call the minus button.
	   - actions: The list's other commands, shown in the action menu.
	 */
	init(
		addLabel: Text,
		removeLabel: Text,
		canAdd: Bool = true,
		canRemove: Bool,
		identifiers: ListEditingIdentifiers = ListEditingIdentifiers(),
		add: @escaping () -> Void,
		remove: @escaping () -> Void,
		@ViewBuilder actions: () -> Actions
	) {
		self.addLabel = addLabel
		self.removeLabel = removeLabel
		self.canAdd = canAdd
		self.canRemove = canRemove
		self.identifiers = identifiers
		self.add = add
		addMenu = nil
		self.remove = remove
		self.actions = actions()
	}
}

extension ListEditingControls where AddMenu == EmptyView, Actions == EmptyView {
	init(
		addLabel: Text,
		removeLabel: Text,
		canAdd: Bool = true,
		canRemove: Bool,
		identifiers: ListEditingIdentifiers = ListEditingIdentifiers(),
		add: @escaping () -> Void,
		remove: @escaping () -> Void
	) {
		self.addLabel = addLabel
		self.removeLabel = removeLabel
		self.canAdd = canAdd
		self.canRemove = canRemove
		self.identifiers = identifiers
		self.add = add
		addMenu = nil
		self.remove = remove
		actions = nil
	}
}

extension ListEditingControls where Actions == EmptyView {
	/// A list of several kinds of item: the plus offers the kinds as a menu.
	init(
		addLabel: Text,
		removeLabel: Text,
		canAdd: Bool = true,
		canRemove: Bool,
		identifiers: ListEditingIdentifiers = ListEditingIdentifiers(),
		@ViewBuilder addMenu: () -> AddMenu,
		remove: @escaping () -> Void
	) {
		self.addLabel = addLabel
		self.removeLabel = removeLabel
		self.canAdd = canAdd
		self.canRemove = canRemove
		self.identifiers = identifiers
		add = nil
		self.addMenu = addMenu()
		self.remove = remove
		actions = nil
	}
}

/// What an Accessibility client finds each of the row's buttons by. Empty
/// identifiers attach nothing.
struct ListEditingIdentifiers {
	var add = ""
	var remove = ""
	var actions = ""
}
