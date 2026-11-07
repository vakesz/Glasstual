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
	/// Where the next label's number comes from.
	var counter: UInt = 0
}

enum LabeledResponsePolicy {
	static let timeout: Duration = .seconds(30)
	static let maximumPendingDeliveries = 512

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

/** What a labelled command's answers have said so far, kept on the batch that
 carries the label.

 A batch is the wire's unit of "these lines belong together"; the label, the
 state and the identifier are this subsystem's reading of it, which is why they
 travel as one value it declares rather than as four fields the batch model
 happens to hold. */
struct BatchDeliveryState {
	/// The label this batch answers, or `nil` when it carries none. It is
	/// cleared once the delivery has been resolved.
	var label: String?
	var state: ChatLineDeliveryState = .delivered
	var messageIdentifier: String?
	var failureReason: String?
	var echoedMessage: Message?
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
