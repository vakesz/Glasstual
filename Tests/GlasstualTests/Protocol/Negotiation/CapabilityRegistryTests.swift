// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
		"echo-message",
		"message-tags",
		"multi-prefix",
		"sasl",
		"server-time",
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

	@Test("The default registry does not carry the retired capabilities")
	func defaultRegistryDropsRetiredCapabilities() {
		let registry = CapabilityRegistry.defaultRegistry

		#expect(registry.capability(named: "identify-msg") == nil)
		#expect(registry.capability(named: "identify-ctcp") == nil)
		#expect(registry.capability(named: "plan.io/playback") == nil)
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
}
