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

import CocoaExtensions
import Foundation
@testable import Glasstual
import SwiftUI
import Testing

/// The endpoint table used to get all of this from Cocoa Bindings: the address
/// and port were validated by `NSValidatesImmediately` reaching the cell view's
/// `validateValue(_:forKey:)`, and the checkbox moved the port through KVC on a
/// shared reference box. Both are plain functions over the value now, so both
/// can be stated as tests.
@Suite("Server endpoint list")
struct ServerEndpointListSheetTests {
	// MARK: - Validation

	@Test(
		"An address that names a host is accepted",
		arguments: ["irc.example.com", "localhost", "127.0.0.1", "example-server.net"]
	)
	func validAddressesAreAccepted(address: String) {
		#expect(ServerEndpointValidation.validatedAddress(address) == address)
	}

	@Test(
		"An address that is empty or holds a separator is rejected",
		arguments: ["", "irc example.com", "irc.example.com/path", "irc:6667"]
	)
	func invalidAddressesAreRejected(address: String) {
		#expect(ServerEndpointValidation.validatedAddress(address) == nil)
	}

	@Test("A port inside the range is accepted", arguments: ["1", "6667", "6697", "65535"])
	func validPortsAreAccepted(port: String) {
		#expect(ServerEndpointValidation.validatedPort(port) == UInt16(port))
	}

	@Test(
		"A port that is empty, not a number or out of range is rejected",
		arguments: ["", "0x1BCB", "65536", "99999", "-1", "six-six-six-seven"]
	)
	func invalidPortsAreRejected(port: String) {
		#expect(ServerEndpointValidation.validatedPort(port) == nil)
	}

