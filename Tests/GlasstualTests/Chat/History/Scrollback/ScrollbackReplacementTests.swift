// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Scrollback delivery replacement")
struct ScrollbackReplacementTests {
	@Test("A receipt changes the stored payload but preserves its cursor and never revives cleared history")
	func replacementPreservesCursor() async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture.unique().store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		var line = ChatLine()
		line.messageBody = "pending"
		line.receivedAt = Date(timeIntervalSince1970: 100)
		#expect(await store.writeChatLine(line.scrollbackEntry(forView: "view")) == .accepted)
		let first = try #require(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries.first)
		line.messageBody = "confirmed"
		line.messageIdentifier = "server-id"
		line.deliveryState = .delivered
		line.receivedAt = Date(timeIntervalSince1970: 105)
		#expect(await store.replaceChatLine(line.scrollbackEntry(forView: "view")) == .replaced)
		let entries = await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
		#expect(entries.count == 1)
		let updated = try #require(entries.first)
		#expect(updated.cursor == first.cursor)
		#expect(updated.creationDate == first.creationDate)
		#expect(ChatLine(entry: updated)?.messageBody == "confirmed")
		_ = await store.resetData(forView: "view")
		#expect(await store.replaceChatLine(line.scrollbackEntry(forView: "view")) == .missing)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries.isEmpty)
		_ = await store.close()
	}
}
