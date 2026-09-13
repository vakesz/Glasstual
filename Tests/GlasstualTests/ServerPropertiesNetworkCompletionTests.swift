/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/** What the Server Address field does with the bundled network catalog.

 The field is an address field that also takes a network by name: "Libera.Chat"
 stands for `irc.libera.chat` on port 6697 over TLS. Every assertion here is
 about that translation — which direction it runs in, when it fires, and what it
 puts back when the person types their own host after all. */
@MainActor
@Suite("Server properties network completion")
struct ServerPropertiesNetworkCompletionTests {
	private static func network(
		_ networkName: String,
		_ serverAddress: String,
		port: Int,
		secured: Bool
	) throws -> Network {
		try #require(Network(dictionary: [
			"name": .string(networkName),
			"serverAddress": .string(serverAddress),
			"serverPort": .integer(port),
			"prefersSecuredConnection": .boolean(secured),
		]))
	}

	/** Two of the curated popular networks and one the curated list does not
	 name, so the suggestions have something to put first and something to put
	 after it, and the two differ in port and in TLS. */
	private static func catalog() throws -> NetworkList {
		try NetworkList(networks: [
			network("Libera.Chat", "irc.libera.chat", port: 6697, secured: true),
			network("Rizon", "irc.rizon.net", port: 6667, secured: false),
			network("Ergo testnet", "testnet.ergo.chat", port: 6697, secured: true),
		])
	}

	/// A configuration whose every other field is acceptable, so the only thing
	/// that can fail validation is the address.
	private static func configuration(
		serverAddress: String = "",
		port: UInt16 = 6667,
		secured: Bool = false
	) -> ClientConfig {
		var config = ClientConfig(connectionName: "Test Connection")
		config.nickname = "someone"
		config.username = "someone"
		config.realName = "Someone"
		config.serverList = [
			Server(serverAddress: serverAddress, serverPort: port, prefersSecuredConnection: secured),
		]

		return config
	}

	private static func model(
		serverAddress: String = "",
		port: UInt16 = 6667,
		secured: Bool = false
	) throws -> ServerPropertiesModel {
		try ServerPropertiesModel(
			config: configuration(serverAddress: serverAddress, port: port, secured: secured),
			networkList: catalog()
		)
	}

	@Test("A typed network name is stored as that network's address")
	func typedNetworkNameIsStoredAsTheCatalogAddress() throws {
		let model = try Self.model()
		model.serverAddress = "libera.chat"
		model.serverAddressTextDidChange()

		#expect(model.serverAddress == "Libera.Chat")
		#expect(model.resolvedPrimaryServerAddress == "irc.libera.chat")

		let submitted = try #require(model.submittedConfig())
		#expect(submitted.serverList.first?.serverAddress == "irc.libera.chat")
		#expect(submitted.serverList.first?.serverPort == 6697)
		#expect(submitted.serverList.first?.prefersSecuredConnection == true)
	}

	/// A host no network claims is still the person's own to type, lowercased
	/// the way it always was.
	@Test("A host the catalog does not list is stored as typed")
	func unlistedHostIsStoredAsTyped() throws {
		let model = try Self.model()
		model.serverAddress = "IRC.Example.Test"
		model.serverAddressTextDidChange()

		#expect(model.serverAddress == "IRC.Example.Test")
		#expect(model.resolvedPrimaryServerAddress == "irc.example.test")
		#expect(try #require(model.submittedConfig()).serverList.first?.serverAddress == "irc.example.test")
	}

	@Test("Typing a network's address shows its name and brings its port and TLS with it")
	func typedCatalogAddressBecomesTheNetworkName() throws {
		let model = try Self.model(serverAddress: "irc.libera.chat", port: 6697, secured: true)
		#expect(model.serverAddress == "Libera.Chat")

		model.serverAddress = "irc.rizon.net"
		model.serverAddressTextDidChange()

		#expect(model.serverAddress == "Rizon")
		#expect(model.serverPort == "6667")
		#expect(model.primaryServerIsSecured == false)
	}

	/** The network overwrote the port and the TLS flag, so the person who then
	 types their own host is owed what they had rather than the last network's
	 defaults. */
	@Test("A host matching no network puts back what the last network overwrote")
	func unknownHostRestoresTheReplacedValues() throws {
		let model = try Self.model(serverAddress: "irc.example.test", port: 7000, secured: false)
		#expect(model.serverPort == "7000")

		model.serverAddress = "Libera.Chat"
		model.serverAddressTextDidChange()
		#expect(model.serverPort == "6697")
		#expect(model.primaryServerIsSecured)

		model.serverAddress = "irc.example.test"
		model.serverAddressTextDidChange()
		#expect(model.serverPort == "7000")
		#expect(model.primaryServerIsSecured == false)

		/* Once restored, the values are gone: a second unlisted host does not
		 put the same port back over whatever was typed after it. */
		model.serverPort = "6660"
		model.serverAddress = "other.example.test"
		model.serverAddressTextDidChange()
		#expect(model.serverPort == "6660")
	}

	@Test("A stored address the catalog lists is shown as the network's name")
	func loadedCatalogAddressShowsTheNetworkName() throws {
		let model = try Self.model(serverAddress: "irc.rizon.net", port: 6667)
		#expect(model.serverAddress == "Rizon")

		let submitted = try #require(model.submittedConfig())
		#expect(submitted.serverList.first?.serverAddress == "irc.rizon.net")

		model.replace(with: Self.configuration(serverAddress: "irc.libera.chat", port: 6697, secured: true))
		#expect(model.serverAddress == "Libera.Chat")
	}

	/** The endpoint list sheet edits hosts, not networks, so it is handed the
	 resolved address and its answer is displayed by the same rule the sheet
	 loaded by. */
	@Test("The endpoint list sees the resolved address and answers by the same display rule")
	func endpointListRoundTripKeepsTheDisplayRule() throws {
		let model = try Self.model(serverAddress: "irc.libera.chat", port: 6697, secured: true)
		let servers = try #require(model.serverListForEditing())
		#expect(servers.first?.serverAddress == "irc.libera.chat")

		model.applyServerList(servers)
		#expect(model.serverAddress == "Libera.Chat")

		var edited = servers
		edited[0].serverAddress = "edited.example.test"
		model.applyServerList(edited)
		#expect(model.serverAddress == "edited.example.test")

		/* Nothing a network overwrote is still on screen after the list comes
		 back, so an unlisted host typed next restores nothing. */
		model.serverPort = "6660"
		model.serverAddress = "another.example.test"
		model.serverAddressTextDidChange()
		#expect(model.serverPort == "6660")
	}

	@Test("An empty field suggests the popular networks first, then the rest")
	func emptyFieldLeadsWithThePopularNetworks() throws {
		let model = try Self.model()

		#expect(model.serverAddressSuggestions.map(\.networkName) == ["Libera.Chat", "Rizon", "Ergo testnet"])
	}

	@Test("Typing narrows the suggestions by name and by address")
	func suggestionsMatchNameAndAddress() throws {
		let model = try Self.model()

		model.serverAddress = "rizo"
		#expect(model.serverAddressSuggestions.map(\.networkName) == ["Rizon"])

		model.serverAddress = "testnet.ergo"
		#expect(model.serverAddressSuggestions.map(\.networkName) == ["Ergo testnet"])

		model.serverAddress = "irc."
		#expect(model.serverAddressSuggestions.map(\.networkName) == ["Libera.Chat", "Rizon"])

		model.serverAddress = "nothing-of-the-sort"
		#expect(model.serverAddressSuggestions.isEmpty)
	}

	/** The field validates an internet address, and three bundled network names
	 hold a space — which no address may. Validating the resolved address rather
	 than the text is what lets the field offer every network it lists. */
	@Test("Every bundled network name is accepted in the address field")
	func everyBundledNetworkNameIsAccepted() {
		let networkList = NetworkList()
		let model = ServerPropertiesModel(config: Self.configuration(), networkList: networkList)

		#expect(networkList.listOfNetworks.isEmpty == false)

		for network in networkList.listOfNetworks {
			model.serverAddress = network.networkName
			#expect(model.resolvedPrimaryServerAddress == network.serverAddress)
			#expect(model.validationFault == nil, "\(network.networkName) was refused")
		}

		#expect(ServerPropertiesValidation.isInternetAddress("Fuel Rats") == false)
	}
}
