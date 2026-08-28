@testable import Glasstual
import Testing

/// IRCv3 capability names are case-sensitive on the wire, so what the client
/// echoes back in `CAP REQ` has to be what the server advertised.
@Suite("Capability spelling")
@MainActor
struct IRCCapabilitySpellingTests {
	@Test("Matching stays case-insensitive")
	func matchingIsCaseInsensitive() {
		let offered = CapabilityRegistry.parseCapabilityList("SASL=PLAIN Multi-Prefix")

		#expect(offered["sasl"] == ["PLAIN"])
		#expect(offered["multi-prefix"] != nil)
	}

	@Test("The advertised spelling is recorded against the lowercased name")
	func offeredSpellingIsRecorded() {
		let names = CapabilityRegistry.offeredNames(fromCapabilityList: "SASL=PLAIN Multi-Prefix draft/chathistory")

		#expect(names["sasl"] == "SASL")
		#expect(names["multi-prefix"] == "Multi-Prefix")
		#expect(names["draft/chathistory"] == "draft/chathistory")
	}

	@Test("An empty list yields no names")
	func emptyListYieldsNoNames() {
		#expect(CapabilityRegistry.offeredNames(fromCapabilityList: "").isEmpty)
	}

	@Test("A token with no name is ignored")
	func namelessTokenIsIgnored() {
		let names = CapabilityRegistry.offeredNames(fromCapabilityList: "=bad sasl")

		#expect(names == ["sasl": "sasl"])
	}

	@Test("The names and the values describe the same set")
	func namesAndValuesAgree() {
		let list = "sasl=PLAIN,EXTERNAL Away-Notify batch"
		let offered = CapabilityRegistry.parseCapabilityList(list)
		let names = CapabilityRegistry.offeredNames(fromCapabilityList: list)

		#expect(Set(offered.keys) == Set(names.keys))
	}
}
