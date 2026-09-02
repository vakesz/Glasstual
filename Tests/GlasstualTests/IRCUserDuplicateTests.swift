import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

/** `User` and `ChannelUser` are values now: a copy is what an edit starts from,
 and the directory and the member list swap the stored copy for the edited one
 rather than editing what a caller happens to be holding. `id` is what makes
 that swap land on the same person. */
@MainActor
struct IRCUserDuplicateTests {
	@Test("An edit made through the directory carries every field and stays the same person")
	func editingThroughTheDirectoryCarriesEveryField() throws {
		let client = GLTTestClient()
		let user = client.findUserOrCreate("Alice")

		client.modify(user) { edited in
			edited.username = "alice"
			edited.address = "example.net"
			edited.realName = "Alice"
			edited.account = "alice-account"
			edited.isIRCop = true
			edited.isBot = true
			edited.isAway = true
		}

		let stored = try #require(client.findUser("Alice"))

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
		let client = GLTTestClient()
		let original = client.findUserOrCreate("Alice")

		client.rename(original, to: "Bob")

		#expect(client.findUser("Alice") == nil)
		#expect(client.findUser("Bob")?.nickname == "Bob")
		#expect(client.findUser("Bob")?.id == original.id)
		#expect(client.numberOfUsers == 1)
	}

	@Test("Replacing a member stores the edited copy")
	func replacingAMemberStoresTheEditedCopy() throws {
		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#chat", type: .channel))
		channel.associatedClient = client

		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let user = client.findUserOrCreate("alice")
		let member = ChannelUser(user: user, prefixes: client.currentUserPrefixes)
		memberList.addMember(member)

		var edited = member
		edited.modes = "o"
		memberList.replaceMember(member, with: edited)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList.first?.modes == "o")
		#expect(client.userAssociated(user, with: channel)?.modes == "o")
		#expect(member.modes.isEmpty)
	}

	@Test("A rename reaches the member every channel holds for the person")
	func renamingRelinksTheMemberLists() throws {
		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#chat", type: .channel))
		channel.associatedClient = client

		channel.activate()
		let memberList = try #require(channel.memberInfo)
		let user = client.findUserOrCreate("Alice")
		memberList.addMember(ChannelUser(user: user, prefixes: client.currentUserPrefixes))

		client.rename(user, to: "Bob")

		#expect(memberList.findMember(withUserID: user.id)?.user.nickname == "Bob")
	}
}
