/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

enum CapabilityPreference: Sendable, Equatable {
	case always
	case echoMessage
	case chatHistory
	case readMarker

	func isEnabled(in preferences: ClientPreferences) -> Bool {
		switch self {
		case .always: true
		case .echoMessage: preferences.enableEchoMessageCapability
		case .chatHistory: preferences.requestChatHistory
		case .readMarker: preferences.synchronizeReadMarkers
		}
	}
}

enum CapabilityNegotiation: Sendable, Equatable {
	case automatic
	case sasl
}

struct Capability: Sendable {
	let name: String
	let identifier: ClientIRCv3SupportedCapability
	let requestedByDefault: Bool
	let preference: CapabilityPreference
	let dependencies: [String]
	let negotiation: CapabilityNegotiation

	static func capability(named name: String, identifier: ClientIRCv3SupportedCapability) -> Capability {
		capability(named: name, identifier: identifier, requestedByDefault: true)
	}

	static func capability(
		named name: String,
		identifier: ClientIRCv3SupportedCapability,
		requestedByDefault: Bool
	) -> Capability {
		Capability(
			name: name,
			identifier: identifier,
			requestedByDefault: requestedByDefault,
			preference: .always,
			dependencies: [],
			negotiation: .automatic
		)
	}

	init(
		name: String,
		identifier: ClientIRCv3SupportedCapability,
		requestedByDefault: Bool,
		preference: CapabilityPreference = .always,
		dependencies: [String] = [],
		negotiation: CapabilityNegotiation = .automatic
	) {
		precondition(name.isEmpty == false)

		/* IRCv3 capability names are case-sensitive, so the name is kept as
		 declared. Every name the registry declares is lower case, which is
		 what every network advertises. */
		self.name = name
		self.identifier = identifier
		self.requestedByDefault = requestedByDefault
		self.preference = preference
		self.dependencies = dependencies
		self.negotiation = negotiation
	}
}

struct CapabilityRegistry: Sendable {
	let capabilities: [Capability]

	private let capabilitiesByName: [String: Capability]

	init(capabilities: [Capability]) {
		self.capabilities = capabilities
		capabilitiesByName = Dictionary(
			capabilities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
		)
	}

	func capability(named name: String) -> Capability? {
		capabilitiesByName[name]
	}

	func capability(for identifier: ClientIRCv3SupportedCapability) -> Capability? {
		guard identifier.rawValue != 0 else {
			return nil
		}

		return capabilities.first {
			($0.identifier.rawValue & identifier.rawValue) == identifier.rawValue
		}
	}

	func isCapabilitySupported(_ name: String, preferences: ClientPreferences) -> Bool {
		capability(named: name)?.preference.isEnabled(in: preferences) ?? false
	}

	/** The capabilities a `CAP LS`/`NEW` line offers, keyed by name.

	 IRCv3 says capability names are case-sensitive, so the name is the key
	 exactly as the server wrote it. Folding case here made `SASL` and `sasl`
	 one entry and forced a second table to remember which spelling to echo
	 back in `CAP REQ`; a name that matches is now already the right spelling. */
	static func parseCapabilityList(_ list: String) -> [String: [String]] {
		var offered: [String: [String]] = [:]

		for token in capabilityTokens(in: list) {
			offered[token.name] = token.values
		}

		return offered
	}

	private static func capabilityTokens(in list: String) -> [(name: String, values: [String])] {
		var tokens: [(name: String, values: [String])] = []

		for token in LineParser.wireTokens(in: list) {
			guard let equalsIndex = token.firstIndex(of: "=") else {
				tokens.append((token, []))
				continue
			}

			let name = String(token[..<equalsIndex])

			guard name.isEmpty == false else {
				continue
			}

			let valueStart = token.index(after: equalsIndex)
			let values = token[valueStart...].split(separator: ",").map(String.init)

			tokens.append((name, values))
		}

		return tokens
	}

	func capabilitiesToRequest(
		fromOffered offered: [String: [String]],
		preferences: ClientPreferences
	) -> [Capability] {
		capabilities.filter {
			isRequestable($0, fromOffered: offered, preferences: preferences, depth: 0)
		}
	}

	private func isRequestable(
		_ capability: Capability,
		fromOffered offered: [String: [String]],
		preferences: ClientPreferences,
		depth: Int
	) -> Bool {
		guard depth <= 8,
		      capability.requestedByDefault,
		      capability.preference.isEnabled(in: preferences),
		      offered[capability.name] != nil
		else {
			return false
		}

		for dependencyName in capability.dependencies {
			guard let dependency = self.capability(named: dependencyName) else {
				return false
			}
			guard isRequestable(
				dependency,
				fromOffered: offered,
				preferences: preferences,
				depth: depth + 1
			) else {
				return false
			}
		}

		return true
	}
}
