// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Transcript paths")
struct TranscriptPathTests {
	@Test("A transcript path is built from the session folder and the item's kind")
	func transcriptPathsCoverConsolesChannelsAndDirectConversations() {
		let session = TestServerSession()
		let root = "/tmp/glasstual-logs"
		let identifier = String(session.uniqueIdentifier.prefix(5))
		let sessionFolder = "\(session.name.safeFilename) (\(identifier))"

		let expectedConsole = (root as NSString).appendingPathComponent(
			"/\(sessionFolder)/\(TranscriptFolderName.console)/"
		)

		#expect(TranscriptPath.write(for: session, relativeTo: root) == expectedConsole)

		let channel = makeChannel(named: "#chat", type: .channel, session: session)
		let expectedChannel = (root as NSString).appendingPathComponent(
			"/\(sessionFolder)/\(TranscriptFolderName.channel)/\("#chat".safeFilename)/"
		)

		let channelSidebarItem: ChatItem = channel
		#expect(TranscriptPath.write(for: channelSidebarItem, relativeTo: root) == expectedChannel)

		let query = makeChannel(named: "alice", type: .direct, session: session)
		let expectedQuery = (root as NSString).appendingPathComponent(
			"/\(sessionFolder)/\(TranscriptFolderName.direct)/\("alice".safeFilename)/"
		)

		let querySidebarItem: ChatItem = query
		#expect(TranscriptPath.write(for: querySidebarItem, relativeTo: root) == expectedQuery)
	}

	@Test("A console conversation has no transcript path, and neither has a session without a folder")
	func consolesAndSessionsWithoutAFolderHaveNoPath() {
		let session = TestServerSession()
		let console = makeChannel(named: "Console", type: .console, session: session)

		let consoleSidebarItem: ChatItem = console
		#expect(TranscriptPath.write(for: consoleSidebarItem, relativeTo: "/tmp/glasstual-logs") == nil)
		#expect(TranscriptPath.write(for: session) == nil)
	}

	@Test("Writing without a transcript folder opens no file")
	func writingWithoutATranscriptFolderDoesNotOpenAFile() async {
		let sink = RecordingFileLogSink()
		let commands = FileLogCommands(sink: FileLogSinkPort { await sink.process($0) })
		let session = TestServerSession()
		let logger = FileLogger(session: session, commands: commands)

		logger.writePlainText("should not write")

		#expect(await commands.flush())
		#expect(await sink.operations == [.flush])
		withExtendedLifetime(logger) {}
	}

	private func makeChannel(named name: String, type: ConversationKind, session: ServerSession) -> Conversation {
		let channel = Conversation(config: ConversationConfig(name: name, type: type))

		channel.associatedSession = session

		return channel
	}
}
