/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation

extension CapabilityRegistry {
	public static var defaultRegistry: CapabilityRegistry {
		defaultRegistryStorage
	}

	private static let defaultRegistryStorage = CapabilityRegistry(
		capabilities: defaultCapabilities
	)

	private static var defaultCapabilities: [Capability] {
		let echoMessageGate: IRCCapabilityPreferenceGate = {
			TextualPreferences.enableEchoMessageCapability()
		}

		let saslHook: IRCCapabilityNegotiationHook = { client, mechanisms in
			client.selectSASLMechanism(fromOffered: mechanisms)
		}

		let saslGeneric = ClientIRCv3SupportedCapability.saslGeneric
		let zncPlaybackModule = ClientIRCv3SupportedCapability.zncPlaybackModule
		let zncServerTime = ClientIRCv3SupportedCapability.zncServerTime
		let zncServerTimeISO = ClientIRCv3SupportedCapability.zncServerTimeISO

		return [
			Capability.capability(named: "account-notify", identifier: .accountNotify),
			Capability.capability(named: "account-tag", identifier: .accountTag),
			Capability.capability(named: "cap-notify", identifier: .capNotify),
			Capability.capability(named: "message-tags", identifier: .messageTags),
			Capability.capability(named: "away-notify", identifier: .awayNotify),
			Capability.capability(named: "batch", identifier: .batch),
			Capability.capability(named: "chghost", identifier: .changeHost),
			Capability(
				name: "draft/chathistory",
				identifier: .chatHistory,
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: ["batch", "server-time", "message-tags"],
				negotiationHook: nil
			),
			Capability(
				name: "chathistory",
				identifier: .chatHistory,
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: ["batch", "server-time", "message-tags"],
				negotiationHook: nil
			),
			Capability.capability(named: "draft/read-marker", identifier: .readMarker),
			Capability.capability(named: "read-marker", identifier: .readMarker),
			Capability(
				name: "echo-message",
				identifier: .echoMessage,
				requestedByDefault: true,
				preferenceGate: echoMessageGate,
				dependencies: nil,
				negotiationHook: nil
			),
			Capability.capability(named: "extended-join", identifier: .extendedJoin),
			Capability.capability(named: "extended-monitor", identifier: .extendedMonitor),
			Capability.capability(named: "invite-notify", identifier: .inviteNotify),
			Capability(
				name: "labeled-response",
				identifier: .labeledResponse,
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: ["message-tags"],
				negotiationHook: nil
			),
			Capability.capability(named: "multi-prefix", identifier: .multiPrefix),
			Capability.capability(named: "pre-away", identifier: .preAway),
			Capability(
				name: "sasl",
				identifier: saslGeneric,
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: nil,
				negotiationHook: saslHook
			),
			Capability.capability(named: "server-time", identifier: .serverTime),
			Capability.capability(named: "setname", identifier: .setName),
			Capability.capability(named: "standard-replies", identifier: .standardReplies),
			Capability.capability(named: "userhost-in-names", identifier: .userhostInNames),
			Capability(
				name: "znc.in/playback",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.playback.rawValue | zncPlaybackModule.rawValue
				),
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: nil,
				negotiationHook: nil
			),
			Capability.capability(named: "znc.in/self-message", identifier: .zncSelfMessage),
			Capability(
				name: "znc.in/server-time",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.serverTime.rawValue | zncServerTime.rawValue
				),
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: nil,
				negotiationHook: nil
			),
			Capability(
				name: "znc.in/server-time-iso",
				identifier: ClientIRCv3SupportedCapability(
					rawValue: ClientIRCv3SupportedCapability.serverTime.rawValue | zncServerTimeISO.rawValue
				),
				requestedByDefault: true,
				preferenceGate: nil,
				dependencies: nil,
				negotiationHook: nil
			),
			Capability.capability(named: "znc.in/tlsinfo", identifier: .zncCertInfoModule),
		]
	}
}
