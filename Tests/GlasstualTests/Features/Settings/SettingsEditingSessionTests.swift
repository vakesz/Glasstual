// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Settings editing completion")
struct SettingsEditingSessionTests {
	@Test("Quit completes a focused draft without waiting for focus loss", arguments: ["3200", "invalid"])
	func completionPersistsOrRejectsPendingDraft(_ text: String) throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let editing = SettingsEditingSession()
		var draft = SettingsFieldDraft()
		var attempts = 0
		let value = SettingsFieldValue(text: { String(fixture.stores[key]) }, write: { text in
			attempts += 1
			guard let count = UInt(text), key.accepts(count) else { return false }
			fixture.stores.set(.integer(Int(count)), for: key)
			return true
		})
		editing.track(draft.identifier) { draft.commit(to: value) }
		draft.edit(text)
		#expect(fixture.stores[key] == key.defaultValue)

		editing.finishEditing()
		editing.finishEditing(for: draft.identifier)

		#expect(attempts == 1)
		#expect(fixture.stores[key] == (text == "3200" ? 3200 : key.defaultValue))
		#expect(draft.wasRejected == (text == "invalid"))
		#expect(draft.displayed(value.text()) == value.text())
	}

	@Test("Export includes a pending Settings edit before encoding the snapshot")
	func exportFinishesPendingEdit() async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let editing = SettingsEditingSession()
		let session = SettingsTransferSession(stores: fixture.stores, recoveryDirectory: fixture.directory,
		                                      sessionSource: .stored, editing: editing)
		editing.track(UUID()) { fixture.stores.set(3200, for: key) }
		#expect(fixture.stores[key] == key.defaultValue)

		let data = try await session.exportData()
		let archive = try SettingsArchive.decode(data)

		#expect(archive.values[key.name] == .integer(3200))
		#expect(fixture.stores[key] == 3200)
	}

	@Test("An edit still focused after preview invalidates the import instead of being overwritten")
	func commitChecksPendingEditForStaleness() async throws {
		let fixture = try SettingsTransferFixture()
		defer { fixture.cleanUp() }
		let key = SettingsKeys.Logging.scrollbackSaveLimit
		let editing = SettingsEditingSession()
		let session = SettingsTransferSession(stores: fixture.stores, recoveryDirectory: fixture.directory,
		                                      sessionSource: .stored, editing: editing)
		var imported = try session.liveSnapshot()
		imported.values[key.name] = 2000
		try await session.prepareImport(from: fixture.write(imported.encoded()))
		#expect(session.preview != nil)
		editing.track(UUID()) { fixture.stores.set(3200, for: key) }

		await session.commitPreview()

		#expect(session.result == nil)
		#expect(session.errorMessage == SettingsTransferError.stalePreview.localizedDescription)
		#expect(fixture.stores[key] == 3200)
		#expect(try await session.recoveryStore.backups().isEmpty)
	}

	@Test("Changing fields finishes the previous edit and a delayed blur leaves the new edit pending")
	func switchingFieldsPreservesNewestEdit() {
		let editing = SettingsEditingSession()
		let first = UUID()
		let second = UUID()
		var finished: [Int] = []
		editing.track(first) { finished.append(1) }
		editing.track(first) { finished.append(2) }
		#expect(finished.isEmpty)
		editing.track(second) { finished.append(3) }
		#expect(finished == [2])
		editing.finishEditing(for: first)
		#expect(finished == [2])
		editing.finishEditing()
		#expect(finished == [2, 3])
	}

	@Test("Completion consumes its pending edit before a callback starts another")
	func reentrantCompletionRetainsNewEdit() {
		let editing = SettingsEditingSession()
		var finished: [Int] = []
		editing.track(UUID()) {
			finished.append(1)
			editing.track(UUID()) { finished.append(2) }
		}
		editing.finishEditing()
		#expect(finished == [1])
		editing.finishEditing()
		#expect(finished == [1, 2])
	}
}
