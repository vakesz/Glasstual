/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

extension CapabilityRegistry {
	static var defaultRegistry: CapabilityRegistry {
		defaultRegistryStorage
	}

	private static let defaultRegistryStorage = CapabilityRegistry(
		capabilities: defaultCapabilities
	)

	/// The IRCv3 extension page a standard capability is defined by.
	private static func ircv3Specification(_ slug: String) -> URL? {
		URL(string: "https://ircv3.net/specs/extensions/\(slug)")
	}

	/// The ZNC documentation page a bouncer capability is described by.
	private static func zncSpecification(_ page: String) -> URL? {
		URL(string: "https://wiki.znc.in/\(page)")
	}

	private static var defaultCapabilities: [Capability] {
		let saslGeneric = ClientIRCv3SupportedCapability.saslGeneric
		let zncPlaybackModule = ClientIRCv3SupportedCapability.zncPlaybackModule
		let zncServerTime = ClientIRCv3SupportedCapability.zncServerTime
		let zncServerTimeISO = ClientIRCv3SupportedCapability.zncServerTimeISO
		/* ZNC documents its own capabilities on one page rather than one page
		 each, so the three that have no page of their own share it. */
		let zncCapabilities = zncSpecification("Developer:Cap")

		return [
			Capability.capability(
				named: "account-notify",
				identifier: .accountNotify,
				specification: ircv3Specification("account-notify")
			),
			Capability.capability(
				named: "account-tag",
				identifier: .accountTag,
				specification: ircv3Specification("account-tag")
			),
			Capability.capability(
				named: "cap-notify",
				identifier: .capNotify,
				specification: ircv3Specification("capability-negotiation")
			),
			Capability.capability(
				named: "message-tags",
				identifier: .messageTags,
				specification: ircv3Specification("message-tags")
			),
			Capability.capability(
				named: "away-notify",
				identifier: .awayNotify,
				specification: ircv3Specification("away-notify")
			),
			Capability.capability(
				named: "batch",
				identifier: .batch,
				specification: ircv3Specification("batch")
			),
			Capability.capability(
				named: "chghost",
				identifier: .changeHost,
				specification: ircv3Specification("chghost")
			),
			Capability(
				name: "draft/chathistory",
				identifier: .chatHistory,
				requestedByDefault: true,
				preference: .chatHistory,
				dependencies: ["batch", "server-time", "message-tags"],
				negotiation: .automatic,
				specification: ircv3Specification("chathistory")
			),
			Capability(
				name: "chathistory",
				identifier: .chatHistory,
				requestedByDefault: true,
				preference: .chatHistory,
				dependencies: ["batch", "server-time", "message-tags"],
				negotiation: .automatic,
				specification: ircv3Specification("chathistory")
			),
			Capability(
				name: "draft/read-marker",
				identifier: .readMarker,
				requestedByDefault: true,
				preference: .readMarker,
				specification: ircv3Specification("read-marker")
			),
			Capability(
				name: "read-marker",
				identifier: .readMarker,
				requestedByDefault: true,
				preference: .readMarker,
				specification: ircv3Specification("read-marker")
			),
			Capability(
				name: "echo-message",
				identifier: .echoMessage,
				requestedByDefault: true,
				preference: .echoMessage,
				specification: ircv3Specification("echo-message")
			),
			Capability.capability(
				named: "extended-join",
				identifier: .extendedJoin,
				specification: ircv3Specification("extended-join")
			),
			Capability.capability(
				named: "extended-monitor",
				identifier: .extendedMonitor,
				specification: ircv3Specification("extended-monitor")
			),
			Capability.capability(
				named: "invite-notify",
				identifier: .inviteNotify,
				specification: ircv3Specification("invite-notify")
			),
			Capability(
				name: "labeled-response",
				identifier: .labeledResponse,
				requestedByDefault: true,
				dependencies: ["message-tags"],
				negotiation: .automatic,
				specification: ircv3Specification("labeled-response")
			),
			Capability.capability(
				named: "multi-prefix",
				identifier: .multiPrefix,
				specification: ircv3Specification("multi-prefix")
			),
			Capability.capability(
				named: "pre-away",
				identifier: .preAway,
				specification: ircv3Specification("pre-away")
			),
			Capability(
				name: "sasl",
				identifier: saslGeneric,
				requestedByDefault: true,
				negotiation: .sasl,
				specification: ircv3Specification("sasl-3.1")
			),
			Capability.capability(
				named: "server-time",
				identifier: .serverTime,
				specification: ircv3Specification("server-time")
			),
			Capability.capability(
				named: "setname",
				identifier: .setName,
				specification: ircv3Specification("setname")
			),
			Capability.capability(
				named: "standard-replies",
				identifier: .standardReplies,
				specification: ircv3Specification("standard-replies")
			),
			Capability.capability(
				named: "userhost-in-names",
				identifier: .userhostInNames,
				specification: ircv3Specification("userhost-in-names")
			),
			Capability(
				name: "znc.in/playback",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.playback.rawValue | zncPlaybackModule.rawValue
				),
				requestedByDefault: true,
				preference: .always,
				specification: zncSpecification("Playback")
			),
			Capability.capability(
				named: "znc.in/self-message",
				identifier: .zncSelfMessage,
				specification: zncSpecification("Query_buffers")
			),
			Capability(
				name: "znc.in/server-time",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.serverTime.rawValue | zncServerTime.rawValue
				),
				requestedByDefault: true,
				preference: .always,
				specification: zncCapabilities
			),
			Capability(
				name: "znc.in/server-time-iso",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.serverTime.rawValue | zncServerTimeISO.rawValue
				),
				requestedByDefault: true,
				preference: .always,
				specification: zncCapabilities
			),
			Capability.capability(
				named: "znc.in/tlsinfo",
				identifier: .zncCertInfoModule,
				specification: zncCapabilities
			),
		]
	}
}
