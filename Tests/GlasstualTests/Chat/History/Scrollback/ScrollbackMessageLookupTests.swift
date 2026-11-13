// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Scrollback lookup by message identifier")
struct ScrollbackMessageLookupTests {
	private func openStore() async throws -> (ScrollbackStore, URL) {
		let directory = try ScrollbackFixture.makeDirectory()
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture.unique().store)
		#expect(await store.openDatabase(inDirectory: directory.path).isOpen)
		return (store, directory)
	}

	private func line(_ body: String, identifier: String?, at seconds: TimeInterval) -> ChatLine {
		var line = ChatLine()
		line.messageBody = body
		line.nickname = "alice"
		line.lineType = .privateMessage
		line.messageIdentifier = identifier
		line.receivedAt = Date(timeIntervalSince1970: seconds)
		return line
	}

	private func window(_ identifier: String, in view: String) -> ScrollbackFetchRequest {
		ScrollbackFetchRequest(viewIdentifier: view, kind: .messageWindow(messageIdentifier: identifier, olderLimit: 1, newerLimit: 1))
	}

	@Test("A stored message is found with its neighbours, and an unknown one finds nothing")
	func storedMessageIsFound() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		for (index, identifier) in ["a", "b", "c", "d"].enumerated() {
			#expect(await store.writeChatLine(line(identifier, identifier: identifier, at: 100 + Double(index))
					.scrollbackEntry(forView: "view")) == .accepted)
		}

		let found = await store.fetchOutcome(window("c", in: "view")).entries
		#expect(found.compactMap { ChatLine(entry: $0)?.messageIdentifier } == ["b", "c", "d"])

		let missing = await store.fetchOutcome(window("zzz", in: "view")).entries
		#expect(missing.isEmpty)
		_ = await store.close()
	}

	@Test("A message stored in another view is not found")
	func otherViewIsNotSearched() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(await store.writeChatLine(line("x", identifier: "x", at: 100).scrollbackEntry(forView: "other")) == .accepted)

		#expect(await store.fetchOutcome(window("x", in: "view")).entries.isEmpty)
		_ = await store.close()
	}
}
