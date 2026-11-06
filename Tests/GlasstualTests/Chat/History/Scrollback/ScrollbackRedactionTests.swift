// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Scrollback redaction")
struct ScrollbackRedactionTests {
	private func openStore() async throws -> (ScrollbackStore, URL) {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
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
		line.reactions = ["👍": ["bob"]]
		line.receivedAt = Date(timeIntervalSince1970: seconds)
		return line
	}

	@Test("The stored payload loses its text but keeps its place, sender and identifier")
	func redactionOverwritesTheStoredBody() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(await store.writeChatLine(line("keep", identifier: "other", at: 100).scrollbackEntry(forView: "view")) == .accepted)
		#expect(await store.writeChatLine(line("secret", identifier: "msg-1", at: 101).scrollbackEntry(forView: "view")) == .accepted)
		let before = await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
		let secretCursor = try #require(before.first?.cursor)

		let outcome = await store.redactChatLine(messageIdentifier: "msg-1", inView: "view")

		guard case let .redacted(redacted) = outcome else {
			Issue.record("Expected the line to be redacted, got \(outcome)")
			return
		}
		#expect(redacted.lineType == .redacted)
		#expect(redacted.messageBody.isEmpty)
		let entries = await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries
		#expect(entries.count == 2)
		let stored = try #require(entries.first.flatMap { ChatLine(entry: $0) })
		#expect(entries.first?.cursor == secretCursor)
		#expect(stored.lineType == .redacted)
		#expect(stored.messageBody.isEmpty)
		#expect(stored.reactions == nil)
		#expect(stored.messageIdentifier == "msg-1")
		#expect(stored.nickname == "alice")
		#expect(stored.receivedAt == Date(timeIntervalSince1970: 101))
		#expect(entries.last.flatMap { ChatLine(entry: $0) }?.messageBody == "keep")
		_ = await store.close()
	}

	@Test("A message in another view is never touched")
	func redactionStaysInItsView() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(await store.writeChatLine(line("elsewhere", identifier: "msg-1", at: 100).scrollbackEntry(forView: "other")) == .accepted)

		#expect(await store.redactChatLine(messageIdentifier: "msg-1", inView: "view") == .missing)

		let stored = await store.fetchOutcome(.newestEntries(forView: "other", fetchLimit: 10)).entries.first
		#expect(stored.flatMap { ChatLine(entry: $0) }?.messageBody == "elsewhere")
		_ = await store.close()
	}

	@Test("An identifier that is not stored is reported missing and never creates a row")
	func missingMessageCreatesNothing() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }

		#expect(await store.redactChatLine(messageIdentifier: "nope", inView: "view") == .missing)
		#expect(await store.redactChatLine(messageIdentifier: "", inView: "view") == .missing)
		#expect(await store.fetchOutcome(.newestEntries(forView: "view", fetchLimit: 10)).entries.isEmpty)
		_ = await store.close()
	}

	@Test("A non-ASCII identifier is found without the byte pre-filter")
	func nonASCIIIdentifierIsFound() async throws {
		let (store, directory) = try await openStore()
		defer { try? FileManager.default.removeItem(at: directory) }
		#expect(await store.writeChatLine(line("secret", identifier: "ü-1", at: 100).scrollbackEntry(forView: "view")) == .accepted)

		let outcome = await store.redactChatLine(messageIdentifier: "ü-1", inView: "view")

		guard case .redacted = outcome else {
			Issue.record("Expected the line to be redacted, got \(outcome)")
			return
		}
		_ = await store.close()
	}
}
