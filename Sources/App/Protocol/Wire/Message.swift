// Copyright (c) 2010 - 2019 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** The largest `@time=` a bouncer's Unix timestamp may carry.

 The tag is read as whole seconds, and 1e11 of them is the year 5138: past that
 the value is not a time at all. It matters because the tag is server-supplied
 text — a forty-digit one parses to a `Double` that no later narrowing can
 survive, and `Int64(_:)` traps on it rather than reporting the overflow. */
private nonisolated let maximumServerTimeInterval: Double = 1e11

/*  A wire parameter carrying whole Unix seconds, read as a date.

 RPL_TOPICWHOTIME, RPL_WHOISIDLE and the mode-list numerics all end in a
 timestamp the server generated, and it is no more trustworthy than the
 `@time=` tag: `TimeInterval(param) ?? 0` read an empty or textual one as 1970,
 and a forty-digit or infinite one as a date past the year 3000. The same
 bound applies here, and `nil` means "the server said nothing usable", which
 lets the caller leave the date out rather than print a wrong one. */

/** How far a bouncer's `server-time` may run behind arrival and still be live.

 A bouncer replays without a batch, so the only thing separating playback from
 a line that took a moment to reach the session is how old the server time is. */
nonisolated let liveServerTimeTolerance: TimeInterval = 30

/// Whether a line is replayed history rather than something happening now.
nonisolated func messageIsReplayed( // nonisolated: pure
	serverTime: Date,
	arrivedAt: Date,
	inReplayBatch: Bool,
	isKnownBouncer: Bool = false
) -> Bool {
	inReplayBatch || (isKnownBouncer && arrivedAt.timeIntervalSince(serverTime) > liveServerTimeTolerance)
}

nonisolated func ircWireTimestampDate(from value: String) -> Date? { // nonisolated: pure
	guard let seconds = Double(value), seconds.isFinite,
	      abs(seconds) <= maximumServerTimeInterval
	else {
		return nil
	}

	return Date(timeIntervalSince1970: seconds)
}

private nonisolated let digitsAndPoint = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))

/** A `time` (or bouncer `t`) tag read as a date, or `nil` when it carries no
 timestamp the session can act on.

 Two spellings reach this: the specification's `YYYY-MM-DDThh:mm:ss.sssZ`, which
 common servers may also send to whole seconds, and the bare Unix seconds a
 bouncer sends. Either way a replayed line is filed when it was said rather than
 when it arrived. */
private nonisolated func serverTimeDate(from value: String) -> Date? { // nonisolated: pure
	if value.unicodeScalars.allSatisfy(digitsAndPoint.contains) {
		return ircWireTimestampDate(from: value)
	}

	return DateFormatting.date(fromISO8601: value)
}

/** What the wire parser needs to know about the session a line arrived on.

 Reading a line asks the connection exactly five questions, and none of them
 changes while the line is being read, so they travel as one value: the parser
 is then a function of the line and the connection's advertised state, with no
 session to reach into. */
nonisolated struct MessageParsingContext: Sendable {
	/// Whom a line with no prefix is attributed to.
	var serverAddress = ""
	/// The longest nickname to read out of a sender prefix.
	var maximumNicknameLength = defaultHostmaskNicknameLength
	/// IRCv3 `batch` is negotiated, so a `batch` tag names a batch.
	var batchEnabled = false
	/// IRCv3 `server-time` is negotiated, so a `time` tag dates the line.
	var serverTimeEnabled = false
	/// The peer is a bouncer, which replays without opening a batch.
	var isKnownBouncer = false

	/// A line read outside any session: the grammar and nothing else.
	static let none = MessageParsingContext()
}

/** One line received from the server, parsed.

 A plain value: handlers take one and treat it as read-only because a copy is
 all they have, and the two places that rewrite a line assign to a `var` of
 their own. The one reference it keeps is `parentBatchMessage`, the batch that
 holds it — that has identity, so it stays a class. */
