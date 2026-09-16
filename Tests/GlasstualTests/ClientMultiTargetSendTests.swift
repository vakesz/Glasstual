/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

/** Sending one message to several channels — `/amsg`, and the multi-selection
 the server list allows — groups the targets onto one command only when the
 server said it would accept several. Almost no server advertises `TARGMAX` for
 `PRIVMSG`, so the ungrouped path is the one nearly every user gets, and the
 grouped tests in `IRCSpecBatchTests` all set `TARGMAX` first. */
@MainActor
@Suite("Multi-target text sending")
struct ClientMultiTargetSendTests {
	@Test("A queued slash command retains its original channel after selection changes")
	func queuedSlashCommandKeepsTarget() async throws {
		let client = client()
		client.markAsLoggedIn()
		let targets = try channels(["#one", "#two"], on: client)
		client.recordedOutput.selectedClient = client
		client.recordedOutput.selectedChannel = targets[0]
		let admission = TranscriptRenderAdmission(capacity: 1)
		client.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { client.cancelPendingSessionTasks(); admission.finish(ticket) }
		client.inputText("/me hello", destination: targets[0])
		#expect(client.sentLines.count == 0)
		client.recordedOutput.selectedChannel = targets[1]
		admission.finish(ticket)
		await drainProducer(on: client)
		#expect(client.sentLines as? [String] == ["PRIVMSG #one :\u{1}ACTION hello\u{1}"])
	}

	@Test("A queued console command cannot adopt a newly selected channel")
	func queuedConsoleCommandKeepsNoTarget() async throws {
		let client = client()
		client.markAsLoggedIn()
		let channel = try #require(channels(["#one"], on: client).first)
		client.recordedOutput.selectedClient = client
		client.recordedOutput.selectedChannel = nil
		let admission = TranscriptRenderAdmission(capacity: 1)
		client.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { client.cancelPendingSessionTasks(); admission.finish(ticket) }
		client.inputText("/part", destination: client)
		#expect(client.sentLines.count == 0)
		client.recordedOutput.selectedChannel = channel
		admission.finish(ticket)
		await drainProducer(on: client)
		#expect(client.sentLines.count == 0)
	}

	private func drainProducer(on client: Client) async {
		let deadline = ContinuousClock.now + .seconds(5)
		while client.outboundTextProducer?.pendingProducerCount != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		#expect(client.outboundTextProducer?.pendingProducerCount == 0)
	}

	@Test("An approved large paste waits for transcript capacity and keeps later input behind it", .timeLimit(.minutes(1)))
	func largePasteHasBoundedOrderedAdmission() async throws {
		let client = client()
		let channel = try #require(channels(["#one"], on: client).first)
		let admission = TranscriptRenderAdmission(capacity: 2)
		client.renderAdmission = admission
		let initial = [admission.submit(for: "existing"), admission.submit(for: "existing")]
		var tickets: [UUID] = []
		let (printed, continuation) = AsyncStream<String>.makeStream()
		defer { client.cancelPendingSessionTasks(); continuation.finish() }
		client.linePrintObserver = { request in
			tickets.append(admission.submit(for: channel.uniqueIdentifier))
			continuation.yield(request.messageBody)
		}
		let expected = (0 ..< 80).map { "line-\($0)" }
		client.inputText(expected.joined(separator: "\n"), destination: channel)
		let confirmation = try #require(client.pendingConfirmationTasks.values.first)
		await confirmation.value
		#expect(client.sentLines.count == 0)
		#expect(client.outboundTextProducer?.pendingProducerCount == 1)
		client.inputText("after", destination: channel)
		#expect(client.outboundTextProducer?.pendingProducerCount == 2)
		for ticket in initial {
			admission.finish(ticket)
		}
		var iterator = printed.makeAsyncIterator()
		for body in expected + ["after"] {
			#expect(await iterator.next() == body)
			#expect(admission.pendingCount <= 2)
			let ticket = try #require(tickets.first)
			tickets.removeFirst()
			admission.finish(ticket)
		}
		#expect(client.sentLines.compactMap { $0 as? String } == (expected + ["after"]).map { "PRIVMSG #one :\($0)" })
	}

	private nonisolated enum DestinationChange: CaseIterable { // nonisolated: value
		case removed, renamed, reconnected
	}

	@Test("A queued text producer rejects a changed target or IRC session", arguments: DestinationChange.allCases)
	private func queuedTextValidatesDestination(change: DestinationChange) async throws {
		let client = client()
		let channel = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		channel.activate()
		let admission = TranscriptRenderAdmission(capacity: 1)
		client.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { client.cancelPendingSessionTasks(); admission.finish(ticket) }
		client.sendText(NSAttributedString(string: "must not cross the boundary"), as: .privmsg, to: channel)
		#expect(client.sentLines.count == 0)
		switch change {
		case .reconnected:
			client.startup = StartupState()
		case .removed:
			client.channelList.removeAll { $0 === channel }
		case .renamed:
			channel.name = "bob"
			try #require(channel.name == "bob")
		}
		admission.finish(ticket)
		let deadline = ContinuousClock.now + .seconds(5)
		while client.outboundTextProducer?.pendingProducerCount != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		#expect(client.outboundTextProducer?.pendingProducerCount == 0)
		#expect(client.sentLines.count == 0)
	}

