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
import os

private let highlightLogEntryLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCHighlightLogEntry"
)

/** An entry in a client's in-memory highlight log.

 A value, owned by the client that logged it (`Client.cachedHighlights`) and
 read by `ServerHighlightList`, which sorts and draws the entries itself
 rather than binding an `NSArrayController` to them by KVC key path.

 Its identity is the line it logged: `lineNumber` names one printed line. */
struct HighlightLogEntry: Codable, Hashable, Sendable {
	var lineLogged: LogLine
	var clientId: String
	var channelId: String

	init(lineLogged: LogLine, clientId: String, channelId: String) {
		self.lineLogged = lineLogged
		self.clientId = clientId
		self.channelId = channelId

		// An incomplete entry used to abort the app from a health check; it is
		// only logged now, and callers that care check `isWellFormed`.
		if isWellFormed == false {
			highlightLogEntryLogger.error("Created an incomplete highlight log entry")
		}
	}

	/// `true` when the entry carries everything its accessors need.
	var isWellFormed: Bool {
		clientId.isEmpty == false && channelId.isEmpty == false
	}

	var timeLogged: Date {
		lineLogged.receivedAt
	}

	var lineNumber: String {
		lineLogged.uniqueIdentifier
	}
}

/** One keyword a connection watches for, optionally scoped to one channel.

 A condition with no keyword can never match. Persisted lists are filtered on
 load rather than rejected, so a hand-edited property list drops the broken
 entry instead of aborting the app. */
nonisolated struct HighlightMatchCondition: Codable, Sendable, Equatable, Hashable { // nonisolated: value
	var uniqueIdentifier: String
	var matchKeyword: String
	var matchChannelId: String?
	var matchIsExcluded: Bool

	init(
		uniqueIdentifier: String = UUID().uuidString,
		matchKeyword: String = "",
		matchChannelId: String? = nil,
		matchIsExcluded: Bool = false
	) {
		self.uniqueIdentifier = uniqueIdentifier
		self.matchKeyword = matchKeyword
		self.matchChannelId = matchChannelId
		self.matchIsExcluded = matchIsExcluded
	}

	private enum CodingKeys: String, CodingKey {
		case uniqueIdentifier
		case matchKeyword
		// Spelled with a capitalised ID on disk since the Objective-C original.
		case matchChannelId = "matchChannelID"
		case matchIsExcluded
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		let identifier = container.decode(String.self, forKey: .uniqueIdentifier, aliases: [], default: "")
		uniqueIdentifier = identifier.isEmpty ? UUID().uuidString : identifier
		matchKeyword = container.decode(String.self, forKey: .matchKeyword, aliases: [], default: "")
		matchChannelId = container.decodeOptional(String.self, forKey: .matchChannelId)
		matchIsExcluded = container.decode(Bool.self, forKey: .matchIsExcluded, aliases: [], default: false)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

		try container.encodeIfPresent(matchChannelId, forKey: .matchChannelId)
		try container.encode(matchKeyword, forKey: .matchKeyword)
		try container.encode(uniqueIdentifier, forKey: .uniqueIdentifier)
		try container.encode(matchIsExcluded, forKey: .matchIsExcluded)
	}

	/// `true` when the condition carries everything a match needs.
	var isWellFormed: Bool {
		matchKeyword.isEmpty == false
	}

	/// A copy under a fresh identity.
	func uniqueCopy() -> HighlightMatchCondition {
		var copy = self
		copy.uniqueIdentifier = UUID().uuidString

		return copy
	}
}
