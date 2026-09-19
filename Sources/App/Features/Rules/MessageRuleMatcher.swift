// Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

/** Runs the user's message rules against inbound text and commands.

 The session asks the engine whether a line may be printed as the line is
 handled, so everything here runs on the main actor beside the models it
 reads. */
@MainActor
final class MessageRuleMatcher {
	private static let logger = Logger(
		subsystem: LogSubsystem.current,
		category: "MessageRuleMatcher"
	)

	/** The most of a message a rule pattern is matched against, in UTF-8 bytes.

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

	private var rules: [MessageRule] {
		rulesProvider()
	}

	private func matchesDestination(
		_ rule: MessageRule,
		author: Prefix,
		destination: Conversation?,
		session: ServerSession
	) -> Bool {
		let limit = rule.destination
		if limit != .unrestricted || rule.ignoresOperators, destination == nil, !author.isServer {
			return false
		}

		switch limit {
		case .channels:
			return destination?.isChannel == true
		case .privateMessages:
			return destination?.isDirect == true
		case .specificItems:
			let channelMatches: Bool = if let identifier = destination?.uniqueIdentifier {
				rule.limitedChannelIDs.contains(identifier)
			} else {
				false
			}
			return rule.limitedSessionIDs.contains(session.uniqueIdentifier) || channelMatches
		case .unrestricted:
			return true
		}
	}

	private func matchesSender(
		_ rule: MessageRule,
		author: Prefix,
		destination: Conversation?,
		session: ServerSession
	) -> Bool {
		if rule.isLimitedToMyself {
			return session.userNickname.caseInsensitiveCompare(author.nickname) == .orderedSame
		}

		if !rule.senderMatch.isEmpty {
			let identity = author.isServer ? author.nickname : author.hostmask
			guard matches(rule.senderMatch, subject: identity) else {
				return false
			}
		}

		guard destination?.isChannel == true, !author.isServer else { return true }
		let sender = destination?.findMember(author.nickname)

		if rule.ageLimit > 0 {
			guard let sender else { return false }

			/* The editor asks for the membership age the rule applies to, so a
			 sender outside that comparison is the one that does not match. */
			let age = Date().timeIntervalSince1970 - sender.creationTime
			let limit = Double(rule.ageLimit)

