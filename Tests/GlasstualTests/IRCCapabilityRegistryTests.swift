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

@testable import Glasstual
import Testing

@MainActor
@Suite("IRCv3 capability registry")
struct IRCCapabilityRegistryTests {
	private func registry() -> CapabilityRegistry {
		let tags = Capability.capability(
			named: "message-tags",
			identifier: ClientIRCv3SupportedCapability.messageTags
		)
		let gated = Capability(
			name: "echo-message",
			identifier: ClientIRCv3SupportedCapability.echoMessage,
			requestedByDefault: true,
			preference: .echoMessage
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

	private func preferences(echoMessage: Bool = true) -> ClientPreferences {
		var preferences = ClientPreferences()
		preferences.enableEchoMessageCapability = echoMessage
		return preferences
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
		#expect(registry.capability(for: ClientIRCv3SupportedCapability.batch) == nil)
	}

	@Test("A capability whose preference gate is closed is neither requested nor supported")
	func requestListRespectsPreferenceGate() {
		let offered: [String: [String]] = ["message-tags": [], "echo-message": []]
		let registry = registry()
		let allowed = registry.capabilitiesToRequest(
			fromOffered: offered,
			preferences: preferences()
		)

		#expect(allowed.map(\.name) == ["message-tags", "echo-message"])

		let deniedPreferences = preferences(echoMessage: false)
		let denied = registry.capabilitiesToRequest(
			fromOffered: offered,
			preferences: deniedPreferences
		)

		#expect(denied.map(\.name) == ["message-tags"])
		#expect(registry.isCapabilitySupported("echo-message", preferences: preferences()))
		#expect(registry.isCapabilitySupported("echo-message", preferences: deniedPreferences) == false)
	}

	@Test("A capability the user switched off is neither requested nor supported")
	func requestListRespectsDisabledCapabilities() {
		let registry = registry()
		var preferences = preferences()
		preferences.disabledCapabilities = ["echo-message"]

		let offered: [String: [String]] = ["message-tags": [], "echo-message": []]
		let allowed = registry.capabilitiesToRequest(fromOffered: offered, preferences: preferences)

		#expect(allowed.map(\.name) == ["message-tags"])
		#expect(registry.isCapabilitySupported("echo-message", preferences: preferences) == false)
		#expect(registry.isCapabilitySupported("message-tags", preferences: preferences))
	}

	/** Switching a capability off has to take everything built on top of it
	 with it: `draft/typing` without `message-tags` is a request the server
	 would answer with tagged messages the client asked not to receive. */
	@Test("Switching a capability off also stops the capabilities that depend on it")
	func disabledDependenciesDisableTheirDependents() {
		let registry = registry()
		let offered: [String: [String]] = ["message-tags": [], "draft/typing": []]
		var preferences = preferences()

		#expect(registry.capabilitiesToRequest(
			fromOffered: offered,
			preferences: preferences
		).map(\.name) == ["message-tags", "draft/typing"])

		preferences.disabledCapabilities = ["message-tags"]

		#expect(registry.capabilitiesToRequest(fromOffered: offered, preferences: preferences).isEmpty)
	}

	@Test("A capability is requested only once everything it depends on is offered")
	func requestListRespectsDependencies() {
		let registry = registry()
		let preferences = preferences()
		let withoutTags = registry.capabilitiesToRequest(
			fromOffered: ["draft/typing": []],
			preferences: preferences
		)

		#expect(withoutTags.isEmpty)

		let withTags = registry.capabilitiesToRequest(
			fromOffered: [
				"draft/typing": [],
				"message-tags": [],
			],
			preferences: preferences
		)

		#expect(withTags.map(\.name) == ["message-tags", "draft/typing"])
	}

	@Test("A capability that is not requested by default is skipped")
	func capabilitiesNotRequestedByDefaultAreSkipped() {
		let registry = registry()

		#expect(registry.capabilitiesToRequest(
			fromOffered: ["draft/opt-in": []],
			preferences: preferences()
		).isEmpty)
	}

	@Test("A capability the registry does not know is never requested")
	func unknownCapabilitiesAreNeverRequested() {
		let registry = registry()

		#expect(registry.capabilitiesToRequest(
			fromOffered: ["example.com/vendor": []],
			preferences: preferences()
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
			preferences: preferences()
		).isEmpty)
	}

	@Test("The default registry carries every capability the client negotiates", arguments: [
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

	@Test("The default registry no longer carries the capabilities Textual retired")
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
