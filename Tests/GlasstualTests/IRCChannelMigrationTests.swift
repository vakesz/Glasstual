@testable import Glasstual
import GlasstualPluginKit
import XCTest

@MainActor
final class IRCChannelMigrationTests: XCTestCase {
	func testChannelKindsExposeStableRendererNames() {
		XCTAssertEqual(makeChannel(type: .channel).channelTypeString, "channel")
		XCTAssertEqual(makeChannel(type: .privateMessage).channelTypeString, "query")
		XCTAssertEqual(makeChannel(type: .utility).channelTypeString, "utility")
		XCTAssertEqual(makeChannel(type: .directChat).channelTypeString, "direct-chat")
	}

	func testOnlyConversationKindsAllowExpectedMutableProperties() {
		let channel = makeChannel(name: "#original", type: .channel)
		channel.name = "#renamed"
		channel.autoJoin = false

		XCTAssertEqual(channel.name, "#original")
		XCTAssertFalse(channel.autoJoin)

		let query = makeChannel(name: "old-nick", type: .privateMessage)
		query.name = "new-nick"
		query.autoJoin = false

		XCTAssertEqual(query.name, "new-nick")
		XCTAssertTrue(query.autoJoin)
	}

	func testConfigUpdateRejectsAnotherChannelIdentity() {
		let channel = makeChannel(name: "#one", type: .channel)
		let originalIdentifier = channel.uniqueIdentifier
		let replacement = ChannelConfig(channelName: "#two")

		channel.updateConfig(replacement)

		XCTAssertEqual(channel.name, "#one")
		XCTAssertEqual(channel.uniqueIdentifier, originalIdentifier)
	}

	func testJoiningStatusCannotBeAppliedByReset() {
		let channel = makeChannel(type: .channel)

		channel.resetStatus(.joining)

		XCTAssertEqual(channel.status, .parted)
		XCTAssertFalse(channel.isActive)
	}

	private func makeChannel(
		name: String = "#channel",
		type: ChannelType
	) -> Channel {
		Channel(config: ChannelConfig(channelName: name, type: type))
	}
}
