// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Splits a set of channels into `JOIN` commands that each fit inside one
/// protocol line.
///
/// A `JOIN` carrying every autojoin channel on a single line is silently
/// truncated by the server, so the user quietly misses channels. The batching
/// is a pure function of the channel list and the server's advertised limits
/// so that it can be tested without a connection.
enum JoinBatching {
	/// One `JOIN` command: the channel names and the keys that go with them.
	///
	/// `keys` is empty for a keyless batch. When it is not empty it has the
	/// same count as `channels`, because the server matches the two lists
	/// positionally.
	struct Batch: Equatable {
		var channels: [String]
		var keys: [String]
	}

	/// A channel to join, and the key it needs (if any).
	nonisolated struct Target: Equatable {
		var name: String
		var key: String?

		init(name: String, key: String? = nil) {
			self.name = name
			self.key = key
		}
	}

	/// Bytes reserved for `"JOIN "` and the space that precedes the key list.
	private static let commandOverhead = "JOIN ".utf8.count + 1

	/// Groups `targets` into batches, preserving their order.
	///
	/// Keyless channels are batched separately from keyed ones because the
	/// two go out as differently shaped commands.
	///
	/// - Parameters:
	///   - targets: The channels to join.
	///   - maximumLineLength: The server's `LINELEN`, or 0 for the RFC default.
	///   - maximumTargets: The server's `TARGMAX`/`MAXTARGETS` for `JOIN`, or 0
	///     when it advertised none. Zero leaves the batch bounded only by the
	///     line budget and `CHANLIMIT`, because a comma-separated channel list
	///     is core `JOIN` syntax that every server takes — unlike a multi-target
	///     `PRIVMSG`, which `ISupport.groupsMultipleTargets(forCommand:)`
	///     withholds until the server has advertised room for it.
	///   - channelLimits: `CHANLIMIT`, keyed by channel prefix. A batch never
	///     carries more channels of one prefix than the server lets the user
	///     be in.
	static func batches(
		for targets: [Target],
		maximumLineLength: Int = 0,
		maximumTargets: UInt = 0,
		channelLimits: [Character: UInt] = [:]
	) -> [Batch] {
		let budget = lineBudget(maximumLineLength: maximumLineLength)
		let targetCap = maximumTargets == 0 ? targets.count : Int(min(maximumTargets, UInt(targets.count)))

		let keyless = targets.filter { ($0.key ?? "").isEmpty }
		let keyed = targets.filter { ($0.key ?? "").isEmpty == false }

		var result = batches(
			for: keyless.map { (name: $0.name, key: "") },
			budget: budget,
			targetCap: targetCap,
			channelLimits: channelLimits
		)
		result.append(contentsOf: batches(
			for: keyed.map { (name: $0.name, key: $0.key ?? "") },
			budget: budget,
			targetCap: targetCap,
			channelLimits: channelLimits
		))
		return result
	}

	private static func lineBudget(maximumLineLength: Int) -> Int {
		// Never let a nonsensical LINELEN shrink the budget to nothing: a
		// batch always has to be able to carry at least one channel.
		max(ProtocolLimits.bodyLimit(forAdvertisedLineLength: maximumLineLength) - commandOverhead, 1)
	}

	private static func batches(
		for entries: [(name: String, key: String)],
		budget: Int,
		targetCap: Int,
		channelLimits: [Character: UInt]
	) -> [Batch] {
		let batches = WireBatching.pack(
			entries,
			maximumCount: targetCap,
			budget: budget,
			closesBatch: { entry, batch in
				guard let prefix = entry.name.first else {
					// A nameless entry has no prefix, so no per-prefix limit applies.
					return false
				}

				/* RFC 2812's ISUPPORT draft gives `#:` — an empty limit — the
				 meaning "no limit for this prefix", and a server writing `#:0`
				 is saying the same thing rather than "no channels at all":
				 nobody advertises a prefix in CHANLIMIT to forbid it. Both
				 parse to zero here, and zero means unlimited. */
				guard let limit = channelLimits[prefix], limit > 0 else {
					return false
				}

				return UInt(batch.count { $0.name.first == prefix }) >= limit
			},
			cost: { entry, batch in
				// One comma in the channel list, plus one in the key list when
				// this batch carries keys.
				let separators = batch.isEmpty ? 0 : (entry.key.isEmpty ? 1 : 2)

				return separators + entry.name.utf8.count + entry.key.utf8.count
			}
		)

		return batches.map { batch in
			Batch(channels: batch.map(\.name), keys: batch.compactMap { $0.key.isEmpty ? nil : $0.key })
		}
	}
}
