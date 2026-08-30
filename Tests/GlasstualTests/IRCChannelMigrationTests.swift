@testable import Glasstual
import GlasstualPluginKit
import Testing

@MainActor
@Suite("Channel kinds and configuration")
struct IRCChannelMigrationTests {
	@Test("Each channel kind names itself the way the renderer expects")
	func channelKindsExposeStableRendererNames() {
		#expect(makeChannel(type: .channel).channelTypeString == "channel")
		#expect(makeChannel(type: .privateMessage).channelTypeString == "query")
		#expect(makeChannel(type: .utility).channelTypeString == "utility")
		#expect(makeChannel(type: .directChat).channelTypeString == "direct-chat")
	}

	@Test("A channel is renamed only where the kind allows it")
	func onlyConversationKindsAllowExpectedMutableProperties() {
		let channel = makeChannel(name: "#original", type: .channel)
		channel.name = "#renamed"
		channel.autoJoin = false

		#expect(channel.name == "#original")
		#expect(channel.autoJoin == false)

		let query = makeChannel(name: "old-nick", type: .privateMessage)
		query.name = "new-nick"
		query.autoJoin = false

		#expect(query.name == "new-nick")
		#expect(query.autoJoin)
	}

	@Test("A config belonging to another channel is refused")
	func configUpdateRejectsAnotherChannelIdentity() {
		let channel = makeChannel(name: "#one", type: .channel)
		let originalIdentifier = channel.uniqueIdentifier
		let replacement = ChannelConfig(channelName: "#two")

		channel.updateConfig(replacement)

		#expect(channel.name == "#one")
		#expect(channel.uniqueIdentifier == originalIdentifier)
	}

	@Test("Resetting the status cannot leave a channel mid-join")
	func joiningStatusCannotBeAppliedByReset() {
		let channel = makeChannel(type: .channel)

		channel.resetStatus(.joining)

		#expect(channel.status == .parted)
		#expect(channel.isActive == false)
	}

	private func makeChannel(
		name: String = "#channel",
		type: ChannelType
	) -> Channel {
		Channel(config: ChannelConfig(channelName: name, type: type))
	}
}
