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

/// Splits a set of channels into `JOIN` commands that each fit inside one
/// protocol line.
///
/// A `JOIN` carrying every autojoin channel on a single line is silently
/// truncated by the server, so the user quietly misses channels. The batching
/// is a pure function of the channel list and the server's advertised limits
/// so that it can be tested without a connection.
enum IRCJoinBatching {
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
	struct Target: Equatable {
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
	///     `PRIVMSG`, which `IRCISupportInfo.groupsMultipleTargets(forCommand:)`
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
		let targetCap = maximumTargets == 0 ? Int.max : Int(maximumTargets)

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
		let advertised = maximumLineLength > 0 ? maximumLineLength : IRCProtocolLimits.maximumBodyLength
		// Never let a nonsensical LINELEN shrink the budget to nothing: a
		// batch always has to be able to carry at least one channel.
		return max(advertised - commandOverhead, 1)
	}

	private static func batches(
		for entries: [(name: String, key: String)],
		budget: Int,
		targetCap: Int,
		channelLimits: [Character: UInt]
	) -> [Batch] {
		var result: [Batch] = []
		var current = Batch(channels: [], keys: [])
		var currentLength = 0
		var countByPrefix: [Character: Int] = [:]

		func flush() {
			guard current.channels.isEmpty == false else { return }
			result.append(current)
			current = Batch(channels: [], keys: [])
			currentLength = 0
			countByPrefix = [:]
		}

		for entry in entries {
			// A nameless entry has no prefix, so no per-prefix limit applies.
			let prefix = entry.name.first
			let prefixLimit = prefix.flatMap { channelLimits[$0] }.map { Int($0) } ?? Int.max
			let prefixCount = prefix.map { countByPrefix[$0, default: 0] } ?? 0
			// One comma in the channel list, plus one in the key list when
			// this batch carries keys.
			let separators = entry.key.isEmpty ? 1 : 2
			let entryLength = entry.name.utf8.count + entry.key.utf8.count

			if current.channels.isEmpty == false,
			   currentLength + separators + entryLength > budget
			   || current.channels.count >= targetCap
			   || prefixCount >= prefixLimit
			{
				flush()
			}

			if current.channels.isEmpty == false {
				currentLength += separators
			}
			currentLength += entryLength
			current.channels.append(entry.name)
			if entry.key.isEmpty == false {
				current.keys.append(entry.key)
			}
			if let prefix {
				countByPrefix[prefix, default: 0] += 1
			}
		}
		flush()

		return result
	}
}
