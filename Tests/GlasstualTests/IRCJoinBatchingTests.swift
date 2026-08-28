/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import Foundation
@testable import Glasstual
import Testing

@Suite("JOIN batching")
struct IRCJoinBatchingTests {
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
}

@MainActor
@Suite("JOIN command emission")
struct IRCClientJoinCommandTests {
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
