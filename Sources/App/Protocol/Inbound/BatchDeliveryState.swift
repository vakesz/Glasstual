// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** What a labelled command's answers have said so far, kept on the batch that
 carries the label.

 Every field is something the wire said: the label, whether the answer was a
 failure, the echoed message's identifier and text, and the failure's reason.
 How the session shows that outcome belongs to the chat layer. */
struct BatchDeliveryState {
	enum Outcome {
		case delivered
		case failed
	}

	/// The label this batch answers, or `nil` when it carries none. It is
	/// cleared once the delivery has been resolved.
	var label: String?
	var outcome = Outcome.delivered
	var messageIdentifier: String?
	var failureReason: String?
	var echoedMessage: Message?
}
