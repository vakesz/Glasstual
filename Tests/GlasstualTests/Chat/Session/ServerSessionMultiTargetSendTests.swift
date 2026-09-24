// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

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
struct ServerSessionMultiTargetSendTests {
	@Test("A queued slash command retains its original channel after selection changes")
	func queuedSlashCommandKeepsTarget() async throws {
		let session = session()
		session.markAsLoggedIn()
		let targets = try channels(["#one", "#two"], on: session)
		session.recordedOutput.selectedSession = session
		session.recordedOutput.selectedConversation = targets[0]
		let admission = RenderAdmission(capacity: 1)
		session.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { session.cancelPendingSessionTasks(); admission.finish(ticket) }
		session.inputText("/me hello", destination: targets[0])
		#expect(session.sentLines.count == 0)
		session.recordedOutput.selectedConversation = targets[1]
		admission.finish(ticket)
		await drainProducer(on: session)
		#expect(session.sentLines as? [String] == ["PRIVMSG #one :\u{1}ACTION hello\u{1}"])
	}

	@Test("A queued console command cannot adopt a newly selected channel")
	func queuedConsoleCommandKeepsNoTarget() async throws {
		let session = session()
		session.markAsLoggedIn()
		let channel = try #require(channels(["#one"], on: session).first)
		session.recordedOutput.selectedSession = session
		session.recordedOutput.selectedConversation = nil
		let admission = RenderAdmission(capacity: 1)
		session.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { session.cancelPendingSessionTasks(); admission.finish(ticket) }
		session.inputText("/part", destination: session)
		#expect(session.sentLines.count == 0)
		session.recordedOutput.selectedConversation = channel
		admission.finish(ticket)
		await drainProducer(on: session)
		#expect(session.sentLines.count == 0)
	}

	private func drainProducer(on session: ServerSession) async {
		let deadline = ContinuousClock.now + .seconds(5)
		while session.outboundTextProducer?.pendingProducerCount != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		#expect(session.outboundTextProducer?.pendingProducerCount == 0)
	}

	@Test("An approved large paste waits for transcript capacity and keeps later input behind it", .timeLimit(.minutes(1)))
	func largePasteHasBoundedOrderedAdmission() async throws {
		let session = session()
		let channel = try #require(channels(["#one"], on: session).first)
		let admission = RenderAdmission(capacity: 2)
		session.renderAdmission = admission
		let initial = [admission.submit(for: "existing"), admission.submit(for: "existing")]
		var tickets: [UUID] = []
		let (printed, continuation) = AsyncStream<String>.makeStream()
		defer { session.cancelPendingSessionTasks(); continuation.finish() }
		session.linePrintObserver = { request in
			tickets.append(admission.submit(for: channel.uniqueIdentifier))
			continuation.yield(request.messageBody)
		}
		let expected = (0 ..< 80).map { "line-\($0)" }
		session.inputText(expected.joined(separator: "\n"), destination: channel)
		let confirmation = try #require(session.pendingConfirmationTasks.values.first)
		await confirmation.value
		#expect(session.sentLines.count == 0)
		#expect(session.outboundTextProducer?.pendingProducerCount == 1)
		session.inputText("after", destination: channel)
		#expect(session.outboundTextProducer?.pendingProducerCount == 2)
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
		#expect(session.sentLines.compactMap { $0 as? String } == (expected + ["after"]).map { "PRIVMSG #one :\($0)" })
	}

	private nonisolated enum DestinationChange: CaseIterable {
		case removed, renamed, reconnected
	}

	@Test("A queued text producer rejects a changed target or IRC session", arguments: DestinationChange.allCases)
	private func queuedTextValidatesDestination(change: DestinationChange) async throws {
		let session = session()
		let channel = try #require(session.findConversationOrCreate("alice", isDirect: true))
		channel.activate()
		let admission = RenderAdmission(capacity: 1)
		session.renderAdmission = admission
		let ticket = admission.submit(for: "existing")
		defer { session.cancelPendingSessionTasks(); admission.finish(ticket) }
		session.sendText(NSAttributedString(string: "must not cross the boundary"), as: .privmsg, to: channel)
		#expect(session.sentLines.count == 0)
		switch change {
		case .reconnected:
			session.startup = StartupState()
		case .removed:
			session.conversationList.removeAll { $0 === channel }
		case .renamed:
			channel.name = "bob"
			try #require(channel.name == "bob")
		}
		admission.finish(ticket)
		let deadline = ContinuousClock.now + .seconds(5)
		while session.outboundTextProducer?.pendingProducerCount != 0, ContinuousClock.now < deadline {
			await Task.yield()
		}
		#expect(session.outboundTextProducer?.pendingProducerCount == 0)
		#expect(session.sentLines.count == 0)
	}

