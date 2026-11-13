// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

enum NetworkRegistration: UInt, Sendable {
	case none = 0
	case optional = 1
	case required = 2
}

nonisolated struct NetworkList: Sendable {
	private static let popularNetworkNames = [
		"Libera.Chat",
		"HybridIRC",
		"IRCnet",
		"Undernet",
		"OFTC",
		"Rizon",
		"EFnet",
		"DALnet",
		"QuakeNet",
		"hackint",
		"Snoonet",
		"Tilde.Chat",
		"DumaNet",
		"EsperNet",
		"synIRC",
		"DareNET",
		"Ergo",
	]

	let listOfNetworks: [Network]
	let popularNetworks: [Network]

	init() {
		self.init(networks: Self.loadNetworks())
	}

	/** The catalog built from a list handed in rather than read from the bundle.

	 Sorting and picking the popular subset is the same work either way, so a
	 fixture list answers every query exactly as the bundled one does. */
	init(networks: [Network]) {
		let networks = networks.sorted {
			$0.networkName.caseInsensitiveCompare($1.networkName) == .orderedAscending
		}

		listOfNetworks = networks

		let networksByName = Dictionary(
			networks.map { ($0.networkName.lowercased(), $0) },
			uniquingKeysWith: { first, _ in first }
		)
		popularNetworks = Self.popularNetworkNames.compactMap { networksByName[$0.lowercased()] }
	}

	func network(named networkName: String) -> Network? {
		listOfNetworks.first { $0.networkName.caseInsensitiveCompare(networkName) == .orderedSame }
	}

	func network(withServerAddress serverAddress: String) -> Network? {
		listOfNetworks.first { $0.serverAddress.caseInsensitiveCompare(serverAddress) == .orderedSame }
	}

	static func accountFieldsApply(
		to registration: NetworkRegistration,
		saslSupported: Bool
	) -> Bool {
		saslSupported || registration != .none
	}

	static func registration(from string: String?) -> NetworkRegistration {
		switch string?.lowercased() {
		case "required":
			.required
		case "optional":
			.optional
		default:
			.none
		}
	}

	private static func loadNetworks() -> [Network] {
		guard let resource = BundleResources.array(fromResources: "IRCNetworks", cacheValue: false) else {
			return []
		}
		return resource.compactMap { entry in
			guard let dictionary = entry.dictionary else {
				return nil
			}
			return Network(dictionary: dictionary)
		}
	}
}

nonisolated struct Network: Sendable, Equatable {
	let networkName: String
	let networkDescription: String
	let serverAddress: String
	let serverPort: UInt16
	let prefersSecuredConnection: Bool
	let transport: ServerTransport
	let webSocketPath: String
	/// More ways to reach the same network, after the primary server: a
	/// preset can list IRC over TLS first and a secure WebSocket after it.
	let alternateEndpoints: [ServerEndpoint]
	let website: String?
	let saslSupported: Bool
	let registration: NetworkRegistration
	let registrationNote: String?
	let suggestedChannels: [String]

	init?(dictionary: [String: PropertyListValue]) {
		guard
			let networkName = dictionary["name"]?.string,
			networkName.isEmpty == false,
			let serverAddress = dictionary["serverAddress"]?.string,
			serverAddress.isEmpty == false, let primary = Self.endpoint(from: dictionary) else { return nil }

		self.networkName = networkName
		networkDescription = Self.localized(dictionary["description"]?.string) ?? ""
		self.serverAddress = serverAddress
		serverPort = primary.serverPort
		prefersSecuredConnection = primary.prefersSecuredConnection
		transport = primary.transport
		webSocketPath = primary.webSocketPath
		alternateEndpoints = (dictionary["alternateServers"]?.array ?? []).compactMap {
			$0.dictionary.flatMap(Self.endpoint(from:))
		}
		website = dictionary["website"]?.string
		saslSupported = dictionary["saslSupported"]?.boolean ?? false
		registration = NetworkList.registration(from: dictionary["registration"]?.string)
		registrationNote = Self.localized(dictionary["registrationNote"]?.string)
		suggestedChannels = dictionary["suggestedChannels"]?.stringArray ?? []
	}

	/** One server entry of the catalog: an address, an optional port that
	 defaults by transport and encryption, and for a WebSocket its path. An
	 entry with an unknown transport or an invalid path is left out rather
	 than dialled some other way. */
	private static func endpoint(from dictionary: [String: PropertyListValue]) -> ServerEndpoint? {
		guard let address = dictionary["serverAddress"]?.string, address.isEmpty == false else { return nil }
		let secured = dictionary["prefersSecuredConnection"]?.boolean ?? false
		guard let transport = ServerTransport(rawValue: dictionary["transport"]?.string ?? ServerTransport.irc.rawValue) else {
			return nil
		}
		let path = dictionary["webSocketPath"]?.string ?? "/"
		guard ServerTransport.isValidWebSocketPath(path) else { return nil }
		let configuredPort = dictionary["serverPort"]?.integer.map(UInt16.init(clamping:)) ?? 0
		return ServerEndpoint(
			uniqueIdentifier: "",
			serverAddress: address,
			serverPort: configuredPort == 0 ? transport.defaultPort(secured: secured) : configuredPort,
			prefersSecuredConnection: secured,
			transport: transport,
			webSocketPath: path
		)
	}

	/// The server entries a connection made from this network starts with,
	/// each under an identity of its own.
	var serverList: [ServerEndpoint] {
		let primary = ServerEndpoint(
			serverAddress: serverAddress,
			serverPort: serverPort,
			prefersSecuredConnection: prefersSecuredConnection,
			transport: transport,
			webSocketPath: webSocketPath
		)
		return [primary] + alternateEndpoints.map { endpoint in
			var copy = endpoint
			copy.uniqueIdentifier = UUID().uuidString
			return copy
		}
	}

	var accountFieldsApply: Bool {
		NetworkList.accountFieldsApply(to: registration, saslSupported: saslSupported)
	}

	/** The `Networks` catalog entry for one of the property list's English
	 blurbs, or the blurb itself when there is no entry for it.

	 The list is data, not code, so there is no typed symbol to reach these
	 through: the English text is the key. That also decides what a network
	 added to the list before its blurb is translated shows — the English
	 sentence, rather than a blank line under the network's name. */
	private static func localized(_ text: String?) -> String? {
		guard let text, text.isEmpty == false else {
			return nil
		}

		return String(localized: String.LocalizationValue(text), table: "Networks", bundle: .main)
	}
}
