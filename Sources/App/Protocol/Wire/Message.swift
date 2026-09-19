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

/** A `time` (or bouncer `t`) tag read as a date, or `nil` when it carries no
 timestamp the session can act on.

 Two spellings reach this: the specification's `YYYY-MM-DDThh:mm:ss.sssZ`, which
 common servers may also send to whole seconds, and the bare Unix seconds a
 bouncer sends. Either way a replayed line is filed when it was said rather than
 when it arrived. */
private nonisolated func serverTimeDate(from value: String) -> Date? { // nonisolated: pure
	let digitsAndPoint = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: "."))

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
	var sender = Prefix()
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

	var senderUsername: String? {
		sender.username
	}

	var senderAddress: String? {
		sender.address
	}

	var senderHostmask: String? {
		sender.hostmask
	}

	var senderIsServer: Bool {
		sender.isServer
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
				?? Prefix(nickname: senderSection, hostmask: senderSection, isServer: true)
		} else {
			sender = Prefix(
				nickname: context.serverAddress,
				hostmask: context.serverAddress,
				isServer: true
			)
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

nonisolated struct ParsedLine: Sendable {
	let messageTagSection: String?
	let senderSection: String?
	let command: String
	let commandNumeric: UInt
	let parameters: [String]

	init(messageTagSection: String?, senderSection: String?, command: String, parameters: [String]) {
		self.messageTagSection = messageTagSection
		self.senderSection = senderSection
		self.command = command
		commandNumeric = Self.numericValue(of: command)
		self.parameters = parameters
	}

	/// IRC numerics are exactly three ASCII digits. `CharacterSet.decimalDigits`
	/// also matches non-ASCII digits, which `integerValue` then reads as 0,
	/// and an oversized run of digits saturates rather than being rejected.
	static func numericValue(of command: String) -> UInt {
		guard command.count == 3, isASCIIDigits(command), let numeric = UInt(command) else {
			return 0
		}

		return numeric
	}

	static func isASCIIDigits(_ string: String) -> Bool {
		string.isEmpty == false && string.utf8.allSatisfy { $0 >= 48 && $0 <= 57 }
	}
}

nonisolated enum LineParser {
	/// RFC 1459/2812 and IRCv3 separate tokens on SPACE (0x20) only, never on
	/// the wider Unicode whitespace set.
	private static let space: Unicode.Scalar = " "

	/// Splits a wire string into tokens on SPACE (0x20), dropping empty runs.
	static func wireTokens(in string: String) -> [String] {
		string.unicodeScalars.split(separator: space).map(String.init)
	}

	static func parsedLine(fromLine line: String) -> ParsedLine? {
		var remainder = line.unicodeScalars[...]
		var messageTagSection: String?
		var senderSection: String?

		if remainder.first == "@" {
			let token = nextToken(from: &remainder)

			guard token.count > 1 else {
				return nil
			}

			messageTagSection = String(token.dropFirst())
		}

		if remainder.first == ":" {
			let token = nextToken(from: &remainder)

			guard token.count > 1 else {
				return nil
			}

			senderSection = String(token.dropFirst())
		}

		let commandToken = nextToken(from: &remainder)

		guard commandToken.isEmpty == false else {
			return nil
		}

		let command = ParsedLine.isASCIIDigits(commandToken) ? commandToken : commandToken.uppercased()
		var parameters: [String] = []

		while remainder.isEmpty == false {
			if remainder.first == ":" {
				parameters.append(String(remainder.dropFirst()))
				break
			}

			/* The last slot takes everything that is left, verbatim: a line of
			 single-character parameters would otherwise cost one array element
			 per two bytes received, before any handler sees the command. */
			if parameters.count == ProtocolLimits.maximumInboundParameterCount - 1 {
				parameters.append(String(remainder))
				break
			}

			parameters.append(nextToken(from: &remainder))
		}

		return ParsedLine(
			messageTagSection: messageTagSection,
			senderSection: senderSection,
			command: command,
			parameters: parameters
		)
	}

	private static func nextToken(from remainder: inout Substring.UnicodeScalarView) -> String {
		guard let separator = remainder.firstIndex(of: space) else {
			let token = String(remainder)

			remainder = remainder[remainder.endIndex...]

			return token
		}

		let token = String(remainder[..<separator])
		let nextToken = remainder[separator...].firstIndex(where: { $0 != space })

		remainder = nextToken.map { remainder[$0...] } ?? remainder[remainder.endIndex...]

		return token
	}
}

/// The message tags of one line, with the two the session reads by name pulled
/// out of them.
nonisolated struct ParsedMessageTags: Sendable, Equatable {
	let tags: [String: String]
	let messageIdentifier: String?
	let senderAccount: String?

	init(tags: [String: String]) {
		self.tags = tags
		messageIdentifier = tags["msgid"]?.nonEmpty
		senderAccount = tags["account"]?.nonEmpty
	}
}

nonisolated enum MessageTagParser {
	/// IRCv3 message-tags caps the tag section at 8191 bytes, counting the
	/// leading `@` and the space that ends it. Anything longer is a server
	/// that is not playing by the rules, so its tags are dropped rather than
	/// parsed into an unbounded dictionary.
	static let maximumSectionLength = 8191

	/// The `@` and the trailing space: counted by the cap, but already taken
	/// off the section this parser is handed.
	private static let sectionDelimiterLength = 2

	/// - Parameter section: The tags between the `@` and the space.
	static func parsedTags(fromSection section: String) -> ParsedMessageTags {
		guard section.utf8.count + sectionDelimiterLength <= maximumSectionLength else {
			return ParsedMessageTags(tags: [:])
		}

		var tags: [String: String] = [:]

		for component in section.split(separator: ";", omittingEmptySubsequences: true) {
			if let equals = component.firstIndex(of: "=") {
				let name = String(component[..<equals])
				let value = component[component.index(after: equals)...]

				tags[name] = decode(value)
			} else {
				tags[String(component)] = ""
			}
		}

		return ParsedMessageTags(tags: tags)
	}

	private static func decode(_ encoded: Substring) -> String {
		var output: [UInt16] = []
		let input = Array(encoded.utf16)
		var index = 0

		while index < input.count {
			let character = input[index]

			guard character == 0x5C else {
				output.append(character)
				index += 1
				continue
			}

			index += 1

			guard index < input.count else {
				break
			}

			switch input[index] {
			case 0x3A:
				output.append(0x3B)
			case 0x73:
				output.append(0x20)
			case 0x72:
				output.append(0x0D)
			case 0x6E:
				output.append(0x0A)
			default:
				output.append(input[index])
			}

			index += 1
		}

		return String(decoding: output, as: UTF16.self)
	}
}
