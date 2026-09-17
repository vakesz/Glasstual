// Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** Runs the user's message rules against inbound text and commands.

 The client asks the engine whether a line may be printed as the line is
 handled, so everything here runs on the main actor beside the models it
 reads. */
@MainActor
final class MessageRuleEngine {
	private static let logger = Logger(
		subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
		category: "MessageRules"
	)

	/** The most of a message a filter pattern is matched against, in UTF-8 bytes.

	 An IRC line is 512 bytes including its command and prefix, so no chat
	 message body is longer; anything that is has not come from a chat line. */
	static let subjectByteLimit = 512

	private let rulesProvider: () -> [MessageRule]
	private var lastActionDates: [String: TimeInterval] = [:]
	/// Patterns that ran out of their match budget, which stay out of matching
	/// until the rules are edited or reloaded.
	private var exhaustedPatterns: Set<String> = []

	init(rules: @escaping () -> [MessageRule]) {
		rulesProvider = rules
	}

	private var filters: [MessageRule] {
		rulesProvider()
	}

	private func matchesDestination(
		_ filter: MessageRule,
		author: Prefix,
		destination: Channel?,
		client: Client
	) -> Bool {
		let limit = filter.destination
		if limit != .unrestricted || filter.ignoresOperators, destination == nil, !author.isServer {
			return false
		}

		switch limit {
		case .channels:
			return destination?.isChannel == true
		case .privateMessages:
			return destination?.isPrivateMessage == true
		case .specificItems:
			let channelMatches: Bool = if let identifier = destination?.uniqueIdentifier {
				filter.limitedChannelIDs.contains(identifier)
			} else {
				false
			}
			return filter.limitedClientIDs.contains(client.uniqueIdentifier) || channelMatches
		case .unrestricted:
			return true
		}
	}

	private func matchesSender(
		_ filter: MessageRule,
		author: Prefix,
		destination: Channel?,
		client: Client
	) -> Bool {
		if filter.isLimitedToMyself {
			return client.userNickname.caseInsensitiveCompare(author.nickname) == .orderedSame
		}

		if !filter.senderMatch.isEmpty {
			let identity = author.isServer ? author.nickname : author.hostmask
			guard matches(filter.senderMatch, subject: identity) else {
				return false
			}
		}

		guard destination?.isChannel == true, !author.isServer else { return true }
		let sender = destination?.findMember(author.nickname)

		if filter.ageLimit > 0 {
			guard let sender else { return false }

			/* The editor asks for the membership age the filter applies to, so a
			 sender outside that comparison is the one that does not match. */
			let age = Date().timeIntervalSince1970 - sender.creationTime
			let limit = Double(filter.ageLimit)

			switch filter.ageComparator {
			case .lessThan where age >= limit: return false
			case .greaterThan where age <= limit: return false
			default: break
			}
		}

		if filter.ignoresOperators {
			guard let sender else { return false }
			return sender.ranks.isDisjoint(with: Self.operatorRanks)
		}
		return true
	}

	/// Whether the filter's pattern matches the text of an event.
	private func matchesText(_ filter: MessageRule, text: String?, allowingNil: Bool) -> Bool {
		guard var text else { return allowingNil }
		guard !filter.match.isEmpty else { return true }
		if Preferences.Messages.removeAllFormatting.value == false {
			text = TextFormatting.removingControlCodes(from: text)
		}
		return matches(filter.match, subject: text)
	}

	/** Whether a user-authored pattern matches remote text, within a budget.

	 Every rule is tried against every line that arrives, on the main actor,
	 because the client asks synchronously whether to show the line. The
	 patterns are the user's while the subject is whatever a peer sent, and ICU
	 backtracks without a limit of its own, so both halves are bounded here: the
	 subject to a message's length, and the evaluation to
	 `RegularExpression.matchBudget`. A pattern that spends its whole budget
	 once is set aside until the rules change, so a flood of lines built to
	 trigger it costs one budget rather than one per line. */
	private func matches(_ pattern: String, subject: String) -> Bool {
		guard exhaustedPatterns.contains(pattern) == false else { return false }
		switch RegularExpression.firstMatch(
			of: pattern, in: Self.boundedSubject(subject), withoutCase: true
		) {
		case .matched:
			return true
		case .unmatched, .invalidPattern:
			return false
		case .exceededBudget:
			exhaustedPatterns.insert(pattern)
			Self.logger.error("""
			A chat filter pattern ran out of its match budget and is skipped until the filters change: \
			\(pattern, privacy: .private)
			""")
			return false
		}
	}

	/// `text` cut to at most `subjectByteLimit` UTF-8 bytes, on a character
	/// boundary.
	static func boundedSubject(_ text: String) -> String {
		guard text.utf8.count > subjectByteLimit else { return text }
		var bytes = 0
		return String(text.prefix { character in
			bytes += character.utf8.count
			return bytes <= subjectByteLimit
		})
	}

