// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

struct SlashCommandSuggestion: Identifiable, Equatable {
	let name: String
	let description: String
	let syntax: String
	let argumentHint: String
	let isScript: Bool

	var id: String {
		name
	}
}

/// Describes the same commands accepted by the dispatcher without running them.
enum SlashCommandCatalog {
	static func suggestions(
		for text: String,
		selection: NSRange,
		includingDeveloperCommands: Bool = false,
		scriptCommands: [String] = []
	) -> [SlashCommandSuggestion] {
		guard let request = SlashCommandRequest(text: text, selection: selection) else { return [] }
		let results = CommandIndex.candidates(
			includingDeveloperCommands: includingDeveloperCommands,
			scriptCommands: scriptCommands
		).compactMap { candidate -> SlashCommandSuggestion? in
			guard matches(candidate.name, request: request) else { return nil }
			if candidate.isScript {
				return scriptSuggestion(name: candidate.name)
			}
			guard let command = LocalCommand(typedName: candidate.name),
			      let help = SlashCommandHelp.byCommand[command]
			else { return nil }
			return help.suggestion(for: command)
		}
		return results.sorted { left, right in
			if (left.name == request.commandName) != (right.name == request.commandName) {
				return left.name == request.commandName
			}
			return left.name.localizedStandardCompare(right.name) == .orderedAscending
		}
	}

	private static func matches(_ name: String, request: SlashCommandRequest) -> Bool {
		request.isEditingCommand ? name.hasPrefix(request.commandPrefix) : name == request.commandName
	}

	private static func scriptSuggestion(name: String) -> SlashCommandSuggestion {
		SlashCommandSuggestion(
			name: name,
			description: String(localized: .SlashCommands.descriptionScript),
			syntax: "/" + name + " " + String(localized: .SlashCommands.syntaxArguments),
			argumentHint: String(localized: .SlashCommands.hintScript),
			isScript: true
		)
	}
}
