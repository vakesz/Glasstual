/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import GlasstualPluginKit
import Testing

@Suite("JOIN batching")
@MainActor
struct IRCJoinBatchingTests {
	@Test(
		"Parsed JOIN and channel limits keep zero unlimited and accept all UInt counts",
		arguments: ["", "0", "1", "2", String(Int.max), String(UInt(Int.max) + 1), String(UInt.max)]
	)
	func parsedCountsReachJoinBatching(_ value: String) {
		let info = IRCISupportInfo()
		let names = ["#a", "#b", "#c"]
		let expected = value == "1" ? names.map { [$0] }
			: value == "2" ? [["#a", "#b"], ["#c"]] : [names]

		info.processConfigurationData("TARGMAX=JOIN:\(value)")
		#expect(IRCJoinBatching.batches(
			for: targets(names), maximumTargets: info.maximumTargets(forCommand: "JOIN")
		).map(\.channels) == expected)

		info.processConfigurationData("CHANLIMIT=#:\(value)")
		#expect(IRCJoinBatching.batches(
			for: targets(names), channelLimits: info.channelLimits
		).map(\.channels) == expected)
	}

	private func targets(_ names: [String], key: String? = nil) -> [IRCJoinBatching.Target] {
		names.map { IRCJoinBatching.Target(name: $0, key: key) }
	}

	@Test("A short channel list goes out as one command")
	func singleBatch() {
		let batches = IRCJoinBatching.batches(for: targets(["#a", "#b", "#c"]))

		#expect(batches == [IRCJoinBatching.Batch(channels: ["#a", "#b", "#c"], keys: [])])
	}

	@Test("Order is preserved and nothing is dropped")
	func preservesOrderAndCompleteness() {
		let names = (0 ..< 200).map { "#channel-with-a-fairly-long-name-\($0)" }
		let batches = IRCJoinBatching.batches(for: targets(names))

		#expect(batches.count > 1)
		#expect(batches.flatMap(\.channels) == names)
	}

	@Test("Every batch fits the line budget")
	func respectsLineBudget() {
		let names = (0 ..< 200).map { "#channel-with-a-fairly-long-name-\($0)" }
		let batches = IRCJoinBatching.batches(for: targets(names))

		for batch in batches {
			let line = "JOIN " + batch.channels.joined(separator: ",")
			#expect(line.utf8.count <= IRCProtocolLimits.maximumBodyLength)
		}
	}

	@Test("Byte length, not character count, drives the split")
	func measuresUTF8Bytes() {
		// Each name is 2 characters but 8 UTF-8 bytes.
		let names = (0 ..< 40).map { _ in "#\u{1F4AC}" }
		let byteBatches = IRCJoinBatching.batches(for: targets(names), maximumLineLength: 40)

		for batch in byteBatches {
			let payload = batch.channels.joined(separator: ",")
			#expect(payload.utf8.count <= 40)
		}
		#expect(byteBatches.flatMap(\.channels).count == names.count)
	}

	@Test("MAXTARGETS caps the number of channels per command")
	func respectsMaximumTargets() {
		let batches = IRCJoinBatching.batches(
			for: targets(["#a", "#b", "#c", "#d", "#e"]),
			maximumTargets: 2
		)

		#expect(batches.map(\.channels) == [["#a", "#b"], ["#c", "#d"], ["#e"]])
	}

	@Test("CHANLIMIT caps channels of one prefix per command")
	func respectsChannelLimits() {
		let batches = IRCJoinBatching.batches(
			for: targets(["#a", "#b", "&c", "#d"]),
			channelLimits: ["#": 2]
		)

		#expect(batches.map(\.channels) == [["#a", "#b", "&c"], ["#d"]])
	}

	@Test("Keyed channels are sent separately and keep their keys aligned")
	func separatesKeyedChannels() {
		let mixed = [
			IRCJoinBatching.Target(name: "#open"),
			IRCJoinBatching.Target(name: "#locked", key: "secret"),
			IRCJoinBatching.Target(name: "#also-open", key: ""),
			IRCJoinBatching.Target(name: "#other", key: "hunter2"),
		]
		let batches = IRCJoinBatching.batches(for: mixed)

		#expect(batches == [
			IRCJoinBatching.Batch(channels: ["#open", "#also-open"], keys: []),
			IRCJoinBatching.Batch(channels: ["#locked", "#other"], keys: ["secret", "hunter2"]),
		])
	}

	@Test("A batch always carries at least one channel")
	func alwaysMakesProgress() {
		let batches = IRCJoinBatching.batches(
			for: targets(["#a-name-far-longer-than-the-budget"]),
			maximumLineLength: 1
		)

		#expect(batches == [IRCJoinBatching.Batch(channels: ["#a-name-far-longer-than-the-budget"], keys: [])])
	}

	@Test("An empty list produces no commands")
	func emptyInput() {
		#expect(IRCJoinBatching.batches(for: []).isEmpty)
	}

	/// `LINELEN` counts the CR LF the line ends with. Spending those two bytes
	/// on channel names put a server's `LINELEN=512` on the wire as 514.
	@Test("The advertised line length leaves room for the CR LF")
	func advertisedLineLengthLeavesRoomForTheTerminator() {
		let names = (0 ..< 60).map { "#channel-number-\($0)" }
		let batches = IRCJoinBatching.batches(for: targets(names), maximumLineLength: 512)

		for batch in batches {
			let line = "JOIN " + batch.channels.joined(separator: ",")

			#expect(line.utf8.count + 2 <= 512)
		}
		#expect(batches.flatMap(\.channels).count == names.count)
		// The default budget is the body length, which already excludes the pair.
		#expect(
			IRCJoinBatching.batches(for: targets(names), maximumLineLength: 0)
				== IRCJoinBatching.batches(for: targets(names), maximumLineLength: 512)
		)
	}
}

