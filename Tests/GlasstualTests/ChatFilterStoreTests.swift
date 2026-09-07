/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
import Testing

@MainActor
@Suite("Chat Filter editor identity")
struct ChatFilterStoreTests {
	@Test("An editor saves its rule after an import reorders the list")
	func savesByIdentityAfterReorder() {
		var first = ChatFilter()
		first.title = "First"
		var second = ChatFilter()
		second.title = "Second"
		var saved: [ChatFilter] = []
		let store = ChatFilterStore { saved = $0 }
		store.replaceAll(with: [first, second])
		var draft = first
		draft.title = "Edited"
		store.replaceAll(with: [second, first])
		#expect(store.save(draft, replacing: first.id))
		#expect(saved.map(\.id) == [second.id, first.id])
		#expect(saved.map(\.title) == ["Second", "Edited"])
		#expect(store.selection == first.id)
	}

	@Test("Saving an editor whose rule was removed does not replace another rule or resurrect it")
	func removedRuleRejectsSave() {
		let first = ChatFilter()
		let second = ChatFilter()
		var writes = 0
		let store = ChatFilterStore { _ in writes += 1 }
		store.replaceAll(with: [first, second])
		store.replaceAll(with: [second])
		#expect(store.save(first, replacing: first.id) == false)
		#expect(store.filters.map(\.id) == [second.id])
		#expect(writes == 0)
	}

	@Test("A new rule still appends after an external replacement")
	func newRuleAppends() {
		let existing = ChatFilter()
		let draft = ChatFilter()
		var writes = 0
		let store = ChatFilterStore { _ in writes += 1 }
		store.replaceAll(with: [existing])
		#expect(store.save(draft, replacing: nil))
		#expect(store.filters.map(\.id) == [existing.id, draft.id])
		#expect(writes == 1)
	}
}
