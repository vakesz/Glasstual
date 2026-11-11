// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A point in a conversation's history a `CHATHISTORY` request counts from.
nonisolated enum ChatHistoryReference: Equatable, Sendable {
	/// `msgid=<id>`
	case messageIdentifier(String)
	/// `timestamp=<ISO 8601 with milliseconds>`
	case timestamp(Date)
	/// `*`: no bound, which only `LATEST` accepts.
	case unbounded

	/// Whether `identifier` can go on the wire as a `msgid=` reference: not
	/// empty, not taken for a trailing parameter, and with nothing that would
	/// end the parameter or the line.
	static func isValidMessageIdentifier(_ identifier: String) -> Bool {
		identifier.isEmpty == false && identifier.hasPrefix(":") == false
			&& identifier.utf8.contains(where: { $0 == 0 || $0 == 10 || $0 == 13 || $0 == 32 }) == false
	}

	/// The message identifier when the server takes those, and otherwise the
	/// timestamp when it takes those; `nil` when neither is possible.
	static func preferred(
		messageIdentifier: String?,
		timestamp: Date?,
		support: ChatHistoryReferenceSupport
	) -> ChatHistoryReference? {
		if support.messageIdentifiers, let messageIdentifier, isValidMessageIdentifier(messageIdentifier) {
			return .messageIdentifier(messageIdentifier)
		}
		if support.timestamps, let timestamp {
			return .timestamp(timestamp)
		}
		return nil
	}

	func wireValue(support: ChatHistoryReferenceSupport) throws(ChatHistoryCommandError) -> String {
		switch self {
		case let .messageIdentifier(identifier):
			guard support.messageIdentifiers else { throw .unsupportedReference }
			guard Self.isValidMessageIdentifier(identifier) else { throw .invalidMessageIdentifier }
			return "msgid=\(identifier)"
		case let .timestamp(date):
			guard support.timestamps else { throw .unsupportedReference }
			return "timestamp=\(DateFormatting.iso8601String(from: date))"
		case .unbounded:
			return "*"
		}
	}
}

/// Which reference types the server takes (`MSGREFTYPES`). A server that does
/// not say takes both.
nonisolated struct ChatHistoryReferenceSupport: Equatable, Sendable {
	var timestamps = true
	var messageIdentifiers = true
}

nonisolated enum ChatHistoryCommandError: Error, Equatable {
	case unsupportedReference
	case invalidMessageIdentifier
	case invalidLimit
	case unboundedNotAllowed
	case emptyTarget
}

/** One `CHATHISTORY` request (IRCv3 chathistory).

 Every subcommand counts from and excludes its references; `TARGETS` takes
 timestamps only and lists conversations rather than messages. */
nonisolated enum ChatHistoryCommand: Equatable, Sendable {
	case latest(target: String, after: ChatHistoryReference, limit: UInt)
	case before(target: String, ChatHistoryReference, limit: UInt)
	case after(target: String, ChatHistoryReference, limit: UInt)
	case around(target: String, ChatHistoryReference, limit: UInt)
	case between(target: String, ChatHistoryReference, ChatHistoryReference, limit: UInt)
	case targets(from: Date, to: Date, limit: UInt)

	/// The parameters after `CHATHISTORY`, or why the request cannot be made.
	func arguments(support: ChatHistoryReferenceSupport) throws(ChatHistoryCommandError) -> [String] {
		switch self {
		case let .latest(target, reference, limit):
			return try ["LATEST", Self.checked(target), reference.wireValue(support: support), Self.checked(limit)]
		case let .before(target, reference, limit):
			return try Self.bounded("BEFORE", target, [reference], limit, support)
		case let .after(target, reference, limit):
			return try Self.bounded("AFTER", target, [reference], limit, support)
		case let .around(target, reference, limit):
			return try Self.bounded("AROUND", target, [reference], limit, support)
		case let .between(target, first, second, limit):
			return try Self.bounded("BETWEEN", target, [first, second], limit, support)
		case let .targets(from, to, limit):
			let timestamps = ChatHistoryReferenceSupport(timestamps: true, messageIdentifiers: false)
			return try [
				"TARGETS",
				ChatHistoryReference.timestamp(from).wireValue(support: timestamps),
				ChatHistoryReference.timestamp(to).wireValue(support: timestamps),
				Self.checked(limit),
			]
		}
	}

	/// The conversation the request is about; `nil` for `TARGETS`.
	var target: String? {
		switch self {
		case let .latest(target, _, _), let .before(target, _, _), let .after(target, _, _),
		     let .around(target, _, _), let .between(target, _, _, _):
			target
		case .targets:
			nil
		}
	}

	private static func bounded(
		_ subcommand: String,
		_ target: String,
		_ references: [ChatHistoryReference],
		_ limit: UInt,
		_ support: ChatHistoryReferenceSupport
	) throws(ChatHistoryCommandError) -> [String] {
		var arguments = try [subcommand, checked(target)]
		for reference in references {
			guard reference != .unbounded else { throw .unboundedNotAllowed }
			try arguments.append(reference.wireValue(support: support))
		}
		try arguments.append(checked(limit))
		return arguments
	}

	private static func checked(_ target: String) throws(ChatHistoryCommandError) -> String {
		guard target.isEmpty == false, target.contains(" ") == false, target.hasPrefix(":") == false else {
			throw .emptyTarget
		}
		return target
	}

	private static func checked(_ limit: UInt) throws(ChatHistoryCommandError) -> String {
		guard limit >= 1 else { throw .invalidLimit }
		return String(limit)
	}
}

/// How many lines one request asks for.
nonisolated enum ChatHistoryLimit {
	/// `requested`, lowered to the server's `CHATHISTORY` maximum when it
	/// names one; `0` means it has none. Never below one.
	static func clamp(_ requested: UInt, serverMaximum: UInt) -> UInt {
		let limit = serverMaximum > 0 ? min(requested, serverMaximum) : requested
		return max(limit, 1)
	}
}
