// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import CocoaExtensions

extension InputField {
	/// The native editor owns the caret and composition. The discovery model
	/// receives a snapshot so a suggestion never changes an IME's marked text.
	func refreshSlashCommands() {
		let isActive = focusModel.isFocused && hasMarkedText() == false
		commandDiscovery.update(
			text: string,
			selection: selectedRange(),
			isActive: isActive,
			includingDeveloperCommands: SettingsKeys.Commands.developerMode.value,
			scriptCommands: isActive ? AppServices.scripts.commandNames : []
		)
		updateSlashCommandAccessibilityHelp()
	}

	func textViewDidChangeSelection(_: Notification) {
		refreshSlashCommands()
	}

	/// A selected command changes only its token, preserving arguments and the
	/// editor's normal undo behavior. Re-read the request before using its range:
	/// a mouse action may arrive after the draft or insertion point has changed.
	@discardableResult
	func acceptSlashCommand(_ suggestion: SlashCommandSuggestion? = nil) -> Bool {
		let selectedName = (suggestion ?? commandDiscovery.selectedSuggestion)?.name
		refreshSlashCommands()
		guard let request = commandDiscovery.request,
		      let currentSuggestion = commandDiscovery.suggestions.first(where: { $0.name == selectedName })
		else { return false }

		let replacement = request.replacement(for: currentSuggestion)
		breakUndoCoalescing()
		insertText(replacement.text, replacementRange: replacement.range)
		setSelectedRange(replacement.selection)
		breakUndoCoalescing()
		focus()
		refreshSlashCommands()
		return true
	}

	/// Return completes an unfinished name, while an exact command or a command
	/// with arguments keeps the existing send behavior.
	func acceptIncompleteSlashCommand() -> Bool {
		refreshSlashCommands()
		guard commandDiscovery.isEditingCommand,
		      let request = commandDiscovery.request,
		      let suggestion = commandDiscovery.selectedSuggestion,
		      request.commandName != suggestion.name
		else { return false }
		return acceptSlashCommand(suggestion)
	}

	@discardableResult
	func moveSlashCommandSelection(forward: Bool) -> Bool {
		refreshSlashCommands()
		let moved = commandDiscovery.moveSelection(forward: forward)
		updateSlashCommandAccessibilityHelp()
		if moved, NSWorkspace.shared.isVoiceOverEnabled, let suggestion = commandDiscovery.selectedSuggestion {
			NSAccessibility.post(element: NSApplication.shared, notification: .announcementRequested, userInfo: [
				.announcement: suggestion.syntax + ". " + suggestion.description,
				.priority: NSAccessibilityPriorityLevel.low.rawValue,
			])
		}
		return moved
	}

	@discardableResult
	func dismissSlashCommands() -> Bool {
		let dismissed = commandDiscovery.dismiss()
		updateSlashCommandAccessibilityHelp()
		return dismissed
	}

	private func updateSlashCommandAccessibilityHelp() {
		let help = commandDiscovery.selectedSuggestion.map { $0.syntax + ". " + $0.argumentHint }
		setAccessibilityHelp(help)
	}
}