nonisolated struct Message {
	var sender = Prefix.unnamed
	/// The wire command as the server spelled it, upper-cased by the parser for
	/// everything that is not a numeric.
	private(set) var command = ""

	/// The command as this session's vocabulary names it, `nil` for a numeric or
	/// a verb the catalogue has no case for. Resolved where `command` is
	/// written, so a handler matches a case rather than a string literal.
	private(set) var remoteCommand: RemoteCommand?
	var commandNumeric: UInt = 0
	var params: [String] = []
	var receivedAt = Date()
	var isReplayed = false
	/// `true` when a negotiated `server-time` (or bouncer `t`) tag supplied
	/// `receivedAt`. The resume point a bouncer replays from is the newest
	/// such stamp, whether or not the line turned out to be replay.
	var hasServerTime = false
	var isPrintOnlyMessage = false
	var batchToken: String?
	var messageTags: [String: String]? = [:]
	var messageIdentifier: String?
	var senderAccount: String?
	var parentBatchMessage: MessageBatch?

	var senderNickname: String? {
		sender.nickname
	}

	var senderHostmask: String? {
		sender.hostmask
	}

	var sequence: String {
		if params.count < 2 {
			return sequence(0)
		}

		return sequence(1)
	}

	init?(line: String, context: MessageParsingContext = .none) {
		guard let parsed = LineParser.parsedLine(fromLine: line) else {
			return nil
		}

		if let tagSection = parsed.messageTagSection {
			readExtensions(tagSection, context: context)
		}

		if let senderSection = parsed.senderSection {
			sender = Prefix.user(parsing: senderSection, maximumNicknameLength: context.maximumNicknameLength)
				?? .server(name: senderSection)
		} else {
			sender = .server(name: context.serverAddress)
		}

		setCommand(parsed.command)
		commandNumeric = parsed.commandNumeric
		params = parsed.parameters
	}

	/// Rewrites what the line says it is. Both spellings move together, so a
	/// handler matching on ``remoteCommand`` sees the rewrite.
	mutating func rewrite(as command: RemoteCommand) {
		self.command = command.wireName
		remoteCommand = command
	}

	private mutating func setCommand(_ wireName: String) {
		command = wireName
		remoteCommand = RemoteCommand(wireName: wireName)
	}

	func param(at index: UInt) -> String {
		let index = Int(index)

		if index < params.count {
			return params[index]
		}

		return ""
	}

	func sequence(_ index: UInt) -> String {
		let start = Int(index)
		guard start < params.count else {
			return ""
		}

		return params[start...].joined(separator: " ")
	}

	/** The message tags, and the two things they say about the line itself.

	 Which batch the named token belongs to is the session's answer, not the
	 line's, so it is resolved by the caller: `isReplayed` is what the timestamp
	 alone makes it, and a replay batch adds to it there. */
	private mutating func readExtensions(_ extensionInfo: String, context: MessageParsingContext) {
		let parsedTags = MessageTagParser.parsedTags(fromSection: extensionInfo)

		messageTags = parsedTags.tags
		messageIdentifier = parsedTags.messageIdentifier
		senderAccount = parsedTags.senderAccount

		if context.batchEnabled,
		   let batchToken = parsedTags.tags["batch"],
		   batchToken.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-" })
		{
			self.batchToken = batchToken
		}

		guard context.serverTimeEnabled,
		      let dateString = parsedTags.tags["time"] ?? parsedTags.tags["t"],
		      let dateObject = serverTimeDate(from: dateString)
		else {
			return
		}

		let arrivedAt = receivedAt
		receivedAt = dateObject
		hasServerTime = true
		isReplayed = messageIsReplayed(
			serverTime: dateObject,
			arrivedAt: arrivedAt,
			inReplayBatch: false,
			isKnownBouncer: context.isKnownBouncer
		)
	}
}