	/** Whether a received command may be printed.

	 The first rule that matches decides. Its action and forwarding run before
	 the verdict, so a rule that hides the line still gets to act on it. */
	func shouldPrintCommand(
		_ command: String,
		text: String?,
		authoredBy author: Prefix,
		destinedFor destination: Channel?,
		onClient client: Client,
		receivedAt: Date,
		messageParameters: [String]
	) -> Bool {
		for filter in filters where filter.isCommandEnabled(command) {
			guard matchesDestination(filter, author: author, destination: destination, client: client),
			      matchesSender(filter, author: author, destination: destination, client: client),
			      matchesText(filter, text: text, allowingNil: true)
			else { continue }

			performAction(
				filter,
				text: text,
				author: author,
				destination: destination,
				client: client,
				messageParameters: messageParameters
			)
			forwardCommand(command, text: text, using: filter, client: client, receivedAt: receivedAt)
			return !filter.ignoresContent
		}
		return true
	}

	/// Whether a received chat line may be printed, decided the same way
	/// ``shouldPrintCommand(_:text:authoredBy:destinedFor:onClient:receivedAt:messageParameters:)`` decides a command.
	func shouldPrintText(
		_ text: String,
		authoredBy author: Prefix,
		destinedFor destination: Channel?,
		as lineType: LogLineType,
		onClient client: Client,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		for filter in filters where accepts(lineType, filter: filter) {
			guard matchesDestination(filter, author: author, destination: destination, client: client),
			      matchesSender(filter, author: author, destination: destination, client: client),
			      matchesText(filter, text: text, allowingNil: false)
			else { continue }

			performAction(
				filter,
				text: text,
				author: author,
				destination: destination,
				client: client,
				messageParameters: []
			)
			forwardText(
				text,
				author: author,
				lineType: lineType,
				using: filter,
				client: client,
				receivedAt: receivedAt,
				wasEncrypted: wasEncrypted
			)
			return !filter.ignoresContent
		}
		return true
	}

