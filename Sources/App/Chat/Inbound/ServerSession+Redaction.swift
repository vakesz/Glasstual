// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	/** IRCv3 `draft/message-redaction`: `REDACT <target> <msgid> [:reason]`.

	 The server relays it to every member who negotiated the capability, the
	 sender included, so the broadcast is also the confirmation of a deletion the
	 reader asked for: nothing is removed locally before it arrives. */
	func receiveRedact(_ message: Message) {
		guard isCapabilityEnabled(.messageRedaction), message.params.count >= 2 else { return }
		let identifier = message.params[1]
		guard identifier.isEmpty == false, let conversation = conversation(forTargetedMessage: message) else { return }

		/* The view owns the stored line while it exists. Without one, the
		 conversation's history is redacted directly. */
		if let presentation = conversation.presentation {
			presentation.noteRedaction(ofMessageIdentifier: identifier)
		} else {
			Scrollback.shared.redactMessage(withIdentifier: identifier, inView: conversation.uniqueIdentifier)
		}

		/* A replayed redaction was logged when it first arrived. */
		guard message.isReplayed == false else { return }
		var event = ChatLine()
		event.receivedAt = message.receivedAt
		event.messageBody = String(localized: .IRC.redactionLogged(message.senderNickname ?? "", identifier))
		conversation.writeToLogFile(event)
	}

	/// A `FAIL REDACT <code> <target> [<msgid>] :<description>`, printed in the
	/// conversation the deletion was asked for.
	func receiveRedactionFailure(_ message: Message) {
		guard message.params.count >= 3 else { return }
		let failure = RedactionFailure(code: message.params[1], description: message.params.last ?? "")
		let conversation = message.params.count > 3 ? findConversation(message.params[2]) : nil
		let text = String(localized: .IRC.redactionFailed(failure.explanation))
		guard shouldPrintReceivedMessage(message, withText: text, destinedFor: conversation) else { return }
		print(text, by: nil, in: conversation, as: .debug, command: message.command, receivedAt: message.receivedAt)
	}
}
