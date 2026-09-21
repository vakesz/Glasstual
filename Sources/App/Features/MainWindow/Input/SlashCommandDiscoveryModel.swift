// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
import Observation

/// Suggestion selection belongs to the input feature, independently of the
/// native text view's insertion point and undo history.
@MainActor
@Observable
final class SlashCommandDiscoveryModel {
	private(set) var suggestions: [SlashCommandSuggestion] = []
	private(set) var selectedIndex = 0
	private(set) var request: SlashCommandRequest?
	private var dismissedText: String?
	private var currentText = ""

	var isVisible: Bool {
		suggestions.isEmpty == false
	}

	var isEditingCommand: Bool {
		request?.isEditingCommand == true
	}

	var selectedSuggestion: SlashCommandSuggestion? {
		suggestions.indices.contains(selectedIndex) ? suggestions[selectedIndex] : nil
	}

	func update(
		text: String,
		selection: NSRange,
		isActive: Bool,
		includingDeveloperCommands: Bool = false,
		scriptCommands: [String] = []
	) {
		if text != currentText {
			dismissedText = nil
		}
		currentText = text
		guard isActive, dismissedText != text,
		      let nextRequest = SlashCommandRequest(text: text, selection: selection)
		else {
			request = nil
			suggestions = []
			selectedIndex = 0
			return
		}

		let selectedName = selectedSuggestion?.name
		request = nextRequest
		suggestions = SlashCommandCatalog.suggestions(
			for: text,
			selection: selection,
			includingDeveloperCommands: includingDeveloperCommands,
			scriptCommands: scriptCommands
		)
		selectedIndex = suggestions.firstIndex { $0.name == selectedName } ?? 0
	}

	@discardableResult
	func moveSelection(forward: Bool) -> Bool {
		guard isVisible, isEditingCommand else { return false }
		selectedIndex = (selectedIndex + (forward ? 1 : suggestions.count - 1)) % suggestions.count
		return true
	}

	@discardableResult
	func dismiss() -> Bool {
		guard isVisible else { return false }
		dismissedText = currentText
		request = nil
		suggestions = []
		selectedIndex = 0
		return true
	}
}
