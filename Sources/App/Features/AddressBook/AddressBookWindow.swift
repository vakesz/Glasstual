// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/// What a command asks the People window to start on.
enum AddressBookEditRequest {
	/// A new entry of the kind given.
	case newEntry(AddressBookEntryKind)
	/// A new ignore, pre-filled with the hostmask `/ignore` collected.
	case newIgnore(hostmask: String)
	/// The entry the member menu asked to modify.
	case edit(AddressBookEntry)
}

/** Where a command that used to open Server Properties at its address book
 opens the People window, and what it starts on there. `nil` for the
 destinations Server Properties still shows. */
struct AddressBookDestination {
	let editRequest: AddressBookEditRequest?

	init?(_ destination: ServerPropertiesDestination) {
		switch destination {
		case .default:
			return nil
		case .addressBook:
			editRequest = nil
		case let .newIgnoreEntry(hostmask):
			editRequest = if let hostmask, hostmask.isEmpty == false {
				.newIgnore(hostmask: hostmask)
			} else {
				.newEntry(.ignore)
			}
		case let .editIgnoreEntry(entry):
			editRequest = .edit(entry)
		}
	}
}

/** The People windows the application has open, one per connection.

 The scene bridge installs and opens the windows; what each one shows belongs
 to this feature. */
@MainActor
final class AddressBookWindowSessions {
	private let scenes: ApplicationScenes
	private var windows = SceneSessions<String, AddressBookWindow>()

	init(scenes: ApplicationScenes = AppServices.scenes) {
		self.scenes = scenes
	}

	/// Opens `session`'s People window, or brings it forward, starting on
	/// `request` when one is given.
	func open(for session: ServerSession, request: AddressBookEditRequest? = nil) {
		let sessionIdentifier = session.uniqueIdentifier
		let book = windows.open(sessionIdentifier) { AddressBookWindow(session: session) }
		if let request {
			book.begin(request)
		}
		scenes.open(ApplicationSceneID.addressBook, value: sessionIdentifier)
	}

	/// What the window for `sessionIdentifier` shows, made on the spot for a
	/// window the system restores on its own.
	func book(for sessionIdentifier: String) -> AddressBookWindow? {
		if let existing = windows[sessionIdentifier] {
			return existing
		}
		guard let session = AppServices.chatSession?.findSession(withId: sessionIdentifier) else {
			return nil
		}

		return windows.open(sessionIdentifier) { AddressBookWindow(session: session) }
	}

	/// A connection that is being taken away takes its People window with it.
	func close(for sessionIdentifier: String) {
		guard windows.close(sessionIdentifier) != nil else { return }
		scenes.dismiss(ApplicationSceneID.addressBook, value: sessionIdentifier)
	}

	func didClose(for sessionIdentifier: String) {
		windows.close(sessionIdentifier)
	}
}

/// The editor sheet the People window has up, for one entry.
struct AddressBookEntryEditor: Identifiable {
	let id = UUID()
	let model: AddressBookEntryModel
}

/** One connection's ignored and tracked people, as a window of its own.

 Changes are written to the connection as they are made, the way a list in a
 window works on the Mac: there is no Save, and the window stays open beside
 the conversation. A change made elsewhere -- `/ignore`, the member menu,
 Server Properties -- reaches the list as soon as the connection takes it. */
@MainActor
@Observable
final class AddressBookWindow {
	let session: ServerSession

	private(set) var entries: [AddressBookEntry]
	var selection: Set<String> = []
	/// The entry being edited, while its sheet is up.
	var editor: AddressBookEntryEditor?

	@ObservationIgnored private let notifications = NotificationSubscriptions()

	init(session: ServerSession) {
		self.session = session
		entries = session.config.ignoreList
		notifications.observe(ServerSessionConfigWasUpdated.self, of: session) { [weak self] message in
			self?.reload(from: message.subject.config.ignoreList)
		}
	}

	var networkName: String {
		session.networkNameAlt
	}

	/// The one selected entry, which is what Edit works on.
	var selectedEntry: AddressBookEntry? {
		guard selection.count == 1, let id = selection.first else { return nil }
		return entries.first { $0.uniqueIdentifier == id }
	}

	func begin(_ request: AddressBookEditRequest) {
		switch request {
		case let .newEntry(kind):
			editor = AddressBookEntryEditor(model: AddressBookEntryModel(entryType: kind))
		case let .newIgnore(hostmask):
			editor = AddressBookEntryEditor(model: AddressBookEntryModel(entry: .newIgnoreEntry(forHostmask: hostmask)))
		case let .edit(entry):
			let current = entries.first { $0.uniqueIdentifier == entry.uniqueIdentifier } ?? entry
			selection = [current.uniqueIdentifier]
			editor = AddressBookEntryEditor(model: AddressBookEntryModel(entry: current))
		}
	}

	func edit(_ identifier: String) {
		guard let entry = entries.first(where: { $0.uniqueIdentifier == identifier }) else { return }
		begin(.edit(entry))
	}

	/// Writes the edited entry into the list, replacing the entry it was, and
	/// closes the editor. A refused entry keeps the editor up with its message.
	func commitEditor() {
		guard let editor, let entry = editor.model.validatedEntry() else { return }

		var updated = entries
		if let index = updated.firstIndex(where: { $0.uniqueIdentifier == entry.uniqueIdentifier }) {
			updated[index] = entry
		} else {
			updated.append(entry)
		}
		write(updated)
		selection = [entry.uniqueIdentifier]
		self.editor = nil
	}

	func cancelEditor() {
		editor = nil
	}

	func remove(_ identifiers: Set<String>) {
		guard identifiers.isEmpty == false else { return }
		write(entries.filter { identifiers.contains($0.uniqueIdentifier) == false })
		selection.subtract(identifiers)
	}

	private func reload(from list: [AddressBookEntry]) {
		guard list != entries else { return }
		entries = list
		selection.formIntersection(list.map(\.uniqueIdentifier))
	}

	/// The connection is what saves the list, the same way `/ignore` changes it.
	private func write(_ list: [AddressBookEntry]) {
		var config = session.config
		config.ignoreList = list
		session.updateConfig(config)
		session.chatSession?.save()
		reload(from: session.config.ignoreList)
	}
}