@Suite("JOIN command emission")
@MainActor
struct IRCClientJoinCommandTests {
	@Test("Offline and stopping clients cannot start single or batched joins", arguments: 0 ..< 16)
	func joinRequiresAvailableClient(flags: Int) throws {
		let client = GLTTestClient()
		client.isLoggedIn = flags & 1 != 0
		client.isQuitting = flags & 2 != 0
		client.isDisconnecting = flags & 4 != 0
		client.isTerminating = flags & 8 != 0
		let channel = try #require(client.findChannelOrCreate("#retry"))
		channel.errorOnLastJoinAttempt = true

		client.join(channel, password: "fixture-key")
		client.joinChannels([channel])

		#expect(channel.status == (flags == 1 ? .joining : .parted))
		#expect(channel.errorOnLastJoinAttempt == (flags != 1))
		#expect(client.sentLines.count == (flags == 1 ? 2 : 0))
	}

	@Test("JOIN rejects another client's channel, queries, and active channels")
	func joinRequiresOwnedInactiveChannel() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let other = GLTTestClient()
		let foreign = try #require(other.findChannelOrCreate("#foreign"))
		let query = try #require(client.findChannelOrCreate("friend", isPrivateMessage: true))
		let active = try #require(client.findChannelOrCreate("#active"))
		active.activate()
		for channel in [foreign, query, active] {
			client.join(channel)
		}
		client.joinChannels([foreign, query, active])
		#expect(client.sentLines.count == 0)
		#expect(foreign.status == .parted)
		#expect(active.isActive)
	}

	@Test("A pending join remains retryable with explicit, absent, or empty passwords")
	func pendingJoinCanRetry() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try #require(client.findChannelOrCreate("#retry"))
		client.join(channel, password: "explicit-fixture-key")
		#expect(channel.status == .joining)
		#expect(channel.isActive == false)
		channel.errorOnLastJoinAttempt = true
		client.join(channel)
		client.join(channel, password: "")
		#expect(client.sentLines.compactMap { $0 as? String } == [
			"JOIN #retry explicit-fixture-key", "JOIN #retry", "JOIN #retry",
		])
		#expect(channel.errorOnLastJoinAttempt == false)
	}

	@Test(
		"Join rejection retires pending state and refreshes presentation",
		arguments: [403, 437, 471, 473, 474, 475, 477]
	)
	func joinFailureRetiresPendingState(numeric: Int) throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try #require(client.findChannelOrCreate("#retry"))
		client.join(channel)
		let reloads = client.recordedOutput.reloadedItems.count
		let titles = client.recordedOutput.titleUpdates.count

		try client.receiveNumericReply(#require(Message(
			line: ":irc.example.test \(numeric) mynick #retry :Join rejected", on: client
		)))

		#expect(channel.status == .parted)
		#expect(channel.errorOnLastJoinAttempt)
		#expect(client.recordedOutput.reloadedItems.dropFirst(reloads).contains { $0 === channel })
		#expect(client.recordedOutput.titleUpdates.dropFirst(titles).contains { $0 === channel })
		client.join(channel)
		#expect(channel.status == .joining)
		#expect(channel.errorOnLastJoinAttempt == false)
		#expect(client.sentLines.compactMap { $0 as? String } == ["JOIN #retry", "JOIN #retry"])
	}

	@Test("Mode errors and stale join failures do not alter nonpending channels", arguments: [403, 437, 477])
	func nonpendingErrorsDoNotPartChannels(numeric: Int) throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try #require(client.findChannelOrCreate("#retry"))
		for active in [false, true] {
			if active {
				channel.activate()
			}
			let titles = client.recordedOutput.titleUpdates.count
			try client.receiveNumericReply(#require(Message(
				line: ":irc.example.test \(numeric) mynick #retry :No channel modes", on: client
			)))
			#expect(channel.status == (active ? .joined : .parted))
			#expect(channel.errorOnLastJoinAttempt == false)
			#expect(client.recordedOutput.titleUpdates.count == titles)
		}
	}

	@Test("Nickname-shaped 437 and server-shaped 402 do not retire a pending join")
	func otherTargetErrorsLeaveJoinPending() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()
		let channel = try #require(client.findChannelOrCreate("#retry"))
		client.join(channel)
		for line in [
			":irc.example.test 437 mynick nickname :Unavailable nickname",
			":irc.example.test 402 mynick #retry :No such server",
		] {
			try client.receiveNumericReply(#require(Message(line: line, on: client)))
		}
		#expect(channel.status == .joining)
		#expect(channel.errorOnLastJoinAttempt == false)
	}

	@Test("Many autojoin channels go out as several JOIN lines")
	func splitsAcrossLines() throws {
		let client = GLTTestClient()
		client.markAsLoggedIn()

		let channels = try (0 ..< 60).map { index in
			try #require(client.findChannelOrCreate("#channel-with-a-long-name-\(index)"))
		}

		client.joinChannels(channels)

		let lines = client.sentLines.compactMap { $0 as? String }

		#expect(lines.count > 1)
		#expect(lines.allSatisfy { $0.hasPrefix("JOIN ") })

		for line in lines {
			#expect(line.utf8.count <= IRCProtocolLimits.maximumBodyLength)
		}

		let joined = lines.flatMap {
			$0.dropFirst("JOIN ".count).components(separatedBy: ",")
		}
		#expect(Set(joined) == Set(channels.map(\.name)))
	}
}
