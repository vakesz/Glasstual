// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** The Help Book's slash command reference against the in-app command help.

 Each row of the reference is the English text of one ``SlashCommandHelp``
 entry: the syntax, the description and the hint the suggestions show. The
 page groups the rows by purpose, which is the page's own choice; the rows
 themselves come from the help, so a command added, renamed or reworded there
 fails this test until the page says the same. On failure the expected rows
 are written to `HelpBookCommandRows.html` in the test host's temporary
 folder, ready to paste into the page. */
@MainActor
@Suite("Help Book command reference")
struct HelpBookCommandReferenceTests {
	private static let english = Locale(identifier: "en")

	private static func english(_ resource: LocalizedStringResource) -> String {
		var resource = resource
		resource.locale = english
		return String(localized: resource)
	}

	private static func escaped(_ text: String) -> String {
		text.replacingOccurrences(of: "&", with: "&amp;")
			.replacingOccurrences(of: "<", with: "&lt;")
			.replacingOccurrences(of: ">", with: "&gt;")
			.replacingOccurrences(of: "\"", with: "&quot;")
	}

	/// One documented command: the name a row is listed under, the other
	/// names that run it, and its help.
	private struct Entry {
		let primary: LocalCommand
		let aliases: [LocalCommand]
		let help: SlashCommandHelp
	}

	/// One help entry per group of aliases, without developer-mode commands,
	/// which the suggestions hide too.
	private static var entries: [Entry] {
		var seen: Set<LocalCommand> = []
		var result: [Entry] = []
		for command in LocalCommand.allCases {
			guard let help = SlashCommandHelp.byCommand[command], seen.contains(command) == false else { continue }
			seen.formUnion(help.commands)
			let commands = help.commands.filter { $0.isDeveloperModeOnly == false }
			/* The help lists the main name first, except where it leads with a
			 shorthand of one or two letters: then the reader looks for the full
			 name it stands for, /join rather than /j and /kickban rather than
			 /kb, which shares its initial. */
			guard let first = commands.first else { continue }
			let primary = first.rawValue.count > 2 ? first : commands
				.filter { $0.rawValue.first == first.rawValue.first }
				.reduce(first) { $1.rawValue.count > $0.rawValue.count ? $1 : $0 }
			result.append(Entry(primary: primary, aliases: commands.filter { $0 != primary }, help: help))
		}
		return result
	}

	private static func row(for entry: Entry) -> String {
		let (primary, aliases, help) = (entry.primary, entry.aliases, entry.help)
		let syntax = help.arguments.map {
			english(.SlashCommands.syntaxWithArguments(primary.rawValue, english($0)))
		} ?? "/" + primary.rawValue
		let aliasList = aliases.isEmpty ? "" :
			#"<span class="aliases">Also: \#(aliases.map { "/" + $0.rawValue }.joined(separator: ", "))</span>"#
		let hint = english(help.hint)
		let hintSpan = hint == english(.SlashCommands.hintNoArguments) ? "" :
			#"<span class="hint">\#(escaped(hint))</span>"#
		return #"<tr id="command-\#(primary.rawValue)"><th scope="row"><code>\#(escaped(syntax))</code>\#(aliasList)</th>"#
			+ #"<td>\#(escaped(english(help.description)))\#(hintSpan)</td></tr>"#
	}

	private static func page() throws -> String {
		let book = try #require(HelpBook.url())
		return try String(
			contentsOf: book.appending(path: "Contents/Resources/en.lproj/pages/commands.html"),
			encoding: .utf8
		)
	}

	@Test("The reference lists every command exactly as the in-app help describes it")
	func referenceMatchesCommandHelp() throws {
		let page = try Self.page()
		let rows = Self.entries.map(Self.row(for:))
		let missing = rows.filter { page.contains($0) == false }

		let documented = Set(Self.entries.map { "command-" + $0.primary.rawValue })
		let listed = Set(page.matches(of: #/<tr id="(command-[^"]+)"/#).map { String($0.output.1) })

		if missing.isEmpty == false || listed != documented {
			let expected = FileManager.default.temporaryDirectory.appending(path: "HelpBookCommandRows.html")
			try rows.joined(separator: "\n").write(to: expected, atomically: true, encoding: .utf8)
			Issue.record("The command reference differs from the in-app help. Expected rows: \(expected.path(percentEncoded: false))")
		}
		#expect(missing.isEmpty, "Rows missing or out of date: \(missing.count)")
		#expect(listed.subtracting(documented).isEmpty, "Rows for commands without help: \(listed.subtracting(documented))")
		#expect(documented.subtracting(listed).isEmpty, "Commands missing from the page: \(documented.subtracting(listed))")
	}

	@Test("Developer-mode commands stay out of the reference")
	func developerCommandsAreHidden() throws {
		let page = try Self.page()

		for command in LocalCommand.allCases where command.isDeveloperModeOnly {
			#expect(page.contains(#"id="command-\#(command.rawValue)""#) == false)
			#expect(page.contains("/\(command.rawValue)<") == false && page.contains("/\(command.rawValue),") == false)
		}
	}
}