	/** A refused row used to throw an `NSError` carrying a domain, a code, a
	 description and a recovery suggestion, none of which anything read: the
	 sheet caught it, looked at the code, and showed a string of its own. The
	 fault says which field, and carries the message the sheet shows. */
	@Test("A refused row names the field that refused it, and what to do about it")
	func aRefusedRowNamesItsFault() {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "not a host", serverPort: 6667),
			Server(serverAddress: "irc.example.com", serverPort: 6667),
		])
		model.port(for: model.entries[1].id).wrappedValue = "70000"

		#expect(model.validatedServers() == nil)
		#expect(model.faults == [.address, .port])
		#expect(ServerEndpointFault.address.message.isEmpty == false)
		#expect(ServerEndpointFault.port.message.isEmpty == false)
		// Selecting the first refused row is what points at the message.
		#expect(model.selectedID == model.entries[0].id)
	}

	/// A column of a `Table` hands back the row rather than a binding into the
	/// list, so the editors take theirs from the model by identity.
	@Test("An editor writes through to the row it belongs to")
	func editorsWriteThroughByIdentity() {
		let model = ServerEndpointListModel()
		model.replace(with: [Server(serverAddress: "irc.example.com", serverPort: 6667)])
		let id = model.entries[0].id

		model.address(for: id).wrappedValue = "irc.other.example"
		model.port(for: id).wrappedValue = "7000"
		model.password(for: id).wrappedValue = "hunter2"
		model.isSecured(for: id).wrappedValue = true

		#expect(model.entries[0].address == "irc.other.example")
		#expect(model.entries[0].password == "hunter2")
		#expect(model.entries[0].prefersSecuredConnection)
		// The transport moved a default port, and 7000 is not one.
		#expect(model.entries[0].port == "7000")
		#expect(model.address(for: "no-such-endpoint").wrappedValue.isEmpty)
	}

	// MARK: - The port that follows the transport

	@Test("Securing a connection on the plain-text port moves it to the secure one")
	func securingMovesTheDefaultPort() {
		let server = Server(serverAddress: "irc.example.com", serverPort: 6667)

		let secured = ServerEndpointValidation.server(server, preferringSecuredConnection: true)

		#expect(secured.prefersSecuredConnection)
		#expect(secured.serverPort == 6697)
	}

	@Test("Unsecuring a connection on the secure port moves it back")
	func unsecuringMovesTheDefaultPortBack() {
		let server = Server(
			serverAddress: "irc.example.com",
			serverPort: 6697,
			prefersSecuredConnection: true
		)

		let plain = ServerEndpointValidation.server(server, preferringSecuredConnection: false)

		#expect(plain.prefersSecuredConnection == false)
		#expect(plain.serverPort == 6667)
	}

	@Test(
		"A port that is neither default was chosen deliberately and is left alone",
		arguments: [UInt16(7000), UInt16(1), UInt16(65535)]
	)
	func aChosenPortSurvivesTheTransportChange(port: UInt16) {
		let server = Server(serverAddress: "irc.example.com", serverPort: port)

		let secured = ServerEndpointValidation.server(server, preferringSecuredConnection: true)
		#expect(secured.serverPort == port)
		#expect(secured.prefersSecuredConnection)

		let plain = ServerEndpointValidation.server(secured, preferringSecuredConnection: false)
		#expect(plain.serverPort == port)
		#expect(plain.prefersSecuredConnection == false)
	}

	@Test("Switching the transport keeps the endpoint's identity and the rest of it")
	func switchingTransportKeepsIdentity() {
		var server = Server(serverAddress: "irc.example.com", serverPort: 6667)
		server.pendingServerPassword = .set("hunter2")

		let secured = ServerEndpointValidation.server(server, preferringSecuredConnection: true)

		#expect(secured.uniqueIdentifier == server.uniqueIdentifier)
		#expect(secured.serverAddress == server.serverAddress)
		#expect(secured.pendingServerPassword == .set("hunter2"))
	}

	// MARK: - The list the sheet edits

	@Test("An endpoint is added, edited by identity, and removed by identity")
	func entriesRoundTrip() throws {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "irc.one.example", serverPort: 6667),
			Server(serverAddress: "irc.two.example", serverPort: 6667),
		])
		#expect(model.entries.count == 2)

		model.addEntry()
		#expect(model.entries.count == 3)
		#expect(model.selectedID == model.entries[2].id)

		/* An edit finds its row by identity, because the table hands back an
		 identifier rather than a position. */
		let editedID = model.entries[1].id
		let index = try #require(model.entries.firstIndex { $0.id == editedID })
		model.entries[index].port = "7000"
		model.portDidChange(for: editedID)

		/* The blank row the add button made, then the first endpoint. */
		model.removeSelection()
		#expect(model.selectedID == nil)
		model.selectedID = model.entries[0].id
		model.removeSelection()

		let submitted = try #require(model.validatedServers())
		#expect(submitted.map(\.uniqueIdentifier) == [editedID])
		#expect(submitted.map(\.serverPort) == [7000])
	}

	/** A draft shows its endpoint's stored secret only once the one keychain read
	 lands, so an untouched row is showing an empty field for a password it has.
	 Submitting that as an edit — `.edited("")`, which is `.cleared` — deleted
	 the password of every row the person had not typed into, a list they only
	 reordered included. */
	@Test("An endpoint nobody typed into asks for no change to its secret")
	@MainActor
	func untouchedEndpointsKeepTheirSecrets() throws {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "irc.one.example", serverPort: 6667),
			Server(serverAddress: "irc.two.example", serverPort: 6667),
		])

		#expect(model.entries.allSatisfy { $0.passwordWasEdited == false })
		model.entries[1].password = "typed"

		let submitted = try #require(model.validatedServers())
		#expect(submitted[0].pendingServerPassword == .unchanged)
		#expect(submitted[1].pendingServerPassword == .set("typed"))

		// Emptying a field is still what asks for the item to go.
		model.entries[1].password = ""
		let emptied = try #require(model.validatedServers())
		#expect(emptied[1].pendingServerPassword == .cleared)
	}

	/// An edit the parent sheet already collected reaches the draft as the field
	/// contents and comes back unchanged when nobody typed over it.
	@Test("An endpoint carrying an unflushed edit hands it back as it was")
	@MainActor
	func unflushedEndpointEditsSurviveUntouched() throws {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "irc.one.example", serverPort: 6667, pendingServerPassword: .set("hunter2")),
			Server(serverAddress: "irc.two.example", serverPort: 6667, pendingServerPassword: .cleared),
		])

		#expect(model.entries[0].password == "hunter2")
		#expect(model.entries[1].password.isEmpty)

		let submitted = try #require(model.validatedServers())

		#expect(submitted[0].pendingServerPassword == .set("hunter2"))
		#expect(submitted[1].pendingServerPassword == .cleared)
	}

	@Test("Every endpoint in a list has an identity of its own to diff by")
	func entryIdentifiersAreDistinct() {
		let entries = [Server(), Server(), Server()]
		let identifiers = Set(entries.map(\.uniqueIdentifier))

		#expect(identifiers.count == entries.count)
	}

	@Test("Reordering by drag moves one endpoint and keeps the rest in order")
	func reorderingMovesOneEndpoint() {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "one"),
			Server(serverAddress: "two"),
			Server(serverAddress: "three"),
		])

		model.moveEntries(from: IndexSet(integer: 2), to: 0)

		#expect(model.entries.map(\.address) == ["three", "one", "two"])
	}

	/// A row added with the "+" button starts with an empty address. Skipping it
	/// on save made it vanish along with the port and password typed into it,
	/// and told the user nothing; an empty address is an invalid address.
	@Test("A row with no address is reported as invalid rather than dropped")
	@MainActor
	func blankEndpointsAreRejected() {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "irc.example.com", serverPort: 6667),
			Server(serverAddress: "", serverPort: 6667),
		])

		#expect(model.validatedServers() == nil)
		#expect(model.invalidAddressIDs == [model.entries[1].id])
	}

	@Test("The native editor validates rows and preserves their order")
	func nativeEditorSubmitsValidRowsInOrder() throws {
		let model = ServerEndpointListModel()
		model.replace(with: [
			Server(serverAddress: "irc.one.example", serverPort: 6697, prefersSecuredConnection: true),
			Server(serverAddress: "irc.two.example", serverPort: 6667),
		])

		model.selectedID = model.entries[1].id
		model.moveSelection(by: -1)

		let submitted = try #require(model.validatedServers())
		#expect(submitted.map(\.serverAddress) == ["irc.two.example", "irc.one.example"])
	}

	@Test("The native editor identifies the field that prevents submission")
	func nativeEditorReportsInvalidFields() {
		let model = ServerEndpointListModel()
		model.replace(with: [Server(serverAddress: "not a host", serverPort: 6667)])
		let id = model.entries[0].id

		#expect(model.validatedServers() == nil)
		#expect(model.invalidAddressIDs == [id])
		#expect(model.invalidPortIDs.isEmpty)

		model.entries[0].address = "irc.example.com"
		model.entries[0].port = "70000"
		#expect(model.validatedServers() == nil)
		#expect(model.invalidAddressIDs.isEmpty)
		#expect(model.invalidPortIDs == [id])
	}

	@Test("The native editor keeps default ports aligned with transport")
	func nativeEditorUpdatesDefaultPortForTransport() {
		let model = ServerEndpointListModel()
		model.replace(with: [Server(serverAddress: "irc.example.com", serverPort: 6667)])
		let id = model.entries[0].id

		model.setSecured(true, for: id)

		#expect(model.entries[0].prefersSecuredConnection)
		#expect(model.entries[0].port == "6697")
	}
}