	private func session() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me", "username": "me"])
		session.userHostmask = "me!user@example.org"

		return session
	}

	private func channels(_ names: [String], on session: TestServerSession) throws -> [Conversation] {
		try names.map { name in
			let channel = try #require(session.findConversationOrCreate(name))
			channel.activate()

			return channel
		}
	}

	@Test("A server that advertises no TARGMAX gets one command per channel")
	func withoutTargmaxEachChannelGetsItsOwnLine() throws {
		let session = session()
		let targets = try channels(["#one", "#two", "#three"], on: session)

		/* Zero is what "the server said nothing" reads as, and nothing is what
		 a session may not build a comma-separated target list on. */
		#expect(session.supportInfo.maximumTargets(forCommand: "PRIVMSG") == 0)
		#expect(session.supportInfo.groupsMultipleTargets(forCommand: "PRIVMSG") == false)

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: targets)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
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
		let session = session()
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:1")
		let targets = try channels(["#one", "#two"], on: session)

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: targets)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one :hello",
				"PRIVMSG #two :hello",
			]
		)
	}

	/** `TARGMAX=PRIVMSG:` — the command named with an empty value — is how a
	 server says it imposes no limit for that command. It reads back as the same
	 zero as a server that never mentioned `PRIVMSG` at all, and the session
	 gives both the same conservative answer: one line per channel. A list a
	 server never asked for is one it may answer with `ERR_TOOMANYTARGETS` or
	 quietly truncate, and the user cannot see either happen. */
	@Test("An empty TARGMAX value sends one command per channel")
	func emptyTargmaxValueIsUngrouped() throws {
		let session = session()
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:")
		let targets = try channels(["#one", "#two"], on: session)

		#expect(session.supportInfo.maximumTargets(forCommand: "PRIVMSG") == 0)

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: targets)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
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
		let session = session()
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:2")
		let targets = try channels(["#one", "#two", "#three", "#four", "#five"], on: session)

		#expect(session.supportInfo.groupsMultipleTargets(forCommand: "PRIVMSG"))

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: targets)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
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
		let session = session()
		session.setConnectionTransportForTesting(.connected)
		session.markAsLoggedIn()
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")
		_ = try channels(["#one", "#two"], on: session)

		session.sendCommand("msg #ONE,#two,#One hello", completeTarget: false, target: nil)

		#expect(session.sentLines.compactMap { $0 as? String } == ["PRIVMSG #one,#two :hello"])
	}

	/// `MAXTARGETS` is the older, command-agnostic form of the same statement,
	/// and it groups the same way for a command `TARGMAX` did not name.
	@Test("MAXTARGETS groups the channels where TARGMAX named no command")
	func maximumTargetsGroupsChannels() throws {
		let session = session()
		session.supportInfo.processConfigurationData("MAXTARGETS=3")
		let targets = try channels(["#one", "#two", "#three", "#four"], on: session)

		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: targets)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG #one,#two,#three :hello",
				"PRIVMSG #four :hello",
			]
		)
	}

	/// A query is not a channel, so it is sent on its own even where the server
	/// would take several targets on one command.
	@Test("A private message is never grouped with a channel")
	func queriesAreSentOnTheirOwn() throws {
		let session = session()
		session.supportInfo.processConfigurationData("TARGMAX=PRIVMSG:4")

		let channel = try #require(session.findConversationOrCreate("#one"))
		let query = try #require(session.findConversationOrCreate("alice", isDirect: true))
		let second = try #require(session.findConversationOrCreate("#two"))
		channel.activate()
		query.activate()
		second.activate()

		session.sendText(
			NSAttributedString(string: "hello"),
			as: .privmsg,
			toConversations: [channel, query, second]
		)

		#expect(
			session.sentLines.compactMap { $0 as? String } == [
				"PRIVMSG alice :hello",
				"PRIVMSG #one,#two :hello",
			]
		)
	}

	@Test("Nothing is sent for an empty message or an empty target list")
	func emptyInputSendsNothing() throws {
		let session = session()
		let targets = try channels(["#one"], on: session)

		session.sendText(NSAttributedString(string: ""), as: .privmsg, toConversations: targets)
		session.sendText(NSAttributedString(string: "hello"), as: .privmsg, toConversations: [])

		#expect(session.sentLines.count == 0)
	}
}
