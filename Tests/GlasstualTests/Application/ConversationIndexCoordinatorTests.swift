// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Spotlight index coordinator")
struct ConversationIndexCoordinatorTests {
	private final class StubActions: IntentActions {
		var serverSnapshots: [IntentServerSnapshot] = [IntentServerSnapshot(id: "s1", name: "Libera", isConnected: true)]
		var conversationSnapshots: [IntentConversationSnapshot] = [
			IntentConversationSnapshot(id: "c1", serverID: "s1", serverName: "Libera", name: "#swift", kind: .channel),
			IntentConversationSnapshot(id: "c2", serverID: "s1", serverName: "Libera", name: "alice", kind: .directMessage),
		]

		func servers() -> [IntentServerSnapshot] {
			serverSnapshots
		}

		func conversations() -> [IntentConversationSnapshot] {
			conversationSnapshots
		}

		func sendMessage(_: String, toConversation _: String) async throws(IntentActionError) {}
		func joinChannel(_: String, onServer _: String) async throws(IntentActionError) {}
		func connect(server _: String) throws(IntentActionError) {}
		func disconnect(server _: String) throws(IntentActionError) {}
		func openConversation(id _: String) throws(IntentActionError) {}
	}

	private final class Fixture {
		let actions = StubActions()
		let writer = FakeConversationIndexWriter()
		var options = ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: false)
		var refreshCount = 0
		var coordinator: ConversationIndexCoordinator!

		init() {
			coordinator = ConversationIndexCoordinator(
				actions: actions,
				writer: writer,
				options: { [unowned self] in options },
				refreshShortcuts: { [unowned self] in refreshCount += 1 }
			)
		}
	}

	@Test("The shortcut parameters are refreshed once for a new set of names and not again for the same one")
	func refreshesOnlyOnChange() async {
		let fixture = Fixture()

		await fixture.coordinator.reconcile()
		#expect(fixture.refreshCount == 1)

		await fixture.coordinator.reconcile()
		#expect(fixture.refreshCount == 1)

		fixture.actions.conversationSnapshots.append(
			IntentConversationSnapshot(id: "c3", serverID: "s1", serverName: "Libera", name: "#macos", kind: .channel)
		)
		await fixture.coordinator.reconcile()
		#expect(fixture.refreshCount == 2)
	}

	@Test("A direct conversation the setting hides does not trigger a refresh")
	func hiddenDirectConversationIsIgnored() async {
		let fixture = Fixture()
		await fixture.coordinator.reconcile()

		fixture.actions.conversationSnapshots.append(
			IntentConversationSnapshot(id: "c4", serverID: "s1", serverName: "Libera", name: "bob", kind: .directMessage)
		)
		await fixture.coordinator.reconcile()

		#expect(fixture.refreshCount == 1)
	}

	@Test("Turning indexing off removes the entries and refreshes with the conversation names withdrawn")
	func turningOffWithdrawsNames() async {
		let fixture = Fixture()
		await fixture.coordinator.reconcile()
		#expect(await fixture.writer.contents == ["s1", "c1"])

		fixture.options = ConversationIndexOptions(indexesConversations: false, indexesDirectMessages: false)
		await fixture.coordinator.reconcile()

		#expect(await fixture.writer.contents.isEmpty)
		#expect(fixture.refreshCount == 2)

		await fixture.coordinator.reconcile()
		#expect(fixture.refreshCount == 2)
	}

	@Test("Turning direct conversations on adds their names to the refresh")
	func optingInAddsDirectConversations() async {
		let fixture = Fixture()
		await fixture.coordinator.reconcile()

		fixture.options = ConversationIndexOptions(indexesConversations: true, indexesDirectMessages: true)
		await fixture.coordinator.reconcile()

		#expect(fixture.refreshCount == 2)
		#expect(await fixture.writer.contents == ["s1", "c1", "c2"])
	}
}
