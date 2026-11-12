// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/** Each editor, under each style: the sheet, or the exact command it puts in
 the message field and what it selects there. */
@Suite("Editor routing")
struct EditorRoutingTests {
	nonisolated struct Row: Sendable, CustomTestStringConvertible {
		let request: EditorRequest
		let command: String
		let selected: String?

		var testDescription: String {
			command
		}
	}

	nonisolated static let rows: [Row] = [
		Row(request: .newServer, command: "/server ", selected: nil),
		Row(request: .serverProperties, command: "/serverconfig ", selected: nil),
		Row(request: .addChannel, command: "/join #", selected: "#"),
		Row(request: .channelProperties(channel: "#swift"), command: "/channelconfig #swift ", selected: nil),
		Row(request: .topic(channel: "#swift", current: "Welcome!"), command: "/topic #swift Welcome!", selected: "Welcome!"),
		Row(request: .modes(channel: "#swift"), command: "/mode #swift ", selected: nil),
		Row(request: .invite(nicknames: ["ada", "grace"]), command: "/invite ada grace #", selected: nil),
		Row(request: .nickname(current: "ada"), command: "/nick ada", selected: "ada"),
		Row(request: .nicknameColor(nickname: "ada"), command: "/setcolor ada ", selected: nil),
		Row(request: .ignore(mask: "*!*@spam.example"), command: "/ignore *!*@spam.example ", selected: nil),
		Row(request: .ignore(mask: nil), command: "/ignore ", selected: nil),
		Row(request: .virtualHost(nickname: "ada"), command: "/hs setall ada ", selected: nil),
		Row(request: .redact(messageID: "abc123"), command: "/redact abc123 ", selected: nil),
		Row(request: .saslSignIn, command: "/sasl auth", selected: nil),
		Row(request: .registerAccount, command: "/register ", selected: nil),
	]

	@Test("In the conversation, an editor is its command", arguments: rows)
	func conversation(_ row: Row) {
		guard case let .prefill(command, selection) = EditorRouting.route(row.request, style: .conversation) else {
			Issue.record("Expected a command for \(row.request)")
			return
		}
		#expect(command == row.command)
		#expect(selection.map { (command as NSString).substring(with: $0) } == row.selected)
	}

	@Test("With dialogs, every editor is its sheet", arguments: rows)
	func dialogs(_ row: Row) {
		#expect(EditorRouting.route(row.request, style: .dialogs) == .sheet)
	}

	@Test("The topic selection counts UTF-16, so a topic with emoji is selected whole")
	func emojiTopic() {
		let route = EditorRouting.route(.topic(channel: "#café", current: "Hi 👋"), style: .conversation)
		guard case let .prefill(command, selection?) = route else {
			Issue.record("Expected a selection")
			return
		}
		#expect((command as NSString).substring(with: selection) == "Hi 👋")
	}
}
