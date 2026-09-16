/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Message rule store")
struct MessageRuleStoreTests {
	@Test("An editor saves its rule after an import reorders the list")
	func savesByIdentityAfterReorder() {
		var first = MessageRule()
		first.title = "First"
		var second = MessageRule()
		second.title = "Second"
		var saved: [MessageRule] = []
		let store = MessageRuleStore { saved = $0 }
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
		let first = MessageRule()
		let second = MessageRule()
		var writes = 0
		let store = MessageRuleStore { _ in writes += 1 }
		store.replaceAll(with: [first, second])
		store.replaceAll(with: [second])
		#expect(store.save(first, replacing: first.id) == false)
		#expect(store.rules.map(\.id) == [second.id])
		#expect(writes == 0)
	}

	@Test("A new rule still appends after an external replacement")
	func newRuleAppends() {
		let existing = MessageRule()
		let draft = MessageRule()
		var writes = 0
		let store = MessageRuleStore { _ in writes += 1 }
		store.replaceAll(with: [existing])
		#expect(store.save(draft, replacing: nil))
		#expect(store.rules.map(\.id) == [existing.id, draft.id])
		#expect(writes == 1)
	}
}
