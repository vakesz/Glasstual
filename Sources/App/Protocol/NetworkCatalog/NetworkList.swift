/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation

public enum IRCNetworkRegistration: UInt, Sendable {
	case none = 0
	case optional = 1
	case required = 2
}

public nonisolated struct NetworkList: Sendable { // nonisolated: value
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
	]

	public let listOfNetworks: [Network]
	public let popularNetworks: [Network]

	public init() {
		self.init(networks: Self.loadNetworks())
	}

	/** The catalog built from a list handed in rather than read from the bundle.

	 Sorting and picking the popular subset is the same work either way, so a
	 fixture list answers every query exactly as the bundled one does. */
	public init(networks: [Network]) {
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

	public func network(named networkName: String) -> Network? {
		listOfNetworks.first { $0.networkName.caseInsensitiveCompare(networkName) == .orderedSame }
	}

	public func network(withServerAddress serverAddress: String) -> Network? {
		listOfNetworks.first { $0.serverAddress.caseInsensitiveCompare(serverAddress) == .orderedSame }
	}

	public static func accountFieldsApply(
		to registration: IRCNetworkRegistration,
		saslSupported: Bool
	) -> Bool {
		saslSupported || registration != .none
	}

	public static func registration(from string: String?) -> IRCNetworkRegistration {
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
		if let resource = ResourceManager.array(fromResources: "IRCNetworks", cacheValue: false) {
			return resource.compactMap { entry in
				guard let dictionary = entry.dictionary else {
					return nil
				}

				return Network(dictionary: dictionary)
			}
		}

		guard
			let legacyList = ResourceManager.dictionary(fromResources: "IRCNetworks", cacheValue: false)
		else {
			return []
		}

		return legacyList.compactMap { name, configuration in
			guard var dictionary = configuration.dictionary else {
				return nil
			}

			dictionary["name"] = .string(name)

			return Network(dictionary: dictionary)
		}
	}
}

public nonisolated struct Network: Sendable, Equatable { // nonisolated: value
	public let networkName: String
	public let networkDescription: String
	public let serverAddress: String
	public let serverPort: UInt16
	public let prefersSecuredConnection: Bool
	public let website: String?
	public let saslSupported: Bool
	public let registration: IRCNetworkRegistration
	public let registrationNote: String?
	public let suggestedChannels: [String]

	public init?(dictionary: [String: PropertyListValue]) {
		guard
			let networkName = dictionary["name"]?.string,
			networkName.isEmpty == false,
			let serverAddress = dictionary["serverAddress"]?.string,
			serverAddress.isEmpty == false
		else {
			return nil
		}

		let prefersSecuredConnection = dictionary["prefersSecuredConnection"]?.boolean ?? false
		let configuredPort = dictionary["serverPort"]?.integer.map(UInt16.init(clamping:)) ?? 0

		self.networkName = networkName
		networkDescription = Self.localized(dictionary["description"]?.string) ?? ""
		self.serverAddress = serverAddress
		serverPort = configuredPort == 0 ? (prefersSecuredConnection ? 6697 : 6667) : configuredPort
		self.prefersSecuredConnection = prefersSecuredConnection
		website = dictionary["website"]?.string
		saslSupported = dictionary["saslSupported"]?.boolean ?? false
		registration = NetworkList.registration(from: dictionary["registration"]?.string)
		registrationNote = Self.localized(dictionary["registrationNote"]?.string)
		suggestedChannels = dictionary["suggestedChannels"]?.stringArray ?? []
	}

	public var accountFieldsApply: Bool {
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
