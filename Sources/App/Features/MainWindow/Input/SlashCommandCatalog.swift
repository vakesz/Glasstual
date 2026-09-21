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
		let scripts = Set(scriptCommands.map { $0.lowercased() }.filter(isValidScriptName))
		var results: [SlashCommandSuggestion] = []
		var includedNames: Set<String> = []

		for command in LocalCommand.allCases {
			guard includingDeveloperCommands || command.isDeveloperModeOnly == false,
			      matches(command.rawValue, request: request)
			else { continue }
			includedNames.insert(command.rawValue)
			// A script can override commands forwarded to the server, but cannot
			// override a local handler or bypass the developer-mode gate.
			if command.group == nil, scripts.contains(command.rawValue) {
				results.append(scriptSuggestion(name: command.rawValue))
			} else if let help = SlashCommandHelp.byCommand[command] {
				results.append(help.suggestion(for: command))
			}
		}
		for name in scripts where includedNames.contains(name) == false && matches(name, request: request) {
			guard LocalCommand(typedName: name) == nil else { continue }
			results.append(scriptSuggestion(name: name))
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

	private static func isValidScriptName(_ name: String) -> Bool {
		name.isEmpty == false && name.contains("/") == false && name.contains(where: \.isWhitespace) == false
	}
}
