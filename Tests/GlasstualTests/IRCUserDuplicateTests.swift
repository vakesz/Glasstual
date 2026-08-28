import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

/** `User` and `ChannelUser` are identified by object identity, so the retired
 mutable subclasses became `duplicate()`. What matters is that the directory and
 the member list still swap the stored instance for the edited one rather than
 editing what they hold. */
@MainActor
struct IRCUserDuplicateTests {
	@Test("A duplicate carries every field and is a distinct object")
	func duplicateCarriesEveryField() {
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

		let stored = client.findUser("Alice")
		let copy = stored?.duplicate()

		#expect(copy !== stored)
		#expect(copy?.nickname == "Alice")
		#expect(copy?.username == "alice")
		#expect(copy?.address == "example.net")
		#expect(copy?.realName == "Alice")
		#expect(copy?.account == "alice-account")
		#expect(copy?.isIRCop == true)
		#expect(copy?.isBot == true)
		#expect(copy?.isAway == true)
		#expect(copy?.client === client)
	}

	@Test("Editing a duplicate does not touch the stored user")
	func duplicatesAreIndependent() {
		let client = GLTTestClient()
		let user = client.findUserOrCreate("Alice")

		let copy = user.duplicate()
		copy.nickname = "Bob"

		#expect(user.nickname == "Alice")
		#expect(client.findUser("Alice") === user)
		#expect(client.findUser("Bob") == nil)
	}

	@Test("Renaming through the directory rekeys it and drops the old nickname")
	func renamingRekeysTheDirectory() {
		let client = GLTTestClient()
		let original = client.findUserOrCreate("Alice")

		client.rename(original, to: "Bob")

		#expect(client.findUser("Alice") == nil)
		#expect(client.findUser("Bob")?.nickname == "Bob")
		#expect(client.numberOfUsers == 1)
	}

	@Test("Replacing a member with its duplicate swaps the stored instance")
	func replacingAMemberStoresTheDuplicate() {
		let client = GLTTestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#chat", type: .channel))
		channel.setValue(client, forKey: "associatedClient")

		let memberList = ChannelMemberList(channel: channel)
		let user = User(nickname: "alice", on: client)
		let member = ChannelUser(user: user)
		memberList.addMember(member)

		let edited = member.duplicate()
		edited.modes = "o"
		memberList.replaceMember(member, with: edited)

		#expect(memberList.numberOfMembers == 1)
		#expect(memberList.memberList.first === edited)
		#expect(user.userAssociated(with: channel) === edited)
		#expect(member.modes.isEmpty)
	}

	@Test("A member duplicate keeps the same user and carries the modes")
	func memberDuplicateKeepsTheUser() {
		let client = GLTTestClient()
		let user = client.findUserOrCreate("Alice")
		let member = ChannelUser(user: user)
		member.modes = "ov"

		let copy = member.duplicate()
		copy.modes = "v"

		#expect(copy !== member)
		#expect(copy.user === user)
		#expect(member.modes == "ov")
		#expect(copy.modes == "v")
	}
}
