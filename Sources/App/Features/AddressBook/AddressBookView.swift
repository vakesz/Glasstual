// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import SwiftUI

/** Window ▸ People: one window per connection, listed in the Window menu,
 restored with the connection it shows. */
struct AddressBookScene: Scene {
	let windows: AddressBookWindowSessions

	var body: some Scene {
		WindowGroup(
			String(localized: .AddressBook.peopleWindowTitle),
			id: ApplicationSceneID.addressBook,
			for: String.self
		) { sessionIdentifier in
			AddressBookSceneRoot(sessionIdentifier: sessionIdentifier.wrappedValue, windows: windows)
		}
		.defaultSize(width: 480, height: 420)
		.windowResizability(.contentMinSize)
	}
}

private struct AddressBookSceneRoot: View {
	let sessionIdentifier: String?
	let windows: AddressBookWindowSessions

	var body: some View {
		Group {
			if let sessionIdentifier, let book = windows.book(for: sessionIdentifier) {
				AddressBookView(book: book)
					.navigationSubtitle(book.networkName)
					.onDisappear {
						windows.didClose(for: sessionIdentifier)
					}
			} else {
				ContentUnavailableView(
					String(localized: .AddressBook.noServerTitle),
					systemImage: "person.2",
					description: Text(.AddressBook.noServerDescription)
				)
			}
		}
		.navigationTitle(String(localized: .AddressBook.peopleWindowTitle))
		.frame(minWidth: 360, minHeight: 280)
		.accessibilityIdentifier(AccessibilityIdentifier.addressBookWindow)
	}
}

/** The ignore and tracking entries of one connection.

 Double-click or Return edits the selected entry, Delete removes the selection,
 and the toolbar adds one of either kind. */
struct AddressBookView: View {
	@Bindable var book: AddressBookWindow

	var body: some View {
		List(selection: $book.selection) {
			ForEach(book.entries, id: \.uniqueIdentifier) { entry in
				VStack(alignment: .leading) {
					Text(verbatim: entry.hostmask)
					Text(entry.entryType.listTitle)
						.font(.caption)
						.foregroundStyle(.secondary)
				}
				.tag(entry.uniqueIdentifier)
			}
		}
		.listStyle(.inset)
		.accessibilityIdentifier(AccessibilityIdentifier.addressBookList)
		.overlay {
			if book.entries.isEmpty {
				ContentUnavailableView(
					String(localized: .AddressBook.emptyTitle),
					systemImage: "person.2",
					description: Text(.AddressBook.emptyDescription)
				)
			}
		}
		.onDeleteCommand { book.remove(book.selection) }
		.contextMenu(forSelectionType: String.self) { identifiers in
			if identifiers.count == 1, let identifier = identifiers.first {
				Button(.AddressBook.editEntry) { book.edit(identifier) }
				Divider()
			}
			if identifiers.isEmpty == false {
				Button(.AddressBook.removeEntry, role: .destructive) { book.remove(identifiers) }
			}
		} primaryAction: { identifiers in
			guard identifiers.count == 1, let identifier = identifiers.first else { return }
			book.edit(identifier)
		}
		.toolbar {
			ToolbarItemGroup(placement: .primaryAction) {
				/* A menu rather than a button, because an entry either
				 ignores or tracks someone and this one list holds both. */
				Menu {
					Button(.AddressBook.addIgnoreEntry) { book.begin(.newEntry(.ignore)) }
					Button(.AddressBook.addTrackingEntry) { book.begin(.newEntry(.userTracking)) }
				} label: {
					Label(String(localized: .AddressBook.addEntry), systemImage: "plus")
				}
				.help(String(localized: .AddressBook.addEntry))
				.accessibilityIdentifier(AccessibilityIdentifier.addressBookAdd)

				Button {
					book.remove(book.selection)
				} label: {
					Label(String(localized: .AddressBook.removeEntry), systemImage: "minus")
				}
				.help(String(localized: .AddressBook.removeEntry))
				.disabled(book.selection.isEmpty)
				.accessibilityIdentifier(AccessibilityIdentifier.addressBookRemove)
			}
		}
		.sheet(item: $book.editor) { editor in
			AddressBookEntryView(model: editor.model, submit: book.commitEditor, cancel: book.cancelEditor)
		}
	}
}
