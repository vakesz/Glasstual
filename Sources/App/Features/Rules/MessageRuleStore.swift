/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Observation
import SwiftUI

/// The rule list the Rules pane edits, and the selection inside it. Every edit
/// is handed straight back to the controller, which writes it.
@Observable
final class MessageRuleStore {
	private(set) var rules: [MessageRule] = []
	var selection: MessageRule.ID?

	private let didChange: ([MessageRule]) -> Void

	init(didChange: @escaping ([MessageRule]) -> Void) {
		self.didChange = didChange
	}

	func replaceAll(with rules: [MessageRule]) {
		self.rules = rules
		if selection.map({ selectedID in rules.contains { $0.id == selectedID } }) != true {
			selection = rules.first?.id
		}
	}

	@discardableResult
	func save(_ rule: MessageRule, replacing identifier: MessageRule.ID?) -> Bool {
		if let identifier {
			guard let index = rules.firstIndex(where: { $0.id == identifier }) else { return false }
			rules[index] = rule
		} else {
			rules.append(rule)
		}
		selection = rule.id
		didChange(rules)
		return true
	}

	func removeSelection() {
		guard let selectedIndex else { return }
		rules.remove(at: selectedIndex)
		selection = rules.indices.contains(selectedIndex)
			? rules[selectedIndex].id
			: rules.last?.id
		didChange(rules)
	}

	func move(from offsets: IndexSet, to destination: Int) {
		rules.move(fromOffsets: offsets, toOffset: destination)
		didChange(rules)
	}

	var selectedIndex: Int? {
		guard let selection else { return nil }
		return rules.firstIndex { $0.id == selection }
	}

	var selectedRule: MessageRule? {
		selectedIndex.map { rules[$0] }
	}
}
