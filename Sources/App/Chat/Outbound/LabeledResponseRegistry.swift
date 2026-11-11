// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** The messages whose labelled answer has not arrived yet.

 IRCv3 `labeled-response` correlates a reply with the line that caused it, so
 the session hands out labels and keeps what each one is waiting for until the
 answer lands or its deadline passes. */
struct LabeledResponseRegistry {
	/// What each outstanding label is waiting for.
	var pending: [String: LabeledDelivery] = [:]
	/// Waits for the earliest deadline in ``pending``; `nil` while nothing is.
	var deadlineTask: Task<Void, Never>?
	/// The deadline ``deadlineTask`` sleeps until.
	var deadlineTaskFireDate: ContinuousClock.Instant?
	/// Deliveries that timed out, newest last, kept so that a late echo
	/// settles its failed line instead of printing a second one.
	var timedOut = TimedOutDeliveries()
	/// Where the next label's number comes from.
	var counter: UInt = 0
}

/** Labels whose delivery timed out, most recent last.

 Flood control can hold a line past its deadline, and a lagged server can
 answer after it, so the echo of a line already drawn as failed can still
 arrive. Only that echo may claim an entry: the server's, from this session,
 to the conversation the line was printed in. */
struct TimedOutDeliveries {
	static let capacity = 64

	struct Entry {
		let label: String
		/// The casefolded name of the conversation the line was printed in.
		let target: String
		let delivery: LabeledDelivery
	}

	private var entries: [Entry] = []

	var count: Int {
		entries.count
	}

	mutating func insert(_ entry: Entry) {
		entries.removeAll { $0.label == entry.label }
		if entries.count >= Self.capacity {
			entries.removeFirst(entries.count - Self.capacity + 1)
		}
		entries.append(entry)
	}

	/// Removes and returns the entry for `label` when it was sent to `target`.
	mutating func take(label: String, target: String) -> Entry? {
		guard let index = entries.firstIndex(where: { $0.label == label && $0.target == target }) else {
			return nil
		}
		return entries.remove(at: index)
	}

	mutating func removeAll() {
		entries.removeAll()
	}
}

enum LabeledResponsePolicy {
	/// How long the server has to answer a line once it is on the wire.
	static let timeout: Duration = .seconds(30)
	/// How long a line may wait in the connection's flood queue before it fails
	/// without ever having been written.
	static let queuedTimeout: Duration = .seconds(300)
	static let maximumPendingDeliveries = 512

	/** The `label` tag of an outgoing line, or `nil` when it has none.

	 Only the tag section is read: a label is a client tag value of the form
	 this session hands out, which needs no unescaping. */
	static func label(inOutgoingLine line: String) -> String? {
		guard line.hasPrefix("@") else { return nil }
		let tags = line.dropFirst().prefix { $0 != " " }
		for tag in tags.split(separator: ";") where tag.hasPrefix("label=") {
			let value = tag.dropFirst("label=".count)
			return value.isEmpty ? nil : String(value)
		}
		return nil
	}

	/// Both standard FAIL replies and legacy error numerics reject a delivery.
	static func responseKind(command: RemoteCommand?, numeric: UInt = 0) -> ResponseKind {
		if ServerNumeric.isErrorReply(numeric) {
			return .failure
		}
		if numeric > 0 {
			return .acknowledgement
		}
		return switch command {
		case .fail: .failure
		case .ack: .acknowledgement
		case .privmsg, .notice, .tagmsg: .echo
		default: .unrelated
		}
	}

	enum ResponseKind {
		case failure
		case acknowledgement
		case echo
		case unrelated
	}
}

extension ChatLineDeliveryState {
	/// How a labelled batch's answers read once the chat layer shows them.
	init(_ outcome: BatchDeliveryState.Outcome) {
		self = switch outcome {
		case .delivered: .delivered
		case .failed: .failed
		}
	}
}

final class LabeledDelivery {
	var label = ""
	weak var conversation: Conversation?
	var lineNumber: String?
	var printedLine: ChatLine?
	var resolved = false
	var state: ChatLineDeliveryState = .none
	/// When the delivery fails if nothing has answered its label.
	var deadline: ContinuousClock.Instant = .now
}