			switch rule.ageComparator {
			case .lessThan where age >= limit: return false
			case .greaterThan where age <= limit: return false
			default: break
			}
		}

		if rule.ignoresOperators {
			guard let sender else { return false }
			return sender.ranks.isDisjoint(with: Self.operatorRanks)
		}
		return true
	}

	/// Whether the rule's pattern matches the text of an event.
	private func matchesText(_ rule: MessageRule, text: String?, allowingNil: Bool) -> Bool {
		guard var text else { return allowingNil }
		guard !rule.match.isEmpty else { return true }
		if SettingsKeys.Messages.removeAllFormatting.value == false {
			text = TextFormatting.removingControlCodes(from: text)
		}
		return matches(rule.match, subject: text)
	}

	/** Whether a user-authored pattern matches remote text, within a budget.

	 Every rule is tried against every line that arrives, on the main actor,
	 because the session asks synchronously whether to show the line. The
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
			A chat rule pattern ran out of its match budget and is skipped until the rules change: \
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
		destinedFor destination: Conversation?,
		onSession session: ServerSession,
		receivedAt: Date,
		messageParameters: [String]
	) -> Bool {
		for rule in rules where rule.isCommandEnabled(command) {
			guard matchesDestination(rule, author: author, destination: destination, session: session),
			      matchesSender(rule, author: author, destination: destination, session: session),
			      matchesText(rule, text: text, allowingNil: true)
			else { continue }

			performAction(
				rule,
				text: text,
				author: author,
				destination: destination,
				session: session,
				messageParameters: messageParameters
			)
			forwardCommand(command, text: text, using: rule, session: session, receivedAt: receivedAt)
			return !rule.ignoresContent
		}
		return true
	}

	/// Whether a received chat line may be printed, decided the same way
	/// ``shouldPrintCommand(_:text:authoredBy:destinedFor:onSession:receivedAt:messageParameters:)`` decides a command.
	func shouldPrintText(
		_ text: String,
		authoredBy author: Prefix,
		destinedFor destination: Conversation?,
		as lineType: ChatLineKind,
		onSession session: ServerSession,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		for rule in rules where accepts(lineType, rule: rule) {
			guard matchesDestination(rule, author: author, destination: destination, session: session),
			      matchesSender(rule, author: author, destination: destination, session: session),
			      matchesText(rule, text: text, allowingNil: false)
			else { continue }

			performAction(
				rule,
				text: text,
				author: author,
				destination: destination,
				session: session,
				messageParameters: []
			)
			forwardText(
				text,
				author: author,
				lineType: lineType,
				using: rule,
				session: session,
				receivedAt: receivedAt,
				wasEncrypted: wasEncrypted
			)
			return !rule.ignoresContent
		}
		return true
	}

	private func accepts(_ lineType: ChatLineKind, rule: MessageRule) -> Bool {
		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			rule.isEventEnabled(.plainTextMessage)
		case .action, .actionNoHighlight:
			rule.isEventEnabled(.actionMessage)
		case .notice:
			rule.isEventEnabled(.noticeMessage)
		default:
			true
		}
	}

	private func forwardCommand(
		_ command: String,
		text: String?,
		using rule: MessageRule,
		session: ServerSession,
		receivedAt: Date
	) {
		guard !rule.forwardDestination.isEmpty, let text, !text.isEmpty else { return }
		guard let destination = session.findConversationOrCreate(rule.forwardDestination, isDirect: true)
		else { return }
		let message = String(localized: .Rules.forwardedMessage(command, text))
		session.print(
			message,
			by: nil,
			in: destination,
			as: .debug,
			command: "",
			receivedAt: receivedAt,
			isEncrypted: false
		) { _ in
			session.setUnreadState(for: destination)
		}
	}

	private func forwardText(
		_ text: String,
		author: Prefix,
		lineType: ChatLineKind,
		using rule: MessageRule,
		session: ServerSession,
		receivedAt: Date,
		wasEncrypted: Bool
	) {
		guard !rule.forwardDestination.isEmpty else { return }
		guard let destination = session.findConversationOrCreate(rule.forwardDestination, isDirect: true)
		else { return }
		let command = lineType == .notice ? "NOTICE" : "PRIVMSG"
		session.print(
			text,
			by: author.nickname,
			in: destination,
			as: lineType,
			command: command,
			receivedAt: receivedAt,
			isEncrypted: wasEncrypted
		) { context in
			if lineType == .notice {
				session.setUnreadState(for: destination)
			} else {
				if context.isHighlight {
					session.setHighlightState(for: destination)
				}
				session.setUnreadState(for: destination, isHighlight: context.isHighlight)
			}
		}
	}

	private func performAction(
		_ rule: MessageRule,
		text: String?,
		author: Prefix,
		destination: Conversation?,
		session: ServerSession,
		messageParameters: [String]
	) {
		guard isSafeToPerformAction(rule), !rule.action.isEmpty else { return }
		var replacements: [String: String] = [
			"%_channelName_%": destination?.name ?? "",
			"%_localNickname_%": session.userNickname,
			"%_networkName_%": session.networkName ?? "",
			"%_originalMessage_%": text ?? "",
			"%_senderNickname_%": author.nickname,
			"%_senderUsername_%": author.username ?? "",
			"%_senderAddress_%": author.address ?? "",
			"%_senderHostmask_%": author.hostmask,
			"%_serverAddress_%": session.serverAddress ?? "",
		]
		for index in 0 ... 9 {
			replacements["%_Parameter_\(index)_%"] =
				messageParameters.indices.contains(index) ? messageParameters[index] : ""
		}

		for line in Self.actionCommands(in: rule.action, replacing: replacements) {
			session.sendCommand(line)
		}

		guard rule.logsMatch else { return }
		guard let report = session.findConversationOrCreate(Self.actionLogConsoleName, isConsole: true) else {
			return
		}
		let message = if let destination {
			String(
				localized: .Rules.actionLogUserInChannel(
					rule.title,
					author.nickname,
					destination.name
				)
			)
		} else {
			String(
				localized: .Rules.actionLogUser(
					rule.title,
					author.nickname
				)
			)
		}
		session.print(message, by: nil, in: report, as: .privateMessage, command: "PRIVMSG")
		session.setUnreadState(for: report)
	}

	/** The commands a rule action runs, with every token expanded.

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

	/// The console conversation a rule with "log this match" writes into. The
	/// name is shown in the sidebar, so it stays as it was.
	private static let actionLogConsoleName = "Filter Actions"

	/// What "ignores operators" refuses to match: half operator and up.
	private static let operatorRanks: UserRank = [
		.halfOperator, .normalOperator, .superOperator, .channelOwner,
	]

	private func isSafeToPerformAction(_ rule: MessageRule) -> Bool {
		let interval = TimeInterval(rule.actionFloodControlInterval)
		guard interval > 0 else { return true }
		let now = Date.timeIntervalSinceReferenceDate
		if let lastAction = lastActionDates[rule.id], now - lastAction <= interval {
			return false
		}
		lastActionDates[rule.id] = now
		return true
	}

	/// Forgets the per-rule flood-control stamps and the exhausted patterns.
	/// Called when the rules change, because both are keyed by what they held.
	func rulesDidChange() {
		exhaustedPatterns.removeAll()
		let validIdentifiers = Set(rules.lazy.filter { $0.actionFloodControlInterval > 0 }.map(\.id))
		lastActionDates = lastActionDates.filter { validIdentifiers.contains($0.key) }
	}
}

/// The inbound path's view of the rules: the engine already answers exactly the
/// two questions the inbound layer declares, so nothing under `Chat/` or
/// `Protocol/` names a rules type.
extension MessageRuleMatcher: MessageRuleFiltering {}
