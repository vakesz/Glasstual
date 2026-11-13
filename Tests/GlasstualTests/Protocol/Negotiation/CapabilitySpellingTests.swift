@testable import Glasstual
import Testing

/// IRCv3 capability names are case-sensitive, so a name is matched — and echoed
/// back in `CAP REQ` — exactly as the server advertised it.
@Suite("Capability spelling")
@MainActor
struct CapabilitySpellingTests {
	@Test("A name keeps the spelling the server used")
	func namesKeepTheirSpelling() {
		let offered = CapabilityRegistry.parseCapabilityList("sasl=PLAIN Multi-Prefix")

		#expect(offered["sasl"] == ["PLAIN"])
		#expect(offered["Multi-Prefix"] != nil)
		/* Folding the case here would have made these one capability, and the
		 session would then request a spelling the server never offered. */
		#expect(offered["multi-prefix"] == nil)
		#expect(offered["SASL"] == nil)
	}

	@Test("A capability offered under a different case is not the one we know")
	func differentCaseIsADifferentCapability() {
		let registry = CapabilityRegistry.defaultRegistry
		let settings = ChatSettings()

		#expect(registry.capability(named: "multi-prefix") != nil)
		#expect(registry.capability(named: "Multi-Prefix") == nil)
		#expect(registry.isCapabilitySupported("SASL", settings: settings) == false)
	}

	@Test("An empty list yields no names")
	func emptyListYieldsNoNames() {
		#expect(CapabilityRegistry.parseCapabilityList("").isEmpty)
	}

	@Test("A token with no name is ignored")
	func namelessTokenIsIgnored() {
		#expect(CapabilityRegistry.parseCapabilityList("=bad sasl") == ["sasl": []])
	}

	// MARK: - pre-away

	@Test("pre-away is declared under its draft name and accepted under the bare one")
	func preAwayHasTwoSpellings() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let draft = try #require(registry.capability(named: "draft/pre-away"))
		let bare = try #require(registry.capability(named: "pre-away"))

		#expect(draft.identifier == .preAway)
		#expect(bare.identifier == .preAway)
		#expect(draft.aliasOf == nil)
		#expect(bare.aliasOf == "draft/pre-away")
		#expect(registry.capabilities.filter { $0.identifier == .preAway && $0.aliasOf == nil }.count == 1)
	}

	@Test("A switch-off stored under the bare name also turns off the draft spelling")
	func bareSwitchOffCoversTheDraftName() {
		let registry = CapabilityRegistry.defaultRegistry
		var settings = ChatSettings()

		settings.disabledCapabilities = ["pre-away"]

		#expect(registry.isCapabilitySupported("draft/pre-away", settings: settings) == false)
		#expect(registry.isCapabilitySupported("pre-away", settings: settings) == false)
		#expect(registry.capabilitiesToRequest(
			fromOffered: ["draft/pre-away": [], "pre-away": []], settings: settings
		).isEmpty)
	}

	@Test("A switch-off stored under the draft name also turns off the bare spelling")
	func draftSwitchOffCoversTheBareName() {
		let registry = CapabilityRegistry.defaultRegistry
		var settings = ChatSettings()

		settings.disabledCapabilities = ["draft/pre-away"]

		#expect(registry.isCapabilitySupported("pre-away", settings: settings) == false)
		#expect(registry.isCapabilitySupported("draft/pre-away", settings: settings) == false)
	}

	@Test("Both spellings are on by default and neither switch-off touches other capabilities")
	func preAwaySwitchOffIsScoped() {
		let registry = CapabilityRegistry.defaultRegistry
		var settings = ChatSettings()

		#expect(registry.isCapabilitySupported("draft/pre-away", settings: settings))
		#expect(registry.isCapabilitySupported("pre-away", settings: settings))

		settings.disabledCapabilities = ["pre-away"]

		#expect(registry.isCapabilitySupported("away-notify", settings: settings))
	}

	@Test("The spellings of a feature are the names its one switch covers")
	func spellingsShareOneSwitch() throws {
		let registry = CapabilityRegistry.defaultRegistry
		let draft = try #require(registry.capability(named: "draft/pre-away"))
		let bare = try #require(registry.capability(named: "pre-away"))

		#expect(registry.spellings(of: draft) == ["draft/pre-away", "pre-away"])
		#expect(registry.spellings(of: bare) == ["draft/pre-away", "pre-away"])

		let batch = try #require(registry.capability(named: "batch"))

		#expect(registry.spellings(of: batch) == ["batch"])
	}
}
