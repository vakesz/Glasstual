@testable import Glasstual
import Testing

/// `Prefix` used to be an immutable class with a mutable subclass; it is now a
/// value carried by `Message`.
@MainActor
struct IRCPrefixValueTests {
	@Test("A default prefix is empty rather than nil")
	func defaultsAreEmpty() {
		let prefix = Prefix()

		#expect(prefix.isServer == false)
		#expect(prefix.nickname == "")
		#expect(prefix.hostmask == "")
		#expect(prefix.username == nil)
		#expect(prefix.address == nil)
	}

	@Test("A user prefix parsed from the wire keeps every component")
	func parsedUserPrefixKeepsEveryComponent() throws {
		let message = try #require(Message(line: ":nick!user@host PRIVMSG #channel :hello"))

		#expect(message.sender.nickname == "nick")
		#expect(message.sender.username == "user")
		#expect(message.sender.address == "host")
		#expect(message.sender.hostmask == "nick!user@host")
		#expect(message.sender.isServer == false)
	}

	@Test("A server prefix is marked as one")
	func serverPrefixIsMarked() throws {
		let message = try #require(Message(line: ":irc.example.net 001 me :Welcome"))

		#expect(message.sender.isServer)
		#expect(message.sender.nickname == "irc.example.net")
		#expect(message.sender.username == nil)
	}

	@Test("Copying a prefix and editing the copy leaves the original alone")
	func copiesAreIndependent() {
		let original = Prefix(nickname: "nick", username: "user", address: "host", hostmask: "nick!user@host")

		var changed = original
		changed.nickname = "other"
		changed.isServer = true

		#expect(original.nickname == "nick")
		#expect(original.isServer == false)
		#expect(changed.nickname == "other")
		#expect(original != changed)
	}
}
