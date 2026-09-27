// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension CapabilityGate {
	func isEnabled(in settings: ChatSettings) -> Bool {
		switch self {
		case .always: true
		case .echoMessage: settings.enableEchoMessageCapability
		case .chatHistory: settings.requestChatHistory
		case .readMarker: settings.synchronizeReadMarkers
		}
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

	func isCapabilitySupported(_ name: String, settings: ChatSettings) -> Bool {
		guard let capability = capability(named: name) else {
			return false
		}

		return isEnabled(capability, settings: settings)
	}

	/** Whether the user leaves the capability available at all: the setting
	 that gates it is on, and its name is not one of the capabilities switched
	 off in Settings. Both are read here so that a request and a support check
	 can never disagree about what the user asked for. */
	private func isEnabled(_ capability: Capability, settings: ChatSettings) -> Bool {
		capability.gate.isEnabled(in: settings)
			&& settings.disabledCapabilities.contains(capability.name) == false
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
		settings: ChatSettings,
		enabledCapabilities: CapabilitySet = []
	) -> [Capability] {
		capabilities.filter {
			isRequestable(
				$0,
				fromOffered: offered,
				settings: settings,
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
		settings: ChatSettings,
		enabledCapabilities: CapabilitySet,
		depth: Int
	) -> Bool {
		guard depth <= 8,
		      capability.requestedByDefault,
		      isEnabled(capability, settings: settings),
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
				settings: settings,
				enabledCapabilities: enabledCapabilities,
				depth: depth + 1
			) else {
				return false
			}
		}

		return true
	}
}
