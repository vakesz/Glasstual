// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Spotlight index actor")
struct ConversationIndexTests {
	private let server = ConversationIndexEntry(id: "s1", kind: .server, title: "Libera", serverID: "s1", serverName: "Libera")
	private let channel = ConversationIndexEntry(id: "c1", kind: .channel, title: "#swift", serverID: "s1", serverName: "Libera")
	private let direct = ConversationIndexEntry(id: "c2", kind: .directMessage, title: "alice", serverID: "s1", serverName: "Libera")

	/// Lets queued work on other tasks run, so a call that is not waiting its
	/// turn has the chance to reach the writer.
	private func letOtherTasksRun() async {
		for _ in 0 ..< 50 {
			await Task.yield()
		}
	}

	@Test("A removal issued while an apply is writing waits for it, so nothing is left indexed")
	func removalWaitsForRunningApply() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)
		await writer.holdNextUpsert()

		let apply = Task { await index.apply([server, channel]) }
		await writer.waitUntilUpsertIsHeld()
		let removal = Task { await index.removeAll() }
		await letOtherTasksRun()

		#expect(await writer.calls == [.deleteAll, .upsert(["s1", "c1"])])

		await writer.releaseHeldUpsert()
		await apply.value
		await removal.value

		#expect(await writer.contents.isEmpty)
		#expect(await writer.calls == [.deleteAll, .upsert(["s1", "c1"]), .deleteAll])

		await index.apply([server, channel])
		#expect(await writer.contents == ["s1", "c1"])
	}

	@Test("An apply that overlaps another diffs against what the first one wrote")
	func overlappingAppliesDiffAfterTheFirst() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)
		await writer.holdNextUpsert()

		let first = Task { await index.apply([server, channel, direct]) }
		await writer.waitUntilUpsertIsHeld()
		let second = Task { await index.apply([server, channel]) }
		await letOtherTasksRun()

		await writer.releaseHeldUpsert()
		await first.value
		await second.value

		#expect(await writer.calls == [.deleteAll, .upsert(["s1", "c1", "c2"]), .delete(["c2"])])
		#expect(await writer.contents == ["s1", "c1"])
	}

	@Test("A failed write leaves the bookkeeping alone, so the next apply retries it")
	func failedUpsertIsRetried() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)
		await writer.failNextUpserts(1)

		await index.apply([server, channel])
		#expect(await writer.contents.isEmpty)

		await index.apply([server, channel])
		#expect(await writer.calls == [.deleteAll, .upsert(["s1", "c1"]), .upsert(["s1", "c1"])])
		#expect(await writer.contents == ["s1", "c1"])
	}

	@Test("An apply with nothing new writes nothing")
	func unchangedApplyWritesNothing() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)

		await index.apply([server, channel])
		await index.apply([server, channel])

		#expect(await writer.calls == [.deleteAll, .upsert(["s1", "c1"])])
	}

	@Test("Removing twice in a row deletes the domain once")
	func repeatedRemovalIsSkipped() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)

		await index.removeAll()
		await index.removeAll()
		await index.removeAll()

		#expect(await writer.deleteAllCount == 1)
	}

	@Test("A removal right after the launch cleanup is skipped when nothing was indexed")
	func removalAfterEmptyApplyIsSkipped() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)

		await index.apply([])
		await index.removeAll()

		#expect(await writer.deleteAllCount == 1)
	}

	@Test("Removing after indexing deletes again")
	func removalAfterIndexingDeletes() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)

		await index.removeAll()
		await index.apply([server])
		await index.removeAll()

		#expect(await writer.calls == [.deleteAll, .upsert(["s1"]), .deleteAll])
		#expect(await writer.contents.isEmpty)
	}

	@Test("A failed removal is retried by the next one")
	func failedRemovalIsRetried() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)
		await writer.failNextDeleteAlls(1)

		await index.removeAll()
		await index.removeAll()
		await index.removeAll()

		#expect(await writer.deleteAllCount == 2)
	}

	@Test("An upsert that failed may have landed in part, so the next removal still deletes")
	func removalAfterFailedUpsertDeletes() async {
		let writer = FakeConversationIndexWriter()
		let index = ConversationIndex(writer: writer)
		await writer.failNextUpserts(1)

		await index.apply([server])
		await index.removeAll()

		#expect(await writer.calls == [.deleteAll, .upsert(["s1"]), .deleteAll])
	}
}
