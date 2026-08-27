/* *********************************************************************
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *********************************************************************** */

import Foundation

private final class PluginIncomingCommandContext: @unchecked Sendable {
	let command: String
	let text: String?
	let author: Prefix
	let destination: IRCChannel?
	let client: IRCClient
	let receivedAt: Date
	let message: Message

	init(
		command: String,
		text: String?,
		author: Prefix,
		destination: IRCChannel?,
		client: IRCClient,
		receivedAt: Date,
		message: Message
	) {
		self.command = command
		self.text = text
		self.author = author
		self.destination = destination
		self.client = client
		self.receivedAt = receivedAt
		self.message = message
	}

	@MainActor
	func dispatch() -> Bool {
		PluginDispatcher.dispatchReceivedCommand(
			command,
			withText: text,
			authoredBy: author,
			destinedFor: destination,
			onClient: client,
			receivedAt: receivedAt,
			referenceMessage: message
		)
	}
}

public extension IRCClient {
	@objc(processBundlesUserMessage:command:)
	func processBundlesUserMessage(_ message: String, command: String) {
		PluginDispatcher.userInputCommandInvoked(
			onClient: self,
			commandString: command,
			messageString: message
		)
	}

	@objc(processBundlesServerMessage:)
	func processBundlesServerMessage(_ message: Message) {
		PluginDispatcher.didReceiveServerInput(message, onClient: self)
	}

	@objc(postReceivedMessage:)
	func postReceivedMessage(_ message: Message) -> Bool {
		postReceivedMessage(message, withText: message.sequence, destinedFor: nil)
	}

	@objc(postReceivedMessage:withText:destinedFor:)
	func postReceivedMessage(_ message: Message, withText text: String?, destinedFor destination: IRCChannel?) -> Bool {
		postReceivedCommand(
			message.command,
			withText: text,
			destinedFor: destination,
			referenceMessage: message
		)
	}

	@objc(postReceivedCommand:withText:destinedFor:referenceMessage:)
	func postReceivedCommand(
		_ command: String,
		withText text: String?,
		destinedFor destination: IRCChannel?,
		referenceMessage message: Message
	) -> Bool {
		let context = PluginIncomingCommandContext(
			command: command,
			text: text,
			author: message.sender,
			destination: destination,
			client: self,
			receivedAt: message.receivedAt,
			message: message
		)
		let shouldPrint = MainActor.assumeIsolated {
			context.dispatch()
		}
		if shouldPrint, let destination, collapseNetsplitMessage(message, in: destination) {
			return false
		}
		return shouldPrint
	}
}
