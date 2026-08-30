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

import CocoaExtensions
import Foundation

public final class ChannelSpotlightSearchResult: NSObject, Identifiable {
	/// The channel this row stands for, captured when the row was made.
	///
	/// A channel can close while the spotlight is open, so the reference is
	/// weak — but the identity must not go with it, or the table would lose
	/// the row it is still drawing.
	public let id: String

	public private(set) weak var channel: IRCChannel?
	public private(set) var distance = 0.0
	/// The server the channel belongs to, likewise captured up front.
	public let clientId: String

	@available(*, unavailable)
	override public init() {
		fatalError("init() is unavailable; use init(channel:)")
	}

	public init(channel: IRCChannel) {
		id = channel.uniqueIdentifier
		clientId = channel.associatedClient?.uniqueIdentifier ?? ""
		self.channel = channel
		super.init()
	}

	public func recalculateDistance(with searchString: String) {
		guard searchString.isEmpty == false, let channel else {
			distance = 0
			return
		}

		distance = Double(
			channel.name.matchScore(
				against: searchString,
				lengthPenaltyWeight: 1.0
			)
		)
	}
}

/// Which search results the spotlight draws, and in what order.
///
/// This was an `NSArrayController` filter predicate (`distance >= 0.5`, plus
/// `clientId LIKE[c]` when channel navigation is per-server) and a sort
/// descriptor on `distance`. It is written out here so it can be read and
/// tested; the table only ever sees the answer.
public nonisolated enum ChannelSpotlightSearchResults { // nonisolated: value
	/// The lowest match score worth showing.
	public static let minimumDistance = 0.5

	/// The rows to draw, best match first.
	///
	/// - Parameter clientID: the only server to show channels from, or `nil`
	///   for every server. An empty string matches only results with no server,
	///   which is what the predicate did when no client was selected.
	public static func displayed<Result>(
		_ results: [Result],
		restrictedToClient clientID: String?,
		distance: (Result) -> Double,
		clientID clientIDOf: (Result) -> String
	) -> [Result] {
		let matches = results.enumerated().filter { _, result in
			guard distance(result) >= minimumDistance else {
				return false
			}

			guard let clientID else {
				return true
			}

			return clientIDOf(result).caseInsensitiveCompare(clientID) == .orderedSame
		}

		/* Ties keep the order they arrived in: the row a result lands on is
		 also its ⌘-number shortcut, so it must not shuffle between redraws. */
		return matches
			.sorted { lhs, rhs in
				let lhsDistance = distance(lhs.element)
				let rhsDistance = distance(rhs.element)

				if lhsDistance == rhsDistance {
					return lhs.offset < rhs.offset
				}

				return lhsDistance > rhsDistance
			}
			.map(\.element)
	}
}
