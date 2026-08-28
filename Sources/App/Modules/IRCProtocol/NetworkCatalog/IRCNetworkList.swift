/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import Foundation

@objc public enum IRCNetworkRegistration: UInt, Sendable {
	case none = 0
	case optional = 1
	case required = 2
}

@objc(IRCNetworkList)
public final nonisolated class NetworkList: NSObject {
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

	@objc public let listOfNetworks: [Network]
	@objc public let popularNetworks: [Network]

	override public init() {
		let networks = Self.loadNetworks().sorted {
			$0.networkName.caseInsensitiveCompare($1.networkName) == .orderedAscending
		}

		listOfNetworks = networks

		let networksByName = Dictionary(
			networks.map { ($0.networkName.lowercased(), $0) },
			uniquingKeysWith: { first, _ in first }
		)
		popularNetworks = Self.popularNetworkNames.compactMap { networksByName[$0.lowercased()] }

		super.init()
	}

	@objc(networkNamed:)
	public func network(named networkName: String) -> Network? {
		listOfNetworks.first { $0.networkName.caseInsensitiveCompare(networkName) == .orderedSame }
	}

	@objc(networkWithServerAddress:)
	public func network(withServerAddress serverAddress: String) -> Network? {
		listOfNetworks.first { $0.serverAddress.caseInsensitiveCompare(serverAddress) == .orderedSame }
	}

	@objc(accountFieldsApplyToRegistration:saslSupported:)
	public static func accountFieldsApply(
		to registration: IRCNetworkRegistration,
		saslSupported: Bool
	) -> Bool {
		saslSupported || registration != .none
	}

	@objc(registrationFromString:)
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
				guard let dictionary = entry as? [String: Any] else {
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
			guard var dictionary = configuration as? [String: Any] else {
				return nil
			}

			dictionary["name"] = name

			return Network(dictionary: dictionary)
		}
	}
}

@objc(IRCNetwork)
public final nonisolated class Network: NSObject {
	@objc public let networkName: String
	@objc public let networkDescription: String
	@objc public let serverAddress: String
	@objc public let serverPort: UInt16
	@objc public let prefersSecuredConnection: Bool
	@objc public let website: String?
	@objc public let saslSupported: Bool
	@objc public let registration: IRCNetworkRegistration
	@objc public let registrationNote: String?
	@objc public let suggestedChannels: [String]

	@available(*, unavailable)
	override public init() {
		fatalError("Use init(dictionary:)")
	}

	@objc(initWithDictionary:)
	public init?(dictionary: [String: Any]) {
		guard
			let networkName = dictionary["name"] as? String,
			networkName.isEmpty == false,
			let serverAddress = dictionary["serverAddress"] as? String,
			serverAddress.isEmpty == false
		else {
			return nil
		}

		let prefersSecuredConnection = Self.boolValue(dictionary["prefersSecuredConnection"])
		let configuredPort = (dictionary["serverPort"] as? NSNumber)?.uint16Value ?? 0

		self.networkName = networkName
		networkDescription = dictionary["description"] as? String ?? ""
		self.serverAddress = serverAddress
		serverPort = configuredPort == 0 ? (prefersSecuredConnection ? 6697 : 6667) : configuredPort
		self.prefersSecuredConnection = prefersSecuredConnection
		website = dictionary["website"] as? String
		saslSupported = Self.boolValue(dictionary["saslSupported"])
		registration = NetworkList.registration(from: dictionary["registration"] as? String)

		if let note = dictionary["registrationNote"] as? String, note.isEmpty == false {
			registrationNote = note
		} else {
			registrationNote = nil
		}

		suggestedChannels = dictionary["suggestedChannels"] as? [String] ?? []

		super.init()
	}

	@objc public var accountFieldsApply: Bool {
		NetworkList.accountFieldsApply(to: registration, saslSupported: saslSupported)
	}

	override public var description: String {
		"<\(NSStringFromClass(type(of: self))) \(networkName) \(serverAddress):\(serverPort)>"
	}

	private static func boolValue(_ value: Any?) -> Bool {
		(value as? NSNumber)?.boolValue ?? false
	}
}
