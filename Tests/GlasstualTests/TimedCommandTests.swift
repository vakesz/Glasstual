// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Timed commands")
struct TimedCommandTests {
	@Test("A timed command records the client and channel it was made for")
	func initializationCapturesCommandContextAndUniqueIdentifiers() {
		let client = TestClient()
		let channel = Channel(config: ChannelConfig(channelName: "#chat"))

		let first = TimedCommand(command: "WHO #chat", onClient: client, inChannel: channel)
		let second = TimedCommand(command: "PING", onClient: client)

		#expect(first.command == "WHO #chat")
		#expect(first.clientId == client.uniqueIdentifier)
		#expect(first.channelId == channel.uniqueIdentifier)
		#expect(second.channelId == nil)
		#expect(first.identifier != second.identifier)
	}

	@Test("Restarting needs a previous start and reuses that timer's configuration")
	func restartRequiresPreviousStartAndPreservesTimerConfiguration() {
		let client = TestClient()
		let command = TimedCommand(command: "PING", onClient: client)

		#expect(command.restart() == false)

		command.start(30, onRepeat: true, iterations: 3)

		#expect(command.timer.isActive)
		#expect(command.timer.interval == 30)
		#expect(command.timer.repeats)
		#expect(command.timer.iterations == 3)

		command.stop()

		#expect(command.timer.isActive == false)

		#expect(command.restart())
		#expect(command.timer.isActive)

		command.stop()
	}

	@Test("A timed command made in a channel that has since closed is removed rather than run elsewhere")
	func timedCommandForAClosedChannelIsRemoved() throws {
		let client = TestClient(configDictionary: ["nickname": "me"])
		client.isConnected = true
		client.markAsLoggedIn()
		let closed = try #require(client.findChannelOrCreate("#closed"))
		let selected = try #require(client.findChannelOrCreate("#selected"))
		closed.activate()
		selected.activate()
		client.recordedOutput.selectedClient = client
		client.recordedOutput.selectedChannel = selected

		let timedCommand = TimedCommand(command: "me waves", onClient: client, inChannel: closed)
		client.addTimedCommand(timedCommand)
		client.channelList.removeAll { $0 === closed }

		client.onTimedCommand(timedCommand)

		#expect(client.sentLines.count == 0)
		#expect(client.timedCommand(withIdentifier: timedCommand.identifier) == nil)
	}

	@Test("A timed command runs in the channel it was made in, not the one selected when it fires")
	func timedCommandRunsInItsOwnChannel() throws {
		let client = TestClient(configDictionary: ["nickname": "me"])
		client.isConnected = true
		client.markAsLoggedIn()
		let origin = try #require(client.findChannelOrCreate("#origin"))
		let selected = try #require(client.findChannelOrCreate("#selected"))
		origin.activate()
		selected.activate()
		client.recordedOutput.selectedClient = client
		client.recordedOutput.selectedChannel = selected

		let inChannel = TimedCommand(command: "me waves", onClient: client, inChannel: origin)
		let inConsole = TimedCommand(command: "me waves", onClient: client)

		client.onTimedCommand(inChannel)
		client.onTimedCommand(inConsole)

		let sent = client.sentLines.compactMap { $0 as? String }
		#expect(sent.first == "PRIVMSG #origin :\u{01}ACTION waves\u{01}")
		#expect(sent.contains { $0.hasPrefix("PRIVMSG #selected") } == false)
	}

	@Test("The client owns its timed commands and hands them back by identifier")
	func clientOwnsTimedCommandsThroughTheSwiftStore() {
		let client = TestClient()
		let first = TimedCommand(command: "PING", onClient: client)
		let second = TimedCommand(command: "WHO #chat", onClient: client)

		client.addTimedCommand(first)
		client.addTimedCommand(second)

		#expect(client.timedCommand(withIdentifier: first.identifier) === first)
		#expect(Set(client.listOfTimedCommands().map(\.identifier)) == [first.identifier, second.identifier])

		client.removeTimedCommand(first)
		#expect(client.timedCommand(withIdentifier: first.identifier) == nil)
		#expect(client.listOfTimedCommands().map(\.identifier) == [second.identifier])

		client.removeTimedCommands()
		#expect(client.listOfTimedCommands().isEmpty)
	}
}
