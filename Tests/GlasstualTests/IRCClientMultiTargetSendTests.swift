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
struct IRCClientMultiTargetSendTests {
	private func client() -> GLTTestClient {
		let client = GLTTestClient(configDictionary: ["nickname": "me", "username": "me"])
		client.userHostmask = "me!user@example.org"

		return client
	}

	private func channels(_ names: [String], on client: GLTTestClient) throws -> [IRCChannel] {
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
