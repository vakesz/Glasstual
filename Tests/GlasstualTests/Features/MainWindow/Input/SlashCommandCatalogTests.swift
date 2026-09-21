// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
struct SlashCommandCatalogTests {
	@Test
	func everyOfferedCommandHasHelp() {
		let suggestions = suggestions("/", includingDeveloperCommands: true)
		#expect(Set(suggestions.map(\.name)) == Set(LocalCommand.allCases.map(\.rawValue)))
		#expect(suggestions.count == LocalCommand.allCases.count)
		for suggestion in suggestions {
			#expect(suggestion.description.isEmpty == false, "\(suggestion.name)")
			#expect(suggestion.syntax.hasPrefix("/" + suggestion.name), "\(suggestion.name)")
			#expect(suggestion.argumentHint.isEmpty == false, "\(suggestion.name)")
		}
	}

	@Test
	func caseInsensitivePrefixMatchingPrefersTheExactCommand() {
		#expect(suggestions("/Jo").map(\.name) == ["join"])
		#expect(suggestions("/m").first?.name == "m")
		#expect(suggestions("/Ctcp").map(\.name) == ["ctcp", "ctcpreply"])
	}

	@Test
	func typingArgumentsKeepsOnlyTheExactCommandsHelp() {
		#expect(suggestions("/me waves").map(\.name) == ["me"])
		#expect(suggestions("/Jo #chat").isEmpty)
		#expect(suggestions("/who alice").map(\.name) == ["who"])
		#expect(suggestions("/unknown argument").isEmpty)
	}

	@Test
	func editingInsideTheTokenUsesOnlyThePrefixBeforeTheCaret() {
		let suggestions = SlashCommandCatalog.suggestions(
			for: "/jwrong #chat",
			selection: NSRange(location: 2, length: 0)
		)
		#expect(suggestions.map(\.name) == ["j", "join"])
	}

	@Test(arguments: ["recv", "tage", "join_random"])
	func developerCommandsCannotBeExposedByScriptNames(name: String) {
		#expect(suggestions("/" + name, scripts: [name]).isEmpty)
		let available = suggestions("/" + name, includingDeveloperCommands: true, scripts: [name])
		#expect(available.count == 1)
		#expect(available.first?.isScript == false)
	}

	@Test
	func scriptsAreDeduplicatedAndRespectDispatchPrecedence() throws {
		let names = ["JOIN", "join", "whowas", "Weather", "weather", "", "bad name", "/bad", "line\nbreak"]
		let available = suggestions("/", scripts: names)
		let join = try #require(available.first { $0.name == "join" })
		let whowas = try #require(available.first { $0.name == "whowas" })
		let weather = try #require(available.first { $0.name == "weather" })
		#expect(join.isScript == false)
		#expect(whowas.isScript)
		#expect(weather.isScript)
		#expect(available.filter { $0.name == "weather" }.count == 1)
		#expect(available.filter { $0.name == "join" }.count == 1)
		#expect(Set(available.filter(\.isScript).map(\.name)) == ["whowas", "weather"])
	}

	@Test
	func helpDistinguishesNotificationMuteFromUserMute() throws {
		let mute = try #require(suggestions("/mute").first)
		#expect(mute.description == String(localized: .SlashCommands.descriptionMute))
		#expect(mute.syntax == "/mute")
		#expect(mute.argumentHint == String(localized: .SlashCommands.hintNoArguments))
	}

	@Test
	func syntaxExplainsLocallyHandledSubcommandsAndOptionalArguments() throws {
		let timer = try #require(suggestions("/timer").first)
		let query = try #require(suggestions("/query").first)
		#expect(timer.syntax == "/timer " + String(localized: .SlashCommands.syntaxSecondsRepeatCommand))
		#expect(query.syntax == "/query " + String(localized: .SlashCommands.syntaxNicknameMessage))
		#expect(timer.argumentHint == String(localized: .SlashCommands.hintSecondsRepeatManagement))
	}

	private func suggestions(
		_ text: String,
		includingDeveloperCommands: Bool = false,
		scripts: [String] = []
	) -> [SlashCommandSuggestion] {
		SlashCommandCatalog.suggestions(
			for: text,
			selection: NSRange(location: text.utf16.count, length: 0),
			includingDeveloperCommands: includingDeveloperCommands,
			scriptCommands: scripts
		)
	}
}
