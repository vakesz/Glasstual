// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Message rule editing")
struct MessageRulesTests {
	/// A controller that reads and writes nothing but what the test hands it,
	/// reporting every write through `written`.
	private static func controller(
		written: @escaping @MainActor ([PropertyListValue]) -> Void
	) -> MessageRules {
		MessageRules(storedRules: { [] }, storeRules: written)
	}

	@Test("An editor saves its rule after an import reorders the list")
	func savesByIdentityAfterReorder() {
		var first = MessageRule()
		first.title = "First"
		var second = MessageRule()
		second.title = "Second"
		var saved: [MessageRule] = []
		let rules = Self.controller { configurations in
			saved = configurations.compactMap(\.dictionary).map(MessageRule.init(dictionary:))
		}
		rules.replaceAll(with: [first, second])
		var draft = first
		draft.title = "Edited"
		rules.replaceAll(with: [second, first])
		#expect(rules.save(draft, replacing: first.id))
		#expect(saved.map(\.id) == [second.id, first.id])
		#expect(saved.map(\.title) == ["Second", "Edited"])
		#expect(rules.selection == first.id)
	}

	@Test("Saving an editor whose rule was removed does not replace another rule or resurrect it")
	func removedRuleRejectsSave() {
		let first = MessageRule()
		let second = MessageRule()
		var writes = 0
		let rules = Self.controller { _ in writes += 1 }
		rules.replaceAll(with: [first, second])
		rules.replaceAll(with: [second])
		#expect(rules.save(first, replacing: first.id) == false)
		#expect(rules.rules.map(\.id) == [second.id])
		#expect(writes == 0)
	}

	@Test("A new rule still appends after an external replacement")
	func newRuleAppends() {
		let existing = MessageRule()
		let draft = MessageRule()
		var writes = 0
		let rules = Self.controller { _ in writes += 1 }
		rules.replaceAll(with: [existing])
		#expect(rules.save(draft, replacing: nil))
		#expect(rules.rules.map(\.id) == [existing.id, draft.id])
		#expect(writes == 1)
	}
}
