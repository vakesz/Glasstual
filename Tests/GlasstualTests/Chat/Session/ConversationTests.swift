import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Conversation kinds and configuration")
struct ConversationTests {
	@Test("A channel is renamed only where the kind allows it")
	func onlyConversationKindsAllowExpectedMutableProperties() {
		let channel = makeChannel(name: "#original", type: .channel)
		channel.name = "#renamed"
		channel.autoJoin = false

		#expect(channel.name == "#original")
		#expect(channel.autoJoin == false)

		let query = makeChannel(name: "old-nick", type: .direct)
		query.name = "new-nick"
		query.autoJoin = false

		#expect(query.name == "new-nick")
		#expect(query.autoJoin)
	}

	@Test("A config belonging to another channel is refused")
	func configUpdateRejectsAnotherChannelIdentity() {
		let channel = makeChannel(name: "#one", type: .channel)
		let originalIdentifier = channel.uniqueIdentifier
		let replacement = ConversationConfig(name: "#two")

		channel.updateConfig(replacement)

		#expect(channel.name == "#one")
		#expect(channel.uniqueIdentifier == originalIdentifier)
	}

	@Test("A renamed configuration is accepted only where the kind is named after its peer")
	func configUpdateRenamesOnlyPeerNamedKinds() {
		let channel = makeChannel(name: "#one", type: .channel)
		var renamedChannel = channel.config
		renamedChannel.name = "#two"

		channel.updateConfig(renamedChannel)

		#expect(channel.name == "#one")

		let query = makeChannel(name: "old-nick", type: .direct)
		var renamedQuery = query.config
		renamedQuery.name = "new-nick"

		query.updateConfig(renamedQuery)

		#expect(query.name == "new-nick")
	}

	@Test("Renaming a query tells observers the configuration changed")
	func renamingAQueryPostsTheConfigurationNotification() async {
		let query = makeChannel(name: "old-nick", type: .direct)
		let (notices, continuation) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
		let observer = NotificationCenter.default.addObserver(
			forName: .conversationConfigWasUpdated,
			object: query,
			queue: nil
		) { _ in continuation.yield() }
		defer { NotificationCenter.default.removeObserver(observer) }

		query.name = "new-nick"
		continuation.finish()

		var posted = false
		for await _ in notices {
			posted = true
		}

		#expect(query.name == "new-nick")
		#expect(posted)
	}

	@Test("Resetting the status cannot leave a channel mid-join")
	func joiningStatusCannotBeAppliedByReset() {
		let channel = makeChannel(type: .channel)

		channel.resetStatus(.joining)

		#expect(channel.status == .parted)
		#expect(channel.isActive == false)
	}

	@Test("Joining records when it happened, on the clock the caller supplies")
	func activationRecordsTheJoinTime() {
		let channel = makeChannel(type: .channel)
		let joinedAt = Date(timeIntervalSince1970: 1_700_000_000)

		#expect(channel.joinedAt == nil)

		channel.activate(at: joinedAt)

		#expect(channel.joinedAt == joinedAt)
	}

	@Test("Leaving forgets the join time, so a parted channel replays nothing")
	func deactivationClearsTheJoinTime() {
		let channel = makeChannel(type: .channel)

		channel.activate(at: Date(timeIntervalSince1970: 1_700_000_000))
		channel.deactivate()

		#expect(channel.joinedAt == nil)
	}

	@Test("Rejoining replaces the join time rather than keeping the first one")
	func rejoiningReplacesTheJoinTime() {
		let channel = makeChannel(type: .channel)
		let second = Date(timeIntervalSince1970: 1_700_000_060)

		channel.activate(at: Date(timeIntervalSince1970: 1_700_000_000))
		channel.deactivate()
		channel.activate(at: second)

		#expect(channel.joinedAt == second)
	}

	@Test("A channel that was never joined has no members")
	func inactiveChannelHasNoMembers() {
		let channel = makeChannel(name: "#inactive", type: .channel)

		#expect(channel.memberInfo == nil)
		#expect(channel.memberList.isEmpty)
		#expect(channel.findMember("nobody") == nil)
		#expect(channel.numberOfMembers == 0)
	}

	private func makeChannel(
		name: String = "#channel",
		type: ConversationKind
	) -> Conversation {
		Conversation(config: ConversationConfig(name: name, type: type))
	}
}
