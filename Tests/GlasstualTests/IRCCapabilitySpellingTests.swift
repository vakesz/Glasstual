@testable import Glasstual
import Testing

/// IRCv3 capability names are case-sensitive, so a name is matched — and echoed
/// back in `CAP REQ` — exactly as the server advertised it.
@Suite("Capability spelling")
@MainActor
struct IRCCapabilitySpellingTests {
	@Test("A name keeps the spelling the server used")
	func namesKeepTheirSpelling() {
		let offered = CapabilityRegistry.parseCapabilityList("sasl=PLAIN Multi-Prefix")

		#expect(offered["sasl"] == ["PLAIN"])
		#expect(offered["Multi-Prefix"] != nil)
		/* Folding the case here would have made these one capability, and the
		 client would then request a spelling the server never offered. */
		#expect(offered["multi-prefix"] == nil)
		#expect(offered["SASL"] == nil)
	}

	@Test("A capability offered under a different case is not the one we know")
	func differentCaseIsADifferentCapability() {
		let registry = CapabilityRegistry.defaultRegistry
		let preferences = ClientPreferences()

		#expect(registry.capability(named: "multi-prefix") != nil)
		#expect(registry.capability(named: "Multi-Prefix") == nil)
		#expect(registry.isCapabilitySupported("SASL", preferences: preferences) == false)
	}

	@Test("An empty list yields no names")
	func emptyListYieldsNoNames() {
		#expect(CapabilityRegistry.parseCapabilityList("").isEmpty)
	}

	@Test("A token with no name is ignored")
	func namelessTokenIsIgnored() {
		#expect(CapabilityRegistry.parseCapabilityList("=bad sasl") == ["sasl": []])
	}
}
