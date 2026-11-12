// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("IRCv3 capability registry")
struct CapabilityRegistryTests {
	private func registry() -> CapabilityRegistry {
		let tags = Capability.capability(
			named: "message-tags",
			identifier: CapabilitySet.messageTags
		)
		let gated = Capability(
			name: "echo-message",
			identifier: CapabilitySet.echoMessage,
			requestedByDefault: true,
			gate: .echoMessage
		)
		let dependent = Capability(
			name: "draft/typing",
			identifier: [],
			requestedByDefault: true,
			dependencies: ["message-tags"]
		)
		let optional = Capability.capability(named: "draft/opt-in", identifier: [], requestedByDefault: false)

		return CapabilityRegistry(capabilities: [tags, gated, dependent, optional])
	}

	private func settings(echoMessage: Bool = true) -> ChatSettings {
		var settings = ChatSettings()
		settings.enableEchoMessageCapability = echoMessage
		return settings
	}

	@Test("A CAP list is split into names and their comma separated values")
	func parseCapabilityList() {
		let offered = CapabilityRegistry.parseCapabilityList("multi-prefix sasl=PLAIN,EXTERNAL  cap-notify x=")

		#expect(offered["multi-prefix"] == [])
		#expect(offered["sasl"] == ["PLAIN", "EXTERNAL"])
		#expect(offered["cap-notify"] == [])
		#expect(offered["x"] == [])
		#expect(offered.count == 4)
		#expect(CapabilityRegistry.parseCapabilityList("").isEmpty)
	}

	@Test("A repeated name takes its last value and empty names and values are dropped")
	func parseCapabilityListUsesLastDuplicateAndIgnoresEmptyNamesAndValues() {
		let offered = CapabilityRegistry.parseCapabilityList("sasl=PLAIN sasl=EXTERNAL,,SCRAM-SHA-256 =bad")

		#expect(offered["sasl"] == ["EXTERNAL", "SCRAM-SHA-256"])
		#expect(offered.count == 1)
	}

	@Test("Capabilities are looked up by their exact name, or by identifier")
	func lookupIsByExactName() {
		let registry = registry()

		#expect(registry.capability(named: "message-tags")?.name == "message-tags")
		/* IRCv3 makes capability names case-sensitive. */
		#expect(registry.capability(named: "Message-Tags") == nil)
		#expect(registry.capability(named: "unknown") == nil)
		#expect(registry.capability(for: .echoMessage)?.name == "echo-message")
		#expect(registry.capability(for: CapabilitySet.batch) == nil)
	}

	@Test("A capability whose preference gate is closed is neither requested nor supported")
	func requestListRespectsPreferenceGate() {
		let offered: [String: [String]] = ["message-tags": [], "echo-message": []]
		let registry = registry()
		let allowed = registry.capabilitiesToRequest(
			fromOffered: offered,
			settings: settings()
		)

		#expect(allowed.map(\.name) == ["message-tags", "echo-message"])

		let deniedSettings = settings(echoMessage: false)
		let denied = registry.capabilitiesToRequest(
			fromOffered: offered,
			settings: deniedSettings
		)

		#expect(denied.map(\.name) == ["message-tags"])
		#expect(registry.isCapabilitySupported("echo-message", settings: settings()))
		#expect(registry.isCapabilitySupported("echo-message", settings: deniedSettings) == false)
	}

	@Test("A capability the user switched off is neither requested nor supported")
	func requestListRespectsDisabledCapabilities() {
		let registry = registry()
		var settings = settings()
		settings.disabledCapabilities = ["echo-message"]

		let offered: [String: [String]] = ["message-tags": [], "echo-message": []]
		let allowed = registry.capabilitiesToRequest(fromOffered: offered, settings: settings)

		#expect(allowed.map(\.name) == ["message-tags"])
		#expect(registry.isCapabilitySupported("echo-message", settings: settings) == false)
		#expect(registry.isCapabilitySupported("message-tags", settings: settings))
	}

