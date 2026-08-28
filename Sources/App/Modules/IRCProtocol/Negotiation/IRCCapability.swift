/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

public typealias IRCCapabilityPreferenceGate = @convention(block) () -> Bool
public typealias IRCCapabilityNegotiationHook = @convention(block) (IRCClient, [String]) -> Bool

@objc(IRCCapability)
public final nonisolated class Capability: NSObject {
	@objc public let name: String
	public let identifier: ClientIRCv3SupportedCapability
	@objc public let requestedByDefault: Bool
	@objc public let preferenceGate: IRCCapabilityPreferenceGate?
	@objc public let dependencies: [String]
	@objc public let negotiationHook: IRCCapabilityNegotiationHook?

	public static func capability(named name: String, identifier: ClientIRCv3SupportedCapability) -> Capability {
		capability(named: name, identifier: identifier, requestedByDefault: true)
	}

	public static func capability(
		named name: String,
		identifier: ClientIRCv3SupportedCapability,
		requestedByDefault: Bool
	) -> Capability {
		Capability(
			name: name,
			identifier: identifier,
			requestedByDefault: requestedByDefault,
			preferenceGate: nil,
			dependencies: nil,
			negotiationHook: nil
		)
	}

	public init(
		name: String,
		identifier: ClientIRCv3SupportedCapability,
		requestedByDefault: Bool,
		preferenceGate: IRCCapabilityPreferenceGate?,
		dependencies: [String]?,
		negotiationHook: IRCCapabilityNegotiationHook?
	) {
		precondition(name.isEmpty == false)

		self.name = name.lowercased()
		self.identifier = identifier
		self.requestedByDefault = requestedByDefault
		self.preferenceGate = preferenceGate
		self.dependencies = dependencies ?? []
		self.negotiationHook = negotiationHook

		super.init()
	}

	@objc public var isEnabledByPreferences: Bool {
		preferenceGate?() ?? true
	}

	override public var description: String {
		"<\(NSStringFromClass(type(of: self))) \(name)>"
	}
}

@objc(IRCCapabilityRegistry)
public final nonisolated class CapabilityRegistry: NSObject {
	@objc public let capabilities: [Capability]

	private let capabilitiesByName: [String: Capability]

	@objc(initWithCapabilities:)
	public init(capabilities: [Capability]) {
		self.capabilities = capabilities
		capabilitiesByName = Dictionary(
			capabilities.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first }
		)

		super.init()
	}

	@objc(capabilityNamed:)
	public func capability(named name: String) -> Capability? {
		capabilitiesByName[name.lowercased()]
	}

	public func capability(for identifier: ClientIRCv3SupportedCapability) -> Capability? {
		guard identifier.rawValue != 0 else {
			return nil
		}

		return capabilities.first {
			($0.identifier.rawValue & identifier.rawValue) == identifier.rawValue
		}
	}

	@objc(isCapabilitySupported:)
	public func isCapabilitySupported(_ name: String) -> Bool {
		capability(named: name)?.isEnabledByPreferences ?? false
	}

	@objc(parseCapabilityList:)
	public static func parseCapabilityList(_ list: String) -> [String: [String]] {
		var offered: [String: [String]] = [:]

		for token in capabilityTokens(in: list) {
			offered[token.name.lowercased()] = token.values
		}

		return offered
	}

	/// Maps each offered capability's lowercased name to the exact spelling the
	/// server used.
	///
	/// IRCv3 capability names are case-sensitive, so a strict server can `NAK` a
	/// `CAP REQ` whose spelling differs from what it advertised. Matching stays
	/// case-insensitive; only what is echoed back changes.
	@objc(offeredNamesFromCapabilityList:)
	public static func offeredNames(fromCapabilityList list: String) -> [String: String] {
		var names: [String: String] = [:]

		for token in capabilityTokens(in: list) {
			names[token.name.lowercased()] = token.name
		}

		return names
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

	@objc(capabilitiesToRequestFromOffered:)
	public func capabilitiesToRequest(fromOffered offered: [String: [String]]) -> [Capability] {
		capabilities.filter { isRequestable($0, fromOffered: offered, depth: 0) }
	}

	private func isRequestable(
		_ capability: Capability,
		fromOffered offered: [String: [String]],
		depth: Int
	) -> Bool {
		guard depth <= 8,
		      capability.requestedByDefault,
		      capability.isEnabledByPreferences,
		      offered[capability.name] != nil
		else {
			return false
		}

		for dependencyName in capability.dependencies {
			guard let dependency = self.capability(named: dependencyName),
			      isRequestable(dependency, fromOffered: offered, depth: depth + 1)
			else {
				return false
			}
		}

		return true
	}
}
