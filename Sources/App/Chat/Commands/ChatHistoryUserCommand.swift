// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a `/chathistory` line asks for.

 `/chathistory <subcommand> [target] [references] [limit]`. The target is
 optional and defaults to the selected conversation; a reference is
 `msgid=…`, `timestamp=…`, or a bare ISO 8601 date or time. */
enum ChatHistoryUserCommand: Equatable {
	case latest(target: String?, after: ChatHistoryReference, limit: UInt?)
	case before(target: String?, ChatHistoryReference, limit: UInt?)
	case after(target: String?, ChatHistoryReference, limit: UInt?)
	case around(target: String?, ChatHistoryReference, limit: UInt?)
	case between(target: String?, ChatHistoryReference, ChatHistoryReference, limit: UInt?)
	/// `since` is `nil` for "since the last message this connection saw".
	case targets(since: Date?, limit: UInt?)
	case fill(target: String?)

	enum ParseError: Error, Equatable {
		case missingSubcommand
		case unknownSubcommand(String)
		case invalidReference(String)
		case missingReference
		case unexpectedArgument(String)
	}

	/// The subcommands, as the syntax line lists them.
	static let subcommands = ["latest", "before", "after", "around", "between", "targets", "fill"]

	/** Reads the arguments after `/chathistory`.

	 `isTarget` answers whether a token names a conversation the session knows
	 or a channel; anything else in the target position is read as a reference.
	 `now` anchors relative times such as `24h`. */
	init(
		_ arguments: CommandArguments,
		isTarget: (String) -> Bool,
		now: Date = Date()
	) throws(ParseError) {
		var tokens: [String] = []
		var cursor = arguments
		while true {
			let token = cursor.next()
			guard token.isEmpty == false else { break }
			tokens.append(token)
		}
		guard let subcommand = tokens.first?.lowercased() else { throw .missingSubcommand }
		var rest = Array(tokens.dropFirst())

		switch subcommand {
		case "targets":
			self = try Self.targets(rest, now: now)
			return
		case "fill":
			let target = rest.first
			guard rest.count <= 1 else { throw .unexpectedArgument(rest[1]) }
			self = .fill(target: target)
			return
		case "latest", "before", "after", "around", "between":
			break
		default:
			throw .unknownSubcommand(subcommand)
		}

		var target: String?
		if let first = rest.first, Self.reference(first, bareIsMessageIdentifier: false) == nil, isTarget(first) {
			target = first
			rest.removeFirst()
		}
		var limit: UInt?
		if let last = rest.last, let value = UInt(last), value > 0 {
			limit = value
			rest.removeLast()
		}

		let bareIsMessageIdentifier = subcommand == "around"
		var references: [ChatHistoryReference] = []
		for token in rest {
			guard let reference = Self.reference(token, bareIsMessageIdentifier: bareIsMessageIdentifier) else {
				throw .invalidReference(token)
			}
			references.append(reference)
		}

		switch (subcommand, references.count) {
		case ("latest", 0): self = .latest(target: target, after: .unbounded, limit: limit)
		case ("latest", 1): self = .latest(target: target, after: references[0], limit: limit)
		case ("before", 1): self = .before(target: target, references[0], limit: limit)
		case ("after", 1): self = .after(target: target, references[0], limit: limit)
		case ("around", 1): self = .around(target: target, references[0], limit: limit)
		case ("between", 2): self = .between(target: target, references[0], references[1], limit: limit)
		case (_, 0), ("between", 1): throw .missingReference
		default: throw .unexpectedArgument(rest.last ?? "")
		}
	}

