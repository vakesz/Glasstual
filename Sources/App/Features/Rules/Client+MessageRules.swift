/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

@MainActor
extension Client {
	/// `text` as the rules see it. They are told whether formatting is removed
	/// and read the text on that promise, while the transcript strips it only
	/// where a line is printed.
	private func textForRules(_ text: String) -> String {
		environment.preferences.removeAllFormatting ? (text as NSString).stripIRCEffects : text
	}

	/// Whether the rules allow `message` to be printed, with the message's own
	/// sequence as its text.
	func shouldPrintReceivedMessage(_ message: Message) -> Bool {
		shouldPrintReceivedMessage(message, withText: message.sequence, destinedFor: nil)
	}

	func shouldPrintReceivedMessage(
		_ message: Message,
		withText text: String?,
		destinedFor destination: Channel?
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
		destinedFor destination: Channel?,
		referenceMessage message: Message
	) -> Bool {
		let shouldPrint = AppServices.messageRules.shouldPrintCommand(
			command,
			text: text.map(textForRules),
			authoredBy: message.sender,
			destinedFor: destination,
			onClient: self,
			receivedAt: message.receivedAt,
			messageParameters: message.params
		)
		if shouldPrint, let destination, collapseNetsplitMessage(message, in: destination) {
			return false
		}
		return shouldPrint
	}

	/// Whether the rules allow a received chat line to be printed.
	func shouldPrintReceivedText(
		_ text: String,
		message: Message,
		destination: Channel?,
		lineType: LogLineType
	) -> Bool {
		AppServices.messageRules.shouldPrintText(
			textForRules(text),
			authoredBy: message.sender,
			destinedFor: destination,
			as: lineType,
			onClient: self,
			receivedAt: message.receivedAt,
			wasEncrypted: false
		)
	}
}
