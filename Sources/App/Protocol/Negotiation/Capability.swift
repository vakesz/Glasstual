// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
	let identifier: CapabilitySet
	let requestedByDefault: Bool
	let preference: CapabilityPreference
	let dependencies: [String]
	let negotiation: CapabilityNegotiation

	/** Where the capability is defined: an IRCv3 extension page, or the ZNC
	 documentation for a bouncer capability.

	 It is a protocol-level constant rather than something a view holds, so the
	 declaration that names a capability is also what says where it comes from.
	 A capability the client requests without a published document has none. */
	let specification: URL?

	static func capability(
		named name: String,
		identifier: CapabilitySet,
		requestedByDefault: Bool = true,
		specification: URL? = nil
	) -> Capability {
		Capability(
			name: name,
			identifier: identifier,
			requestedByDefault: requestedByDefault,
			preference: .always,
			dependencies: [],
			negotiation: .automatic,
			specification: specification
		)
	}

	init(
		name: String,
		identifier: CapabilitySet,
		requestedByDefault: Bool,
		preference: CapabilityPreference = .always,
		dependencies: [String] = [],
		negotiation: CapabilityNegotiation = .automatic,
		specification: URL? = nil
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
		self.specification = specification
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

	func capability(for identifier: CapabilitySet) -> Capability? {
		guard identifier.rawValue != 0 else {
			return nil
		}

		return capabilities.first {
			($0.identifier.rawValue & identifier.rawValue) == identifier.rawValue
		}
	}

	func isCapabilitySupported(_ name: String, preferences: ClientPreferences) -> Bool {
		guard let capability = capability(named: name) else {
			return false
		}

		return isEnabled(capability, preferences: preferences)
	}

	/** Whether the user leaves the capability available at all: the preference
	 that gates it is on, and its name is not one of the capabilities switched
	 off in Settings. Both are read here so that a request and a support check
	 can never disagree about what the user asked for. */
	private func isEnabled(_ capability: Capability, preferences: ClientPreferences) -> Bool {
		capability.preference.isEnabled(in: preferences)
			&& preferences.disabledCapabilities.contains(capability.name) == false
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
		preferences: ClientPreferences,
		enabledCapabilities: CapabilitySet = []
	) -> [Capability] {
		capabilities.filter {
			isRequestable(
				$0,
				fromOffered: offered,
				preferences: preferences,
				enabledCapabilities: enabledCapabilities,
				depth: 0
			)
		}
	}

	var knownIdentifiers: CapabilitySet {
		capabilities.reduce(into: []) { $0.formUnion($1.identifier) }
	}

	/// Dependencies are semantic identifiers, so a surviving vendor alias can
	/// still supply server-time. Iterate to a fixed point for transitive needs.
	func projection(of names: [String]) -> CapabilitySet {
		let acknowledged = names.compactMap { capability(named: $0) }
		var result: CapabilitySet = []
		for _ in 0 ... capabilities.count {
			let previous = result
			for capability in acknowledged where dependenciesSatisfied(for: capability, by: result) {
				result.formUnion(capability.identifier)
			}
			if result == previous {
				break
			}
		}
		return result
	}

	func dependenciesSatisfied(for capability: Capability, by enabled: CapabilitySet) -> Bool {
		capability.dependencies.allSatisfy { name in
			guard let dependency = self.capability(named: name) else { return false }
			return enabled.contains(dependency.identifier)
		}
	}

	private func isRequestable(
		_ capability: Capability,
		fromOffered offered: [String: [String]],
		preferences: ClientPreferences,
		enabledCapabilities: CapabilitySet,
		depth: Int
	) -> Bool {
		guard depth <= 8,
		      capability.requestedByDefault,
		      isEnabled(capability, preferences: preferences),
		      offered[capability.name] != nil
		else {
			return false
		}

		for dependencyName in capability.dependencies {
			guard let dependency = self.capability(named: dependencyName) else {
				return false
			}
			if dependency.identifier.rawValue != 0, enabledCapabilities.contains(dependency.identifier) {
				continue
			}
			guard isRequestable(
				dependency,
				fromOffered: offered,
				preferences: preferences,
				enabledCapabilities: enabledCapabilities,
				depth: depth + 1
			) else {
				return false
			}
		}

		return true
	}
}

/// Opaque capability identifiers used by the client's negotiated-capability registry.
nonisolated struct CapabilitySet: OptionSet, Hashable, Sendable {
	let rawValue: UInt

	static let awayNotify = Self(rawValue: 1 << 0)
	static let batch = Self(rawValue: 1 << 1)
	static let echoMessage = Self(rawValue: 1 << 2)
	static let isIdentifiedWithSASL = Self(rawValue: 1 << 5)
	static let isInSASLNegotiation = Self(rawValue: 1 << 6)
	static let monitorCommand = Self(rawValue: 1 << 7)
	static let multiPrefix = Self(rawValue: 1 << 8)
	static let playback = Self(rawValue: 1 << 9)
	static let serverTime = Self(rawValue: 1 << 10)
	static let userhostInNames = Self(rawValue: 1 << 11)
	static let watchCommand = Self(rawValue: 1 << 12)
	static let zncCertInfoModule = Self(rawValue: 1 << 13)
	static let zncSelfMessage = Self(rawValue: 1 << 14)
	static let changeHost = Self(rawValue: 1 << 15)
	static let messageTags = Self(rawValue: 1 << 16)
	static let capNotify = Self(rawValue: 1 << 17)
	static let standardReplies = Self(rawValue: 1 << 18)
	static let chatHistory = Self(rawValue: 1 << 19)
	static let readMarker = Self(rawValue: 1 << 20)
	static let labeledResponse = Self(rawValue: 1 << 21)
	/// `sasl`, as opposed to the mechanism-specific SASL bits.
	static let saslGeneric = Self(rawValue: 1 << 22)
	static let zncServerTime = Self(rawValue: 1 << 25)
	static let zncServerTimeISO = Self(rawValue: 1 << 26)
	static let zncPlaybackModule = Self(rawValue: 1 << 27)
	static let accountNotify = Self(rawValue: 1 << 28)
	static let extendedJoin = Self(rawValue: 1 << 29)
	static let accountTag = Self(rawValue: 1 << 30)
	static let setName = Self(rawValue: 1 << 31)
	static let inviteNotify = Self(rawValue: 1 << 32)
	static let extendedMonitor = Self(rawValue: 1 << 33)
	static let preAway = Self(rawValue: 1 << 34)
}

/// What the negotiated session lets the client do, read by everything past
/// registration. The negotiation that produces these answers lives in
/// `ClientNegotiation`.
extension Client {
	func isCapabilityEnabled(_ capability: CapabilitySet) -> Bool {
		capabilities.contains(capability)
	}

	func isCapabilitySupported(_ capability: String) -> Bool {
		CapabilityRegistry.defaultRegistry.isCapabilitySupported(capability, preferences: environment.preferences)
	}

	var enabledCapabilitiesStringValue: String {
		capabilityNegotiation.enabledCapabilitiesStringValue
	}

	/// Whether the server tracks presence for the client, through `MONITOR`
	/// or `WATCH`.
	var supportsAdvancedTracking: Bool {
		isCapabilityEnabled(.monitorCommand) || isCapabilityEnabled(.watchCommand)
	}

	/// Whether member away state is kept current, by `away-notify` or by the
	/// user's own polling preference.
	var monitorAwayStatus: Bool {
		isCapabilityEnabled(.awayNotify) || environment.preferences.trackUserAwayStatusMaximumChannelSize > 0
	}
}
