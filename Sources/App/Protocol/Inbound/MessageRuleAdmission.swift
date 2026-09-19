// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

@MainActor
extension ServerSession {
	/// `text` as the rules see it. They are told whether formatting is removed
	/// and read the text on that promise, while the transcript strips it only
	/// where a line is printed.
	private func textForRules(_ text: String) -> String {
		environment.settings.removeAllFormatting ? (text as NSString).stripIRCEffects : text
	}

	/// Whether the rules allow `message` to be printed, with the message's own
	/// sequence as its text.
	func shouldPrintReceivedMessage(_ message: Message) -> Bool {
		shouldPrintReceivedMessage(message, withText: message.sequence, destinedFor: nil)
	}

	func shouldPrintReceivedMessage(
		_ message: Message,
		withText text: String?,
		destinedFor destination: Conversation?
	) -> Bool {
		shouldPrintReceivedCommand(
			message.command,
			withText: text,
			destinedFor: destination,
			referenceMessage: message
		)
	}

	func shouldPrintReceivedCommand(
		_ command: String,
		withText text: String?,
		destinedFor destination: Conversation?,
		referenceMessage message: Message
	) -> Bool {
		let shouldPrint = environment.services.messageRules?.shouldPrintCommand(
			command,
			text: text.map(textForRules),
			authoredBy: message.sender,
			destinedFor: destination,
			onSession: self,
			receivedAt: message.receivedAt,
			messageParameters: message.params
		) ?? true
		if shouldPrint, let destination, collapseNetsplitMessage(message, in: destination) {
			return false
		}
		return shouldPrint
	}

	/// Whether the rules allow a received chat line to be printed.
	func shouldPrintReceivedText(
		_ text: String,
		message: Message,
		destination: Conversation?,
		lineType: ChatLineKind
	) -> Bool {
		environment.services.messageRules?.shouldPrintText(
			textForRules(text),
			authoredBy: message.sender,
			destinedFor: destination,
			as: lineType,
			onSession: self,
			receivedAt: message.receivedAt,
			wasEncrypted: false
		) ?? true
	}
}