	private func client() -> TestClient {
		let client = TestClient(configDictionary: ["nickname": "me", "username": "me"])
		client.userHostmask = "me!user@example.org"

		return client
	}

	private func channels(_ names: [String], on client: TestClient) throws -> [Channel] {
		try names.map { name in
			let channel = try #require(client.findChannelOrCreate(name))
			channel.activate()

			return channel
		}
	}

	@Test("A server that advertises no TARGMAX gets one command per channel")
	func withoutTargmaxEachChannelGetsItsOwnLine() throws {
		let client = client()
		let targets = try channels(["#one", "#two", "#three"], on: client)

		/* Zero is what "the server said nothing" reads as, and nothing is what
		 a client may not build a comma-separated target list on. */
		#expect(client.supportInfo.maximumTargets(forCommand: "PRIVMSG") == 0)
		#expect(client.supportInfo.groupsMultipleTargets(forCommand: "PRIVMSG") == false)

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: targets)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one :hello",
				"PRIVMSG #two :hello",
				"PRIVMSG #three :hello",
			]
		)
	}

	/// `TARGMAX=PRIVMSG:1` says outright that one target is the most it takes,
	/// which has to read the same way as advertising nothing at all.
	@Test("A TARGMAX of one is the same as no TARGMAX")
	func aTargmaxOfOneIsUngrouped() throws {
		let client = client()
		client.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:1")
		let targets = try channels(["#one", "#two"], on: client)

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: targets)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one :hello",
				"PRIVMSG #two :hello",
			]
		)
	}

	/** `TARGMAX=PRIVMSG:` — the command named with an empty value — is how a
	 server says it imposes no limit for that command. It reads back as the same
	 zero as a server that never mentioned `PRIVMSG` at all, and the client
	 gives both the same conservative answer: one line per channel. A list a
	 server never asked for is one it may answer with `ERR_TOOMANYTARGETS` or
	 quietly truncate, and the user cannot see either happen. */
	@Test("An empty TARGMAX value sends one command per channel")
	func emptyTargmaxValueIsUngrouped() throws {
		let client = client()
		client.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:")
		let targets = try channels(["#one", "#two"], on: client)

		#expect(client.supportInfo.maximumTargets(forCommand: "PRIVMSG") == 0)

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: targets)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one :hello",
				"PRIVMSG #two :hello",
			]
		)
	}

	/** A limit the server did advertise is used to the letter: the channels go
	 out in comma-separated groups of that size, in order, and the remainder
	 rides the last line. */
	@Test("A TARGMAX above one groups the channels into lines that size")
	func aTargmaxAboveOneGroupsChannels() throws {
		let client = client()
		client.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:2")
		let targets = try channels(["#one", "#two", "#three", "#four", "#five"], on: client)

		#expect(client.supportInfo.groupsMultipleTargets(forCommand: "PRIVMSG"))

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: targets)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one,#two :hello",
				"PRIVMSG #three,#four :hello",
				"PRIVMSG #five :hello",
			]
		)
	}

	/// A destination is matched to its channel under the server's casemapping,
	/// so a spelling that differs from the channel's own is still the channel
	/// the grouped line already reached.
	@Test("A /msg destination spelled differently from its channel is sent once")
	func msgDestinationMatchedByCasemappingIsSentOnce() throws {
		let client = client()
		client.isConnected = true
		client.markAsLoggedIn()
		client.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")
		_ = try channels(["#one", "#two"], on: client)

		client.sendCommand("msg #ONE,#two,#One hello", completeTarget: false, target: nil)

		#expect(client.sentLines.compactMap { $0 as? String } == ["PRIVMSG #one,#two :hello"])
	}

	/// `MAXTARGETS` is the older, command-agnostic form of the same statement,
	/// and it groups the same way for a command `TARGMAX` did not name.
	@Test("MAXTARGETS groups the channels where TARGMAX named no command")
	func maximumTargetsGroupsChannels() throws {
		let client = client()
		client.supportInfo.processConfigurationData("MAXTARGETS=3")
		let targets = try channels(["#one", "#two", "#three", "#four"], on: client)

		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: targets)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one,#two,#three :hello",
				"PRIVMSG #four :hello",
			]
		)
	}

	/// A query is not a channel, so it is sent on its own even where the server
	/// would take several targets on one command.
	@Test("A private message is never grouped with a channel")
	func queriesAreSentOnTheirOwn() throws {
		let client = client()
		client.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")

		let channel = try #require(client.findChannelOrCreate("#one"))
		let query = try #require(client.findChannelOrCreate("alice", isPrivateMessage: true))
		let second = try #require(client.findChannelOrCreate("#two"))
		channel.activate()
		query.activate()
		second.activate()

		client.sendText(
			NSAttributedString(string: "hello"),
			as: .privmsg,
			toChannels: [channel, query, second]
		)

		#expect(
			client.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG alice :hello",
				"PRIVMSG #one,#two :hello",
			]
		)
	}

	@Test("Nothing is sent for an empty message or an empty target list")
	func emptyInputSendsNothing() throws {
		let client = client()
		let targets = try channels(["#one"], on: client)

		client.sendText(NSAttributedString(string: ""), as: .privmsg, toChannels: targets)
		client.sendText(NSAttributedString(string: "hello"), as: .privmsg, toChannels: [])

		#expect(client.sentLines.count == 0)
	}
}
