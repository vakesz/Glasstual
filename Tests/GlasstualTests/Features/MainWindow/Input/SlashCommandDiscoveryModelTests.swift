// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SlashCommandDiscoveryModelTests {
	private func update(_ model: SlashCommandDiscoveryModel, text: String, active: Bool = true) {
		model.update(text: text, selection: NSRange(location: text.utf16.count, length: 0), isActive: active)
	}

	@Test("Native selection updates preserve the chosen suggestion while it still matches")
	func selectionSurvivesRepeatedUpdates() {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/j")
		#expect(model.selectedSuggestion?.name == "j")
		#expect(model.moveSelection(forward: true))
		#expect(model.selectedSuggestion?.name == "join")

		update(model, text: "/j")
		#expect(model.selectedSuggestion?.name == "join")
		update(model, text: "/jo")
		#expect(model.selectedSuggestion?.name == "join")
		update(model, text: "/topic")
		#expect(model.selectedSuggestion?.name == "topic")
	}

	@Test("Selection wraps in both directions and argument hints leave arrows to the editor")
	func navigationWrapsOnlyWhileChoosingCommand() {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/j")
		let firstName = model.selectedSuggestion?.name
		let lastName = model.suggestions.last?.name

		#expect(model.moveSelection(forward: false))
		#expect(model.selectedSuggestion?.name == lastName)
		#expect(model.moveSelection(forward: true))
		#expect(model.selectedSuggestion?.name == firstName)

		update(model, text: "/join #swift")
		#expect(model.isVisible)
		#expect(model.isEditingCommand == false)
		#expect(model.moveSelection(forward: true) == false)
		#expect(model.selectedSuggestion?.name == "join")
	}

	@Test("Dismissal survives caret and focus changes until the text changes")
	func dismissalSurvivesFocusAndCaretChanges() {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/jo")
		#expect(model.dismiss())
		#expect(model.isVisible == false)
		#expect(model.dismiss() == false)

		model.update(text: "/jo", selection: NSRange(location: 2, length: 0), isActive: true)
		#expect(model.isVisible == false)
		update(model, text: "/jo", active: false)
		update(model, text: "/jo")
		#expect(model.isVisible == false)

		update(model, text: "/joi")
		#expect(model.isVisible)
		#expect(model.selectedSuggestion?.name == "join")
	}

	@Test("Losing focus hides suggestions without dismissing the unchanged command")
	func focusLossDoesNotDismiss() {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/join")
		update(model, text: "/join", active: false)
		#expect(model.isVisible == false)
		#expect(model.request == nil)
		#expect(model.moveSelection(forward: true) == false)

		update(model, text: "/join")
		#expect(model.isVisible)
		#expect(model.selectedSuggestion?.name == "join")
	}

	@Test("Non-command drafts clear an existing suggestion", arguments: [
		"//join", "/join\n#swift", "hello /join", "", "/zzunrecognizedcommand",
	])
	func nonCommandDraftsHideSuggestions(_ text: String) {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/join")
		update(model, text: text)
		#expect(model.isVisible == false)
		#expect(model.selectedSuggestion == nil)
	}

	@Test("A text selection hides suggestions and restoring the insertion point opens them")
	func selectedTextHidesSuggestions() {
		let model = SlashCommandDiscoveryModel()
		update(model, text: "/join")
		model.update(text: "/join", selection: NSRange(location: 1, length: 4), isActive: true)
		#expect(model.isVisible == false)

		update(model, text: "/join")
		#expect(model.isVisible)
	}

	@Test("Command panel height is bounded even when scripts add hundreds of commands")
	func panelHeightIsBounded() {
		let model = SlashCommandDiscoveryModel()
		#expect(SlashCommandDiscoveryView.height(for: model) == 0)
		let scripts = (0 ..< 100).map { "zzscript\($0)" }
		let command = "/zz"
		let caret = NSRange(location: command.utf16.count, length: 0)
		model.update(text: command, selection: caret, isActive: true, scriptCommands: Array(scripts.prefix(3)))
		let shortHeight = SlashCommandDiscoveryView.height(for: model)
		model.update(text: command, selection: caret, isActive: true, scriptCommands: Array(scripts.prefix(5)))
		let fullHeight = SlashCommandDiscoveryView.height(for: model)
		model.update(text: command, selection: caret, isActive: true, scriptCommands: scripts)

		#expect(model.suggestions.count == scripts.count)
		#expect(shortHeight > 0)
		#expect(fullHeight > shortHeight)
		#expect(SlashCommandDiscoveryView.height(for: model) == fullHeight)

		update(model, text: "/join #swift")
		#expect(SlashCommandDiscoveryView.height(for: model) > 0)
		#expect(SlashCommandDiscoveryView.height(for: model) < shortHeight)
		model.dismiss()
		#expect(SlashCommandDiscoveryView.height(for: model) == 0)
	}
}
