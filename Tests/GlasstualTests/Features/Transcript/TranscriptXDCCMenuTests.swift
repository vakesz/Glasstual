// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
import Foundation
@testable import Glasstual
import Testing

/// A bot's line offers its pack in the transcript's context menu, and the
/// request goes to the transcript's own connection.
@MainActor
@Suite("Transcript XDCC menu")
struct TranscriptXDCCMenuTests {
	private func row(_ text: String, from nickname: String = "Bot", type: ChatLineKind = .privateMessage) -> TranscriptRow {
		TranscriptRow(
			lineNumber: "1", receivedAt: Date(timeIntervalSince1970: 0),
			nickname: nickname, memberType: .normal, lineType: type, command: "PRIVMSG",
			messageIdentifier: nil, replyToMessageIdentifier: nil,
			deliveryState: .none, deliveryFailureReason: nil, reactions: [:], markers: [],
			body: TranscriptBody(plainText: text, runs: [TranscriptTextRun(text: text)])
		)
	}

	@Test("A listing line or an announcement carries its pack", arguments: [
		ChatLineKind.privateMessage, .action, .notice,
	])
	func packIsRecognised(type: ChatLineKind) {
		#expect(row("#12  5x [1.2G] Some.File.mkv", type: type).xdccPack?.pack == 12)
		#expect(row("Get it: /msg Other xdcc send #3", from: "announcer", type: type).xdccPack?.bot == "Other")
	}

	@Test("Other line types and ordinary text carry nothing", arguments: [
		ChatLineKind.topic, .join, .debug, .dccFileTransfer,
	])
	func otherLinesCarryNothing(type: ChatLineKind) {
		#expect(row("#12  5x [1.2G] Some.File.mkv", type: type).xdccPack == nil)
		#expect(row("we are #1 at this").xdccPack == nil)
	}

	@Test("The menu names the pack and bot, and offers nothing while logged out")
	func menuItems() throws {
		var requested: [(XDCCPackReference, Bool)] = []
		var sink = TranscriptCommandSink()
		sink.requestXDCCPack = { _, pack, info in requested.append((pack, info)) }
		let commands = TranscriptCommands(sink: sink)
		let session = TestServerSession()
		let pack = XDCCPackReference(bot: "Bot", pack: 12, filename: "file.mkv", sizeText: nil, gets: nil)

		#expect(commands.xdccMenuItems(for: pack, session: session).isEmpty)
		#expect(commands.xdccMenuItems(for: nil, session: session).isEmpty)

		session.markAsLoggedIn()
		let items = commands.xdccMenuItems(for: pack, session: session).filter { $0.isSeparatorItem == false }
		#expect(items.map(\.title) == [
			String(localized: .Transcript.requestPackFromBot("12", "Bot")),
			String(localized: .Transcript.getPackInfo),
		])

		for item in items {
			let action = try #require(item.action)
			_ = (item.target as? NSObject)?.perform(action, with: item)
		}
		#expect(requested.map(\.0.pack) == [12, 12])
		#expect(requested.map(\.1) == [false, true])
	}
}
