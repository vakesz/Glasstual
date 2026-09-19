import Foundation
@testable import Glasstual
import Testing

/** `User` and `Member` are values now: a copy is what an edit starts from,
 and the directory and the member list swap the stored copy for the edited one
 rather than editing what a caller happens to be holding. `id` is what makes
 that swap land on the same person. */
@MainActor
struct UserDuplicateTests {
	@Test("An edit made through the directory carries every field and stays the same person")
	func editingThroughTheDirectoryCarriesEveryField() throws {
		let session = TestServerSession()
		let user = session.findUserOrCreate("Alice")

		session.modify(user) { edited in
			edited.username = "alice"
			edited.address = "example.net"
			edited.realName = "Alice"
			edited.account = "alice-account"
			edited.isIRCop = true
			edited.isBot = true
			edited.isAway = true
		}

		let stored = try #require(session.findUser("Alice"))

		#expect(stored.id == user.id)
		#expect(stored.nickname == "Alice")
		#expect(stored.username == "alice")
		#expect(stored.address == "example.net")
		#expect(stored.realName == "Alice")
		#expect(stored.account == "alice-account")
		#expect(stored.isIRCop)
		#expect(stored.isBot)
		#expect(stored.isAway)

		/* The caller's own handle still holds what it did before the edit, so
		 the directory is the only place the new state lives. */
		#expect(user.username == nil)
	}

	@Test("Renaming through the directory rekeys it and keeps the person")
	func renamingRekeysTheDirectory() {
		let session = TestServerSession()
		let original = session.findUserOrCreate("Alice")

		session.rename(original, to: "Bob")

		#expect(session.findUser("Alice") == nil)
		#expect(session.findUser("Bob")?.nickname == "Bob")
		#expect(session.findUser("Bob")?.id == original.id)
		#expect(session.numberOfUsers == 1)
	}

	@Test("Replacing a member stores the edited copy")
	func replacingAMemberStoresTheEditedCopy() throws {
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session

		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let user = session.findUserOrCreate("alice")
		let member = Member(user: user, prefixes: session.currentUserPrefixes)
		memberList.addMember(member)

		var edited = member
		edited.modes = "o"
		memberList.replaceMember(member, with: edited)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList.first?.modes == "o")
		#expect(session.userAssociated(user, with: channel)?.modes == "o")
		#expect(member.modes.isEmpty)
	}

	@Test("A rename reaches the member every channel holds for the person")
	func renamingRelinksTheMemberLists() throws {
		let session = TestServerSession()
		let channel = Conversation(config: ConversationConfig(name: "#chat", type: .channel))
		channel.associatedSession = session

		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let user = session.findUserOrCreate("Alice")
		memberList.addMember(Member(user: user, prefixes: session.currentUserPrefixes))

		session.rename(user, to: "Bob")

		#expect(memberList.findMember(withUserID: user.id)?.user.nickname == "Bob")
	}
}
