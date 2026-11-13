// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

extension ServerSession {
	/// Whether the server accepts `REDACT`: it is negotiated and the session is
	/// registered.
	var supportsMessageRedaction: Bool {
		isLoggedIn && isCapabilityEnabled(.messageRedaction)
	}

	/** Asks the server to delete a message in `conversation`.

	 Nothing changes locally until the server relays the `REDACT` back, or answers
	 with a `FAIL`. Returns whether a request went out. */
	@discardableResult
	func redactMessage(withIdentifier identifier: String, in conversation: Conversation, reason: String?) -> Bool {
		guard supportsMessageRedaction, conversation.isConsole == false, identifier.isEmpty == false else {
			return false
		}
		var arguments = [conversation.name, identifier]
		if let reason = reason?.trimmingCharacters(in: .whitespacesAndNewlines), reason.isEmpty == false {
			arguments.append(reason)
		}
		send(.redact, arguments: arguments)
		return true
	}
}
