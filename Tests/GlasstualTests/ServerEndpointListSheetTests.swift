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

import Foundation
@testable import Glasstual
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
	func validAddressesAreAccepted(address: String) throws {
		#expect(try ServerEndpointValidation.validatedAddress(address) == address)
	}

	@Test(
		"An address that is empty or holds a separator is rejected",
		arguments: ["", "irc example.com", "irc.example.com/path", "irc:6667"]
	)
	func invalidAddressesAreRejected(address: String) {
		#expect(throws: (any Error).self) {
			try ServerEndpointValidation.validatedAddress(address)
		}
	}

	@Test("A rejected address carries the error the bindings used to raise")
	func rejectedAddressCarriesItsError() {
		var raised: NSError?

		do {
			_ = try ServerEndpointValidation.validatedAddress("")
		} catch {
			raised = error as NSError
		}

		#expect(raised?.domain == ServerEndpointValidation.errorDomain)
		#expect(raised?.code == ServerEndpointValidation.invalidAddressCode)
		#expect(raised?.localizedDescription.isEmpty == false)
	}

	@Test("A port inside the range is accepted", arguments: ["1", "6667", "6697", "65535"])
	func validPortsAreAccepted(port: String) throws {
		#expect(try ServerEndpointValidation.validatedPort(port) == UInt16(port))
	}

	@Test(
		"A port that is empty, not a number or out of range is rejected",
		arguments: ["", "0x1BCB", "65536", "99999", "-1", "six-six-six-seven"]
	)
	func invalidPortsAreRejected(port: String) {
		#expect(throws: (any Error).self) {
			try ServerEndpointValidation.validatedPort(port)
		}
	}

	@Test("A rejected port carries the error the bindings used to raise")
	func rejectedPortCarriesItsError() {
		var raised: NSError?

		do {
			_ = try ServerEndpointValidation.validatedPort("65536")
		} catch {
			raised = error as NSError
		}

		#expect(raised?.domain == ServerEndpointValidation.errorDomain)
		#expect(raised?.code == ServerEndpointValidation.invalidPortCode)
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
		server.pendingServerPassword = "hunter2"

		let secured = ServerEndpointValidation.server(server, preferringSecuredConnection: true)

		#expect(secured.uniqueIdentifier == server.uniqueIdentifier)
		#expect(secured.serverAddress == server.serverAddress)
		#expect(secured.pendingServerPassword == "hunter2")
	}

	// MARK: - The list the sheet edits

	@Test("An endpoint is added, edited by identity, and removed by identity")
	func entriesRoundTrip() throws {
		var entries: [Server] = []

		entries.append(Server(serverAddress: "irc.one.example", serverPort: 6667))
		entries.append(Server(serverAddress: "irc.two.example", serverPort: 6667))
		#expect(entries.count == 2)

		/* An edit finds its row by identity, because the table hands back an
		 identifier rather than a position. */
		let editedID = entries[1].uniqueIdentifier
		let index = try #require(entries.firstIndex { $0.uniqueIdentifier == editedID })
		entries[index].serverPort = 7000

		#expect(entries[1].serverPort == 7000)
		#expect(entries[0].serverPort == 6667)

		let removedID = entries[0].uniqueIdentifier
		entries.removeAll { $0.uniqueIdentifier == removedID }

		#expect(entries.count == 1)
		#expect(entries[0].uniqueIdentifier == editedID)
	}

	@Test("Every endpoint in a list has an identity of its own to diff by")
	func entryIdentifiersAreDistinct() {
		let entries = [Server(), Server(), Server()]
		let identifiers = Set(entries.map(\.uniqueIdentifier))

		#expect(identifiers.count == entries.count)
	}

	@Test("Reordering by drag moves one endpoint and keeps the rest in order")
	func reorderingMovesOneEndpoint() {
		var entries = [
			Server(serverAddress: "one"),
			Server(serverAddress: "two"),
			Server(serverAddress: "three"),
		]

		entries.insert(entries.remove(at: 2), at: 0)

		#expect(entries.map(\.serverAddress) == ["three", "one", "two"])
	}

	@Test("Only endpoints that name a server are reported back")
	func blankEndpointsAreNotReported() {
		let entries = [
			Server(serverAddress: "irc.example.com"),
			Server(serverAddress: ""),
			Server(serverAddress: "irc.other.example"),
		]

		let reported = entries.filter { $0.serverAddress.isEmpty == false }

		#expect(reported.map(\.serverAddress) == ["irc.example.com", "irc.other.example"])
	}
}