	private func accepts(_ lineType: LogLineType, filter: MessageRule) -> Bool {
		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			filter.isEventEnabled(.plainTextMessage)
		case .action, .actionNoHighlight:
			filter.isEventEnabled(.actionMessage)
		case .notice:
			filter.isEventEnabled(.noticeMessage)
		default:
			true
		}
	}

	private func forwardCommand(
		_ command: String,
		text: String?,
		using filter: MessageRule,
		client: Client,
		receivedAt: Date
	) {
		guard !filter.forwardDestination.isEmpty, let text, !text.isEmpty else { return }
		guard let destination = client.findChannelOrCreate(filter.forwardDestination, isPrivateMessage: true)
		else { return }
		let message = String(localized: .Rules.forwardedMessage(command, text))
		client.print(
			message,
			by: nil,
			in: destination,
			as: .debug,
			command: "",
			receivedAt: receivedAt,
			isEncrypted: false
		) { _ in
			client.setUnreadState(for: destination)
		}
	}

	private func forwardText(
		_ text: String,
		author: Prefix,
		lineType: LogLineType,
		using filter: MessageRule,
		client: Client,
		receivedAt: Date,
		wasEncrypted: Bool
	) {
		guard !filter.forwardDestination.isEmpty else { return }
		guard let destination = client.findChannelOrCreate(filter.forwardDestination, isPrivateMessage: true)
		else { return }
		let command = lineType == .notice ? "NOTICE" : "PRIVMSG"
		client.print(
			text,
			by: author.nickname,
			in: destination,
			as: lineType,
			command: command,
			receivedAt: receivedAt,
			isEncrypted: wasEncrypted
		) { context in
			if lineType == .notice {
				client.setUnreadState(for: destination)
			} else {
				if context.isHighlight {
					client.setHighlightState(for: destination)
				}
				client.setUnreadState(for: destination, isHighlight: context.isHighlight)
			}
		}
	}

	private func performAction(
		_ filter: MessageRule,
		text: String?,
		author: Prefix,
		destination: Channel?,
		client: Client,
		messageParameters: [String]
	) {
		guard isSafeToPerformAction(filter), !filter.action.isEmpty else { return }
		var replacements: [String: String] = [
			"%_channelName_%": destination?.name ?? "",
			"%_localNickname_%": client.userNickname,
			"%_networkName_%": client.networkName ?? "",
			"%_originalMessage_%": text ?? "",
			"%_senderNickname_%": author.nickname,
			"%_senderUsername_%": author.username ?? "",
			"%_senderAddress_%": author.address ?? "",
			"%_senderHostmask_%": author.hostmask,
			"%_serverAddress_%": client.serverAddress ?? "",
		]
		for index in 0 ... 9 {
			replacements["%_Parameter_\(index)_%"] =
				messageParameters.indices.contains(index) ? messageParameters[index] : ""
		}

		for line in Self.actionCommands(in: filter.action, replacing: replacements) {
			client.sendCommand(line)
		}

		guard filter.logsMatch else { return }
		guard let report = client.findChannelOrCreate(Self.actionLogChannelName, isUtility: true) else {
			return
		}
		let message = if let destination {
			String(
				localized: .Rules.actionLogUserInChannel(
					filter.title,
					author.nickname,
					destination.name
				)
			)
		} else {
			String(
				localized: .Rules.actionLogUser(
					filter.title,
					author.nickname
				)
			)
		}
		client.print(message, by: nil, in: report, as: .privateMessage, command: "PRIVMSG")
		client.setUnreadState(for: report)
	}

	/** The commands a filter action runs, with every token expanded.

	 The order the steps run in is the whole security property of this
	 function, and it used to be the other way around:

	 - The *template* is split into lines first. A line separator that arrives
	   inside a substituted value can then never start a command, because the
	   command boundaries were fixed before any remote text was in the string.
	 - Whether a line is a command is decided on the template line too. Deciding
	   it after expansion let a line that is only a token — `%_originalMessage_%`,
	   `%_Parameter_1_%`, or `%_networkName_%`, which the server names — run
	   whatever command a peer or server put in that value.
	 - Every substituted value has its own line and paragraph separators
	   stripped. `\u{2028}`, `\u{2029}`, `\u{0085}`, `\u{000B}` and `\u{000C}`
	   are all legal in an IRC message body and all count as line breaks to
	   `components(separatedBy: .newlines)`, so a peer used to be able to end
	   the line the template put its text on and write `/quit` — or any other
	   command, user scripts included — on the next one.
	 - Substitution is a single left-to-right pass. Replacing token by token
	   rescanned what earlier tokens had already inserted, so a message body
	   containing the literal text `%_senderHostmask_%` was expanded by a later
	   iteration; iterating a dictionary, the order that happened in was not
	   even fixed. A value this pass writes is never looked at again. */
	static func actionCommands(in template: String, replacing replacements: [String: String]) -> [String] {
		let sanitized = replacements.mapValues(removingLineBreaks)
		let tokens = sanitized.keys.sorted { $0.count > $1.count }

		return templateLines(of: template).compactMap { line -> String? in
			guard line.hasPrefix("/"), !line.hasPrefix("//") else { return nil }
			let command = expanding(String(line.dropFirst()), tokens: tokens, values: sanitized)
			guard command.isEmpty == false, !command.hasPrefix("/") else { return nil }
			return command
		}
	}

	/// The user-authored template split into lines. `\n` and `\r\n` are what a
	/// text editor writes and the only separators a person can mean here; every
	/// other separator is something that arrived from the network.
	private static func templateLines(of template: String) -> [String] {
		template.components(separatedBy: "\n").map { line in
			line.hasSuffix("\r") ? String(line.dropLast()) : line
		}
	}

	private static func expanding(_ line: String, tokens: [String], values: [String: String]) -> String {
		guard line.contains("%_") else { return line }

		var result = ""
		var index = line.startIndex
		while index < line.endIndex {
			let remainder = line[index...]
			if let token = tokens.first(where: { remainder.hasPrefix($0) }) {
				result += values[token] ?? ""
				index = line.index(index, offsetBy: token.count)
			} else {
				result.append(line[index])
				index = line.index(after: index)
			}
		}
		return result
	}

	private static func removingLineBreaks(_ value: String) -> String {
		String(String.UnicodeScalarView(value.unicodeScalars.filter { scalar in
			!CharacterSet.newlines.contains(scalar)
		}))
	}

	/// The utility conversation a rule with "log this match" writes into. It is
	/// a channel name the user sees, so it stays as it was.
	private static let actionLogChannelName = "Filter Actions"

	/// What "ignores operators" refuses to match: half operator and up.
	private static let operatorRanks: UserRank = [
		.halfOperator, .normalOperator, .superOperator, .channelOwner,
	]

	private func isSafeToPerformAction(_ filter: MessageRule) -> Bool {
		let interval = TimeInterval(filter.actionFloodControlInterval)
		guard interval > 0 else { return true }
		let now = Date.timeIntervalSinceReferenceDate
		if let lastAction = lastActionDates[filter.id], now - lastAction <= interval {
			return false
		}
		lastActionDates[filter.id] = now
		return true
	}

	/// Forgets the per-rule flood-control stamps and the exhausted patterns.
	/// Called when the rules change, because both are keyed by what they held.
	func rulesDidChange() {
		exhaustedPatterns.removeAll()
		let validIdentifiers = Set(filters.lazy.filter { $0.actionFloodControlInterval > 0 }.map(\.id))
		lastActionDates = lastActionDates.filter { validIdentifiers.contains($0.key) }
	}
}
