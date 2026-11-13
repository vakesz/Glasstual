// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import Observation
import SwiftUI // for `Array.move(fromOffsets:toOffset:)`, which the pane's `.onMove` hands its offsets to

/** Owns the user's message rules: the stored list, the editing the Rules pane
 does, and the engine the inbound path asks.

 The rules live in one setting, so a configuration import is a write to it
 like any other. The change notification is what brings an import back in,
 which is why the list is re-read rather than kept only in memory. */
@MainActor
@Observable
final class MessageRules {
	/// The rule list the Rules pane edits. Every edit is written straight back
	/// to where the rules are stored.
	private(set) var rules: [MessageRule] = []

	/// The rule the Rules pane has selected, kept pointing at something the list
	/// still holds.
	var selection: MessageRule.ID?

	/// The engine the inbound path asks whether a line may be printed.
	@ObservationIgnored private(set) lazy var engine = MessageRuleMatcher { [weak self] in
		self?.rules ?? []
	}

	@ObservationIgnored private var savedConfigurations: [PropertyListValue]?
	@ObservationIgnored private let storedRules: @MainActor () -> [PropertyListValue]
	@ObservationIgnored private let storeRules: @MainActor ([PropertyListValue]) -> Void
	@ObservationIgnored private let notifications = NotificationSubscriptions()

	/// The app reads and writes the rules setting; a test hands in its own
	/// storage so editing can be exercised without touching what is stored.
	init(
		storedRules: @escaping @MainActor () -> [PropertyListValue] = {
			SettingsKeys.Rules.messageRules.propertyListValue?.array ?? []
		},
		storeRules: @escaping @MainActor ([PropertyListValue]) -> Void = {
			SettingsKeys.Rules.messageRules.propertyListValue = .array($0)
		}
	) {
		self.storedRules = storedRules
		self.storeRules = storeRules
		notifications.observe(.userDefaultsDidChange) { [weak self] notification in
			let changedKey = notification.userInfo?[
				SettingsChangeNotification.changedKeyUserInfoKey
			] as? String
			guard changedKey == nil || changedKey == SettingsKeys.Rules.messageRules.name else { return }
			self?.load()
		}
		load()
	}

	// MARK: - Editing

	@discardableResult
	func save(_ rule: MessageRule, replacing identifier: MessageRule.ID?) -> Bool {
		if let identifier {
			guard let index = rules.firstIndex(where: { $0.id == identifier }) else { return false }
			rules[index] = rule
		} else {
			rules.append(rule)
		}
		selection = rule.id
		save(rules)
		return true
	}

	func removeSelection() {
		guard let selectedIndex else { return }
		rules.remove(at: selectedIndex)
		selection = rules.indices.contains(selectedIndex)
			? rules[selectedIndex].id
			: rules.last?.id
		save(rules)
	}

	func move(from offsets: IndexSet, to destination: Int) {
		rules.move(fromOffsets: offsets, toOffset: destination)
		save(rules)
	}

	var selectedIndex: Int? {
		guard let selection else { return nil }
		return rules.firstIndex { $0.id == selection }
	}

	var selectedRule: MessageRule? {
		selectedIndex.map { rules[$0] }
	}

	// MARK: - Storage

	func replaceAll(with rules: [MessageRule]) {
		self.rules = rules
		if selection.map({ selectedID in rules.contains { $0.id == selectedID } }) != true {
			selection = rules.first?.id
		}
	}

	private func load() {
		let configurations = storedRules()
		guard configurations != savedConfigurations else { return }
		savedConfigurations = configurations
		replaceAll(with: configurations.compactMap(\.dictionary).map(MessageRule.init(dictionary:)))
		engine.rulesDidChange()
	}

	private func save(_ rules: [MessageRule]) {
		let configurations = rules.map { PropertyListValue.dictionary($0.dictionaryValue) }
		savedConfigurations = configurations
		storeRules(configurations)
		engine.rulesDidChange()
	}
}
