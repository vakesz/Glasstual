// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** How many unsolicited DCC offers — a file, or a chat — one connection takes.

 Every offer that gets through costs the user something: a row in the transfer
 list with its observers, a notification and a Dock bounce, or a chat prompt in
 front of whatever they were doing. One sender offering hundreds of files, or a
 channel's worth of people doing it together, is a flood rather than a request,
 so past these ceilings an offer is dropped where it arrived.

 The counts are timestamps rather than a running total so the window slides,
 and the senders remembered are bounded because the network chooses their
 names. */
nonisolated struct DCCOfferThrottle: Sendable {
	/// How long an offer is remembered for.
	static let window: TimeInterval = 60
	/// Offers one sender gets through inside the window.
	static let perSenderLimit = 3
	/// Offers everyone together gets through inside the window.
	static let overallLimit = 10
	/// Senders remembered at once. Past it the least recently heard from is
	/// forgotten, which at worst forgives one sender one offer.
	static let maximumTrackedSenders = 64

	private var offerTimesBySender: [String: [Date]] = [:]

	/// Whether an offer from `sender` — already casefolded, so that one person
	/// cannot reset the count by changing the case of their nickname — may be
	/// taken now, counting it if so.
	mutating func recordOffer(from sender: String, at now: Date) -> Bool {
		let cutoff = now.addingTimeInterval(-Self.window)
		offerTimesBySender = offerTimesBySender.compactMapValues { times in
			let recent = times.filter { $0 > cutoff }
			return recent.isEmpty ? nil : recent
		}

		let senderCount = offerTimesBySender[sender]?.count ?? 0
		let overallCount = offerTimesBySender.values.reduce(0) { $0 + $1.count }
		guard senderCount < Self.perSenderLimit, overallCount < Self.overallLimit else {
			return false
		}

		offerTimesBySender[sender, default: []].append(now)
		if offerTimesBySender.count > Self.maximumTrackedSenders,
		   let oldest = offerTimesBySender.min(by: { ($0.value.last ?? .distantPast) < ($1.value.last ?? .distantPast) })
		{
			offerTimesBySender.removeValue(forKey: oldest.key)
		}
		return true
	}
}