	/** Switching a capability off has to take everything built on top of it
	 with it: `draft/typing` without `message-tags` is a request the server
	 would answer with tagged messages the session asked not to receive. */
	@Test("Switching a capability off also stops the capabilities that depend on it")
	func disabledDependenciesDisableTheirDependents() {
		let registry = registry()
		let offered: [String: [String]] = ["message-tags": [], "draft/typing": []]
		var settings = settings()

		#expect(registry.capabilitiesToRequest(
			fromOffered: offered,
			settings: settings
		).map(\.name) == ["message-tags", "draft/typing"])

		settings.disabledCapabilities = ["message-tags"]

		#expect(registry.capabilitiesToRequest(fromOffered: offered, settings: settings).isEmpty)
	}

	@Test("A capability is requested only once everything it depends on is offered")
	func requestListRespectsDependencies() {
		let registry = registry()
		let settings = settings()
		let withoutTags = registry.capabilitiesToRequest(
			fromOffered: ["draft/typing": []],
			settings: settings
		)

		#expect(withoutTags.isEmpty)

		let withTags = registry.capabilitiesToRequest(
			fromOffered: [
				"draft/typing": [],
				"message-tags": [],
			],
			settings: settings
		)

		#expect(withTags.map(\.name) == ["message-tags", "draft/typing"])
	}

	@Test("A capability that is not requested by default is skipped")
	func capabilitiesNotRequestedByDefaultAreSkipped() {
		let registry = registry()

		#expect(registry.capabilitiesToRequest(
			fromOffered: ["draft/opt-in": []],
			settings: settings()
		).isEmpty)
	}

	@Test("A capability the registry does not know is never requested")
	func unknownCapabilitiesAreNeverRequested() {
		let registry = registry()

		#expect(registry.capabilitiesToRequest(
			fromOffered: ["example.com/vendor": []],
			settings: settings()
		).isEmpty)
	}

	@Test("Capabilities that depend on each other are never requested")
	func cyclicDependenciesAreNeverRequested() {
		let first = Capability(
			name: "first",
			identifier: [],
			requestedByDefault: true,
			dependencies: ["second"]
		)
		let second = Capability(
			name: "second",
			identifier: [],
			requestedByDefault: true,
			dependencies: ["first"]
		)
		let registry = CapabilityRegistry(capabilities: [first, second])
		let offered: [String: [String]] = ["first": [], "second": []]

		#expect(registry.capabilitiesToRequest(
			fromOffered: offered,
			settings: settings()
		).isEmpty)
	}

	@Test("The default registry carries every capability the session negotiates", arguments: [
		"away-notify",
		"batch",
		"cap-notify",
		"chghost",
		"draft/channel-rename",
		"draft/extended-isupport",
		"draft/message-redaction",
		"draft/multiline",
		"draft/no-implicit-names",
		"echo-message",
		"message-tags",
		"multi-prefix",
		"sasl",
		"server-time",
		"soju.im/bouncer-networks",
		"soju.im/bouncer-networks-notify",
		"standard-replies",
		"userhost-in-names",
		"znc.in/playback",
		"znc.in/self-message",
		"znc.in/server-time",
		"znc.in/server-time-iso",
		"znc.in/tlsinfo",
	])
	func defaultRegistryOffersCapability(_ name: String) {
		#expect(CapabilityRegistry.defaultRegistry.capability(named: name) != nil, "\(name) is missing")
	}

	/** A bit two capabilities shared would turn one on whenever the other was
	 acknowledged. Only an alias carries its primary's bits, and only a vendor
	 variant carries the bit of the standard capability it stands in for. */
	@Test("Every capability owns a bit no unrelated capability or session fact uses")
	func capabilityBitsAreDistinct() {
		let entries = CapabilityRegistry.defaultRegistry.capabilities.filter { $0.identifier.isEmpty == false }
		let standalone = Set(entries.map(\.identifier.rawValue))
		for (index, first) in entries.enumerated() {
			for second in entries[(index + 1)...] where first.identifier.isDisjoint(with: second.identifier) == false {
				let shared = first.identifier.intersection(second.identifier)
				let isAlias = first.identifier == second.identifier
					&& (first.aliasOf == second.name || second.aliasOf == first.name
						|| (first.aliasOf != nil && first.aliasOf == second.aliasOf))
				let isVariant = first.identifier != second.identifier && standalone.contains(shared.rawValue)
				#expect(isAlias || isVariant, "\(first.name) and \(second.name) share a bit")
			}
		}
		let facts: CapabilitySet = [.isIdentifiedWithSASL, .isInSASLNegotiation, .monitorCommand, .watchCommand]
		#expect(entries.allSatisfy { $0.identifier.isDisjoint(with: facts) })
	}

	@Test("Account registration, metadata and extended ISUPPORT each own one bit")
	func recentCapabilitiesOwnTheirBits() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let names = ["draft/account-registration", "draft/metadata-2", "draft/extended-isupport"]
		let identifiers = try names.map { try #require(registry.capability(named: $0)).identifier }

		#expect(identifiers == [.accountRegistration, .metadata, .extendedISupport])
		#expect(identifiers.allSatisfy { $0.rawValue.nonzeroBitCount == 1 })
		#expect(Set(identifiers.map(\.rawValue)).count == names.count)
	}

	@Test("Channel rename depends on nothing and owns a bit no other capability uses")
	func channelRenameIsIndependent() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let rename = try #require(registry.capability(named: "draft/channel-rename"))

		#expect(rename.dependencies.isEmpty)
		#expect(rename.identifier == .channelRename)
		#expect(rename.identifier.rawValue.nonzeroBitCount == 1)
		let others = registry.capabilities.filter { $0.name != rename.name }
		#expect(others.allSatisfy { $0.identifier.isDisjoint(with: rename.identifier) })
		#expect(rename.specification?.absoluteString == "https://ircv3.net/specs/extensions/channel-rename")
	}

	@Test("Bouncer networks need batch, notifications need the listing, and each owns a bit")
	func bouncerNetworksDependencies() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let networks = try #require(registry.capability(named: "soju.im/bouncer-networks"))
		let notify = try #require(registry.capability(named: "soju.im/bouncer-networks-notify"))

		#expect(networks.dependencies == ["batch"])
		#expect(notify.dependencies == ["soju.im/bouncer-networks"])
		#expect(networks.identifier == .bouncerNetworks)
		#expect(notify.identifier == .bouncerNetworksNotify)
		for capability in [networks, notify] {
			#expect(capability.identifier.rawValue.nonzeroBitCount == 1)
			let others = registry.capabilities.filter { $0.name != capability.name }
			#expect(others.allSatisfy { $0.identifier.isDisjoint(with: capability.identifier) })
		}
		#expect(networks.specification?.host == "git.sr.ht")
	}

	@Test("Notifications are eligible once the listing is enabled, and the listing needs batch")
	func bouncerNotificationsWaitForTheirDependencies() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let networks = try #require(registry.capability(named: "soju.im/bouncer-networks"))
		let notify = try #require(registry.capability(named: "soju.im/bouncer-networks-notify"))

		#expect(registry.dependenciesSatisfied(for: networks, by: []) == false)
		#expect(registry.dependenciesSatisfied(for: networks, by: [.batch]))
		#expect(registry.dependenciesSatisfied(for: notify, by: [.batch]) == false)
		#expect(registry.dependenciesSatisfied(for: notify, by: [.bouncerNetworks]))
	}

	@Test("A bouncer that offers the listing without batch is not asked for it")
	func bouncerListingNeedsBatchOffered() {
		let registry = CapabilityRegistry.defaultRegistry

		#expect(registry.capabilitiesToRequest(fromOffered: ["soju.im/bouncer-networks": []], settings: settings()).isEmpty)
		#expect(registry.capabilitiesToRequest(
			fromOffered: ["batch": [], "soju.im/bouncer-networks": []], settings: settings()
		).map(\.name) == ["batch", "soju.im/bouncer-networks"])
	}

	@Test("The default registry does not carry the retired capabilities")
	func defaultRegistryDropsRetiredCapabilities() {
		let registry = CapabilityRegistry.defaultRegistry

		#expect(registry.capability(named: "identify-msg") == nil)
		#expect(registry.capability(named: "identify-ctcp") == nil)
		#expect(registry.capability(named: "plan.io/playback") == nil)
	}

	@Test(
		"Draft extensions cannot negotiate their reserved future capability names",
		arguments: ["chathistory", "read-marker", "message-redaction"]
	)
	func draftCapabilityNamesRemainPrefixed(_ name: String) {
		let registry = CapabilityRegistry.defaultRegistry
		#expect(registry.capability(named: name) == nil)
		#expect(registry.capability(named: "draft/" + name) != nil)
	}

	@Test("SASL has typed negotiation and vendor variants set the generic bit")
	func defaultRegistryVendorVariantsCarryTheGenericBit() throws {
		let registry = CapabilityRegistry.defaultRegistry

		#expect(registry.capability(named: "sasl")?.negotiation == .sasl)

		/* Vendor variants switch on the generic bit too. */
		let zncServerTime = try #require(registry.capability(named: "znc.in/server-time-iso")?.identifier)

		#expect(zncServerTime.contains(.serverTime))

		let zncPlayback = try #require(registry.capability(named: "znc.in/playback")?.identifier)

		#expect(zncPlayback.contains(.playback))
	}

	@Test("extended-isupport is requested by default under its draft name only")
	func extendedISupportUsesTheDraftName() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let capability = try #require(registry.capability(named: "draft/extended-isupport"))

		#expect(capability.requestedByDefault)
		#expect(capability.dependencies.isEmpty)
		#expect(capability.identifier == .extendedISupport)
		#expect(registry.capability(named: "extended-isupport") == nil)
	}
}