	/// `msgid=…`, `timestamp=…`, `*` or a bare date. In `around` a bare token
	/// that is not a date is a message identifier.
	static func reference(_ token: String, bareIsMessageIdentifier: Bool) -> ChatHistoryReference? {
		if token == "*" {
			return .unbounded
		}
		if token.hasPrefix("msgid=") {
			let identifier = String(token.dropFirst("msgid=".count))
			return ChatHistoryReference.isValidMessageIdentifier(identifier) ? .messageIdentifier(identifier) : nil
		}
		if token.hasPrefix("timestamp=") {
			return date(String(token.dropFirst("timestamp=".count))).map(ChatHistoryReference.timestamp)
		}
		if let date = date(token) {
			return .timestamp(date)
		}
		guard bareIsMessageIdentifier, ChatHistoryReference.isValidMessageIdentifier(token), UInt(token) == nil else {
			return nil
		}
		return .messageIdentifier(token)
	}

	/// A full ISO 8601 time, or a calendar date read as UTC midnight.
	static func date(_ text: String) -> Date? {
		if let date = DateFormatting.date(fromISO8601: text) {
			return date
		}
		if let date = try? Date.ISO8601FormatStyle(timeZone: .gmt).parse(text) {
			return date
		}
		return try? Date.ISO8601FormatStyle(timeZone: .gmt).year().month().day().parse(text)
	}

	/// `30m`, `24h` or `7d` before `now`.
	static func relativeDate(_ text: String, now: Date) -> Date? {
		guard let unit = text.last, let amount = UInt(text.dropLast()), amount > 0 else { return nil }
		let seconds: TimeInterval = switch unit {
		case "m": 60
		case "h": 3600
		case "d": 86400
		default: 0
		}
		guard seconds > 0 else { return nil }
		return now.addingTimeInterval(-TimeInterval(amount) * seconds)
	}

	private static func targets(_ tokens: [String], now: Date) throws(ParseError) -> ChatHistoryUserCommand {
		var tokens = tokens
		var limit: UInt?
		if let last = tokens.last, let value = UInt(last), value > 0 {
			limit = value
			tokens.removeLast()
		}
		guard tokens.count <= 1 else { throw .unexpectedArgument(tokens[1]) }
		guard let since = tokens.first else { return .targets(since: nil, limit: limit) }
		guard let date = relativeDate(since, now: now) ?? date(since) else { throw .invalidReference(since) }
		return .targets(since: date, limit: limit)
	}
}

extension ServerSession {
	/// `/chathistory`: reads the subcommand and sends the request it names.
	func dispatchChatHistoryCommand(_ parsed: ParsedUserCommand, targetConversation: Conversation?) {
		guard isLoggedIn else { return }
		guard isCapabilityEnabled(.chatHistory) else {
			printDebugInformation(String(localized: .IRC.thisServerDoesNotSupportChat))
			return
		}

		let command: ChatHistoryUserCommand
		do {
			command = try ChatHistoryUserCommand(parsed.arguments) { [weak self] token in
				guard let self else { return false }
				return stringIsChannelName(token) || findConversation(token) != nil
			}
		} catch {
			printChatHistoryCommandError(error)
			return
		}

		runChatHistoryCommand(command, in: targetConversation)
	}

	private func printChatHistoryCommandError(_ error: ChatHistoryUserCommand.ParseError) {
		switch error {
		case .missingSubcommand, .missingReference:
			printDebugInformation(String(localized: .ChatHistory.chatHistoryCommandSyntax))
		case let .unknownSubcommand(subcommand):
			printDebugInformation(String(localized: .ChatHistory.chatHistoryUnknownSubcommand(subcommand)))
		case let .invalidReference(token), let .unexpectedArgument(token):
			printDebugInformation(String(localized: .ChatHistory.chatHistoryInvalidReference(token)))
		}
	}

	/// The conversation a request is about: the one named, or the selected one.
	func chatHistoryCommandConversation(named name: String?, in selected: Conversation?) -> Conversation? {
		let conversation = name.flatMap(findConversation) ?? (name == nil ? selected : nil)
		guard let conversation, conversation.isConsole == false else {
			printDebugInformation(String(localized: .ChatHistory.chatHistoryNoTarget))
			return nil
		}
		return conversation
	}

