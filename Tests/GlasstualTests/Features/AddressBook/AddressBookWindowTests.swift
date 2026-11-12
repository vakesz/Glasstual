// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("People window")
struct AddressBookWindowTests {
	private let fixture = ChatEnvironmentFixture()

	@Test("The address book destinations open the People window, the default one does not")
	func destinationsRouteToThePeopleWindow() throws {
		#expect(AddressBookDestination(.default) == nil)

		let list = try #require(AddressBookDestination(.addressBook))
		#expect(list.editRequest == nil)

		let named = try #require(AddressBookDestination(.newIgnoreEntry(hostmask: "nick")))
		guard case let .newIgnore(hostmask) = named.editRequest else {
			Issue.record("A named ignore starts on that hostmask")
			return
		}
		#expect(hostmask == "nick")

		for hostmask in [nil, ""] as [String?] {
			let blank = try #require(AddressBookDestination(.newIgnoreEntry(hostmask: hostmask)))
			guard case .newEntry(.ignore) = blank.editRequest else {
				Issue.record("An ignore with no hostmask starts on a blank ignore entry")
				return
			}
		}

		let entry = AddressBookEntry.newIgnoreEntry(forHostmask: "a!b@c")
		let edit = try #require(AddressBookDestination(.editIgnoreEntry(entry)))
		guard case let .edit(edited) = edit.editRequest else {
			Issue.record("Modify Ignore starts on the entry")
			return
		}
		#expect(edited == entry)
	}

	@Test("An accepted entry is written to the connection at once, with no Save")
	func acceptedEntryIsWrittenToTheConnection() throws {
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let book = AddressBookWindow(session: session)

		book.begin(.newIgnore(hostmask: "nick!*@example.com"))
		book.commitEditor()

		#expect(book.editor == nil)
		let saved = try #require(session.config.ignoreList.first)
		#expect(saved.hostmask == "nick!*@example.com")
		#expect(book.entries == session.config.ignoreList)
		#expect(book.selection == [saved.uniqueIdentifier])
	}

	@Test("A refused entry keeps the editor up and writes nothing")
	func refusedEntryKeepsTheEditor() {
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let book = AddressBookWindow(session: session)

		book.begin(.newEntry(.ignore))
		book.editor?.model.entry.hostmask = "not-a-hostmask"
		book.commitEditor()

		#expect(book.editor != nil)
		#expect(session.config.ignoreList.isEmpty)
	}

	@Test("Editing replaces the entry in place, and removing takes it out")
	func editAndRemove() throws {
		var config = ServerConfig()
		config.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "old!*@example.com")]
		let session = fixture.chatSession.createSession(with: config)
		let book = AddressBookWindow(session: session)
		let identifier = try #require(book.entries.first?.uniqueIdentifier)

		book.edit(identifier)
		book.editor?.model.entry.hostmask = "new!*@example.com"
		book.commitEditor()

		#expect(session.config.ignoreList.map(\.hostmask) == ["new!*@example.com"])
		#expect(session.config.ignoreList.first?.uniqueIdentifier == identifier)

		book.remove([identifier])
		#expect(session.config.ignoreList.isEmpty)
		#expect(book.selection.isEmpty)
	}

	@Test("A change made elsewhere reaches the open window")
	func externalChangesReachTheWindow() {
		let session = fixture.chatSession.createSession(with: ServerConfig())
		let book = AddressBookWindow(session: session)

		var config = session.config
		config.ignoreList = [AddressBookEntry.newIgnoreEntry(forHostmask: "x!*@example.com")]
		session.updateConfig(config)

		#expect(book.entries.map(\.hostmask) == ["x!*@example.com"])
	}
}
