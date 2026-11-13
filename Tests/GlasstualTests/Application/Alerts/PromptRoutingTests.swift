// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Which form a question takes. The decision table in `PromptRouting`, one
 row at a time, plus the window rule each dialog carries. */
@Suite("Prompt routing")
struct PromptRoutingTests {
	nonisolated struct Row: Sendable, CustomTestStringConvertible {
		let name: String
		let style: InteractionStyle
		let allowsInline: Bool
		let origin: PromptOrigin
		let anchor: String?
		let expected: PromptRoute

		var testDescription: String {
			name
		}
	}

	nonisolated static let rows: [Row] = [
		Row(name: "R1 dialogs", style: .dialogs, allowsInline: true, origin: .conversation, anchor: "item",
		    expected: .dialog(revealsMainWindow: true)),
		Row(name: "R2 needs a dialog", style: .conversation, allowsInline: false, origin: .conversation, anchor: "item",
		    expected: .dialog(revealsMainWindow: true)),
		Row(name: "R3 inside a sheet", style: .conversation, allowsInline: true, origin: .guiSurface, anchor: "item",
		    expected: .dialog(revealsMainWindow: true)),
		Row(name: "R4 nowhere to show it", style: .conversation, allowsInline: true, origin: .application, anchor: nil,
		    expected: .dialog(revealsMainWindow: true)),
		Row(name: "R5 conversation", style: .conversation, allowsInline: true, origin: .conversation, anchor: "item",
		    expected: .inline(itemID: "item")),
		Row(name: "R5 application", style: .conversation, allowsInline: true, origin: .application, anchor: "console",
		    expected: .inline(itemID: "console")),
	]

	@Test("Each rule decides its row", arguments: rows)
	func decisionTable(_ row: Row) {
		let route = PromptRouting.route(
			style: row.style, allowsInline: row.allowsInline, origin: row.origin,
			anchor: row.anchor, revealsMainWindow: true
		)
		#expect(route == row.expected)
	}

	@Test("A dialog nobody raised from the main window leaves it hidden")
	func backgroundDialogDoesNotReveal() {
		let route = PromptRouting.route(
			style: .dialogs, allowsInline: true, origin: .conversation, anchor: "item", revealsMainWindow: false
		)
		#expect(route == .dialog(revealsMainWindow: false))
		#expect(route.itemID == nil)
	}
}
