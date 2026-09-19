// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

@testable import Glasstual
import Testing

@MainActor
@Suite("Settings field draft")
struct SettingsFieldDraftTests {
	@Test("Selecting a preset replaces an unfinished draft and later completion writes nothing")
	func presetDiscardsPendingDraft() {
		let store = Store()
		var draft = SettingsFieldDraft()
		draft.edit("3000")
		#expect(draft.displayed(store.text) == "3000")
		#expect(store.writes.isEmpty)
		draft.choose("2000", for: store.value)
		#expect(draft.displayed(store.text) == "2000")
		#expect(store.text == "2000")
		#expect(draft.wasRejected == false)
		draft.commit(to: store.value)
		draft.commit(to: store.value)
		#expect(store.writes == ["2000"])
		#expect(store.text == "2000")
	}

	@Test("An accepted preset clears an earlier rejection and any replacement draft")
	func presetClearsRejection() {
		let store = Store()
		var draft = SettingsFieldDraft()
		draft.edit("invalid")
		draft.commit(to: store.value)
		#expect(draft.wasRejected)
		draft.edit("3000")
		draft.choose("2000", for: store.value)
		#expect(draft.wasRejected == false)
		#expect(draft.displayed(store.text) == "2000")
		draft.commit(to: store.value)
		#expect(store.writes == ["invalid", "2000"])
	}

	@Test("A refused preset reports rejection and cannot revive the discarded draft")
	func rejectedPresetDiscardsDraft() {
		let store = Store()
		var draft = SettingsFieldDraft()
		draft.edit("3000")
		draft.choose("invalid", for: store.value)
		#expect(draft.wasRejected)
		#expect(draft.displayed(store.text) == "1000")
		draft.commit(to: store.value)
		#expect(store.writes == ["invalid"])
		#expect(store.text == "1000")
		draft.choose("2000", for: store.value)
		#expect(draft.wasRejected == false)
		#expect(draft.displayed(store.text) == "2000")
	}

	@Test("A normalized preset displays the stored spelling without an extra write")
	func normalizedPresetUsesStoredText() {
		let store = Store()
		var draft = SettingsFieldDraft()
		draft.edit("3000")
		draft.choose("02000", for: store.value)
		#expect(draft.wasRejected == false)
		#expect(draft.displayed(store.text) == "2000")
		draft.commit(to: store.value)
		#expect(store.writes == ["02000"])
	}

	private final class Store {
		var text = "1000"
		var writes: [String] = []

		var value: SettingsFieldValue {
			SettingsFieldValue(text: { self.text }, write: { submitted in
				self.writes.append(submitted)
				guard let number = Int(submitted), number >= 100 else { return false }
				self.text = String(number)
				return true
			})
		}
	}
}
