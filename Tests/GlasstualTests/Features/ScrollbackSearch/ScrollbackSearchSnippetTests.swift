// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@Suite("Scrollback search snippet")
struct ScrollbackSearchSnippetTests {
	private func marked(_ snippet: AttributedString) -> [String] {
		snippet.runs.compactMap { run in
			run.inlinePresentationIntent == .stronglyEmphasized ? String(snippet[run.range].characters) : nil
		}
	}

	@Test("Every match is marked, however it is cased or accented")
	func marksEveryMatch() {
		let snippet = ScrollbackSearchSnippet.make(text: "Caf\u{00E9} and CAFE and cafe", query: "cafe")

		#expect(String(snippet.characters) == "Caf\u{00E9} and CAFE and cafe")
		#expect(marked(snippet) == ["Caf\u{00E9}", "CAFE", "cafe"])
	}

	@Test("A query with no text marks nothing")
	func emptyQueryMarksNothing() {
		let snippet = ScrollbackSearchSnippet.make(text: "plain", query: "  ")

		#expect(String(snippet.characters) == "plain")
		#expect(marked(snippet).isEmpty)
	}

	@Test("A long line is cut around its first match, with ellipses where text was left out")
	func longLinesShowTheMatch() {
		let text = String(repeating: "a", count: 300) + " needle " + String(repeating: "b", count: 300)

		let snippet = ScrollbackSearchSnippet.make(text: text, query: "needle")
		let shown = String(snippet.characters)

		#expect(shown.hasPrefix("\u{2026}"))
		#expect(shown.hasSuffix("\u{2026}"))
		#expect(shown.contains("needle"))
		#expect(shown.count <= ScrollbackSearchSnippet.maximumLength + 2)
		#expect(marked(snippet) == ["needle"])
	}

	@Test("A match near the start keeps the start")
	func nearbyMatchKeepsTheStart() {
		let snippet = ScrollbackSearchSnippet.make(text: "say needle now" + String(repeating: "x", count: 400), query: "needle")

		#expect(String(snippet.characters).hasPrefix("say needle"))
	}

	@Test("Line breaks become spaces so a row stays on its lines")
	func lineBreaksFlatten() {
		#expect(String(ScrollbackSearchSnippet.make(text: "one\ntwo", query: "").characters) == "one two")
	}
}

@Suite("Scrollback search scope")
struct ScrollbackSearchScopeTests {
	private let targets = ScrollbackSearchTargets(
		entries: [
			ScrollbackSearchTarget(viewIdentifier: "a", title: "#a", serverIdentifier: "s1", serverName: "One"),
			ScrollbackSearchTarget(viewIdentifier: "b", title: "#b", serverIdentifier: "s2", serverName: "Two"),
		],
		selectedViewIdentifier: "a",
		selectedServerIdentifier: "s2"
	)

	@Test("The server scope follows the selected server, not the selected conversation")
	func serverScope() {
		#expect(targets.viewIdentifiers(for: .server) == ["b"])
		#expect(targets.viewIdentifiers(for: .conversation) == ["a"])
		#expect(targets.viewIdentifiers(for: .all) == ["a", "b"])
	}

	@Test("A selection that has no history is not a scope")
	func selectionWithoutHistory() {
		var targets = targets
		targets.selectedViewIdentifier = "console"

		#expect(targets.isAvailable(.conversation) == false)
		#expect(targets.viewIdentifiers(for: .conversation).isEmpty)
	}

	@Test("There is nothing to search without conversations")
	func emptyTargets() {
		#expect(ScrollbackSearchTargets.empty.isAvailable(.all) == false)
	}

	@Test("Rows group by conversation in the order the conversations first appear")
	func grouping() {
		func row(_ view: String, _ id: Int) -> ScrollbackSearchRow {
			ScrollbackSearchRow(
				hit: ScrollbackSearchHit(
					viewIdentifier: view, lineIdentifier: "l\(id)", sender: "x", text: "t", timestamp: Double(id),
					cursor: ScrollbackRowCursor(timestamp: Double(id), insertionIdentifier: 1, lineIdentifier: "l\(id)", rowURI: "r\(id)")
				),
				conversationName: view, serverName: ""
			)
		}

		let groups = ScrollbackSearchGroup.grouping([row("b", 4), row("a", 3), row("b", 2)])

		#expect(groups.map(\.viewIdentifier) == ["b", "a"])
		#expect(groups.first?.rows.count == 2)
	}
}
