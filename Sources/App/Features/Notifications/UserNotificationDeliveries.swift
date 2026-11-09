// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// Deliveries waiting for authorization or for Notification Center to add
/// them still belong to a conversation that can be read or muted meanwhile.
struct UserNotificationDeliveries {
	private struct Delivery {
		let payload: UserNotificationPayload
		let task: Task<Void, Never>
	}

	private var pending: [String: Delivery] = [:]

	mutating func insert(_ task: Task<Void, Never>, identifier: String, payload: UserNotificationPayload) {
		pending[identifier] = Delivery(payload: payload, task: task)
	}

	mutating func complete(_ identifier: String) {
		pending[identifier] = nil
	}

	mutating func cancel(for sessionIdentifier: String, conversationIdentifier: String?) {
		let identifiers = pending.compactMap { identifier, delivery in
			delivery.payload.isInScope(of: sessionIdentifier, conversationIdentifier: conversationIdentifier)
				? identifier : nil
		}
		for identifier in identifiers {
			pending.removeValue(forKey: identifier)?.task.cancel()
		}
	}

	mutating func cancelAll() {
		pending.values.forEach { $0.task.cancel() }
		pending.removeAll()
	}
}