	/// The name a request goes to: the one typed, which need not be open, or
	/// the selected conversation's.
	private func chatHistoryCommandTarget(named name: String?, in selected: Conversation?) -> String? {
		if let name {
			return name
		}
		return chatHistoryCommandConversation(named: nil, in: selected)?.name
	}

	func runChatHistoryCommand(_ command: ChatHistoryUserCommand, in selected: Conversation?) {
		let limit: (UInt?) -> UInt = { [unowned self] requested in
			ChatHistoryLimit.clamp(requested ?? ChatHistoryPolicy.defaultRequestLimit, serverMaximum: supportInfo.chatHistoryMaximumLines)
		}
		switch command {
		case let .latest(name, reference, requested):
			guard let target = chatHistoryCommandTarget(named: name, in: selected) else { return }
			sendChatHistoryCommand(.latest(target: target, after: reference, limit: limit(requested)))
		case let .before(name, reference, requested):
			guard let conversation = chatHistoryCommandConversation(named: name, in: selected) else { return }
			/* A page above what is on screen is the transcript's page size,
			 so a typed limit does not apply to it. */
			_ = requested
			requestChatHistoryPage(before: reference, in: conversation)
		case let .after(name, reference, requested):
			guard let target = chatHistoryCommandTarget(named: name, in: selected) else { return }
			sendChatHistoryCommand(.after(target: target, reference, limit: limit(requested)))
		case let .around(name, reference, requested):
			guard let target = chatHistoryCommandTarget(named: name, in: selected) else { return }
			sendChatHistoryCommand(.around(target: target, reference, limit: limit(requested)))
		case let .between(name, first, second, requested):
			guard let target = chatHistoryCommandTarget(named: name, in: selected) else { return }
			sendChatHistoryCommand(.between(target: target, first, second, limit: limit(requested)))
		case let .fill(name):
			guard let conversation = chatHistoryCommandConversation(named: name, in: selected) else { return }
			guard fillChatHistoryGap(in: conversation) else {
				printDebugInformation(
					String(localized: .ChatHistory.chatHistoryNothingMissing(conversation.name)),
					in: conversation
				)
				return
			}
		case .targets:
			printDebugInformation(String(localized: .ChatHistory.chatHistoryUnknownSubcommand(
				command.subcommandName
			)))
		}
	}

	/// Sends a request whose lines arrive as an ordinary replay batch.
	private func sendChatHistoryCommand(_ command: ChatHistoryCommand) {
		do {
			try send(.chathistory, arguments: command.arguments(support: chatHistoryReferenceSupport))
		} catch {
			printDebugInformation(String(localized: .ChatHistory.chatHistoryReferenceUnsupported))
		}
	}

	/// `before` from the command line goes through the scroll-back path, so
	/// its page is drawn above what is on screen.
	private func requestChatHistoryPage(before reference: ChatHistoryReference, in conversation: Conversation) {
		let request: ServerHistoryRequest
		switch reference {
		case let .messageIdentifier(identifier) where chatHistoryReferenceSupport.messageIdentifiers:
			request = ServerHistoryRequest(id: UUID(), before: Date(), oldestLineNumber: nil, messageIdentifier: identifier)
		case let .timestamp(date) where chatHistoryReferenceSupport.timestamps:
			request = ServerHistoryRequest(id: UUID(), before: date, oldestLineNumber: nil)
		default:
			printDebugInformation(String(localized: .ChatHistory.chatHistoryReferenceUnsupported))
			return
		}
		guard requestServerHistory(request, in: conversation) else {
			printDebugInformation(String(localized: .ChatHistory.chatHistoryReferenceUnsupported))
			return
		}
	}
}

extension ChatHistoryUserCommand {
	var subcommandName: String {
		switch self {
		case .latest: "latest"
		case .before: "before"
		case .after: "after"
		case .around: "around"
		case .between: "between"
		case .targets: "targets"
		case .fill: "fill"
		}
	}
}
