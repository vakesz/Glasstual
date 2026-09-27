// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

enum CapabilityGate: Sendable, Equatable {
	case always
	case echoMessage
	case chatHistory
	case readMarker
}

/// How a capability is negotiated: on its own, or through a SASL exchange.
enum CapabilityNegotiationKind: Sendable, Equatable {
	case automatic
	case sasl
}

struct Capability: Sendable {
	let name: String
	let identifier: CapabilitySet
	let requestedByDefault: Bool
	let gate: CapabilityGate
	let dependencies: [String]
	let negotiation: CapabilityNegotiationKind

	/** Where the capability is defined: an IRCv3 extension page, or the ZNC
	 documentation for a bouncer capability.

	 It is a protocol-level constant rather than something a view holds, so the
	 declaration that names a capability is also what says where it comes from.
	 A capability the session requests without a published document has none. */
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
			gate: .always,
			dependencies: [],
			negotiation: .automatic,
			specification: specification
		)
	}

	init(
		name: String,
		identifier: CapabilitySet,
		requestedByDefault: Bool,
		gate: CapabilityGate = .always,
		dependencies: [String] = [],
		negotiation: CapabilityNegotiationKind = .automatic,
		specification: URL? = nil
	) {
		precondition(name.isEmpty == false)

		/* IRCv3 capability names are case-sensitive, so the name is kept as
		 declared. Every name the registry declares is lower case, which is
		 what every network advertises. */
		self.name = name
		self.identifier = identifier
		self.requestedByDefault = requestedByDefault
		self.gate = gate
		self.dependencies = dependencies
		self.negotiation = negotiation
		self.specification = specification
	}
}

/// Opaque capability identifiers used by the session's negotiated-capability registry.
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
