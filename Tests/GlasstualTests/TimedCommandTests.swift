/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

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
