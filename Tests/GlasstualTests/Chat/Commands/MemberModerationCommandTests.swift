@testable import Glasstual
import Testing

@Suite("Member moderation commands")
struct MemberModerationCommandTests {
	@Test("A member menu item still sends the command the network expects")
	func memberCommandsPreserveLegacyWireFormat() {
		#expect(MemberModerationCommand.ignore("Alice") == "ignore Alice")
		#expect(MemberModerationCommand.unignore("Alice") == "unignore Alice")
		#expect(MemberModerationCommand.mode("HALFOP", nicknames: ["Alice", "Bob"]) == "HALFOP Alice Bob")
		#expect(MemberModerationCommand.kickban("Alice", reason: "Requested") == "KICKBAN Alice Requested")
		#expect(
			MemberModerationCommand.operatorCommand("GLINE", nickname: "Alice", reason: "Abuse")
				== "GLINE Alice Abuse"
		)
		#expect(MemberModerationCommand.setVhost("staff.example", nickname: "Alice") == "hs setall Alice staff.example")
	}
}
