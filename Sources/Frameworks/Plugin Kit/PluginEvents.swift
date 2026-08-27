/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
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
 *
 *********************************************************************** */

import Foundation

public final class PluginTextEvent: Sendable {
	public let text: String
	public let author: PluginSender
	public let destination: PluginChannel?
	public let kind: PluginMessageKind
	public let client: PluginClient
	public let receivedAt: Date
	public let wasEncrypted: Bool

	public init(
		text: String,
		author: PluginSender,
		destination: PluginChannel?,
		kind: PluginMessageKind,
		client: PluginClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) {
		self.text = text
		self.author = author
		self.destination = destination
		self.kind = kind
		self.client = client
		self.receivedAt = receivedAt
		self.wasEncrypted = wasEncrypted
	}
}

public final class PluginCommandInvocation: Sendable {
	public let client: PluginClient
	public let command: String
	public let message: String
	public let selectedChannel: PluginChannel?
	public let connectedClients: [PluginClient]

	public init(
		client: PluginClient,
		command: String,
		message: String,
		selectedChannel: PluginChannel?,
		connectedClients: [PluginClient]
	) {
		self.client = client
		self.command = command
		self.message = message
		self.selectedChannel = selectedChannel
		self.connectedClients = connectedClients
	}
}

public final class PluginIncomingCommandEvent: Sendable {
	public let command: String
	public let text: String?
	public let author: PluginSender
	public let destination: PluginChannel?
	public let client: PluginClient
	public let receivedAt: Date
	public let messageParameters: [String]

	public init(
		command: String,
		text: String?,
		author: PluginSender,
		destination: PluginChannel?,
		client: PluginClient,
		receivedAt: Date,
		messageParameters: [String]
	) {
		self.command = command
		self.text = text
		self.author = author
		self.destination = destination
		self.client = client
		self.receivedAt = receivedAt
		self.messageParameters = messageParameters
	}
}

public struct PluginRenderEvent: Sendable {
	public let message: String
	public let kind: PluginMessageKind

	public init(message: String, kind: PluginMessageKind) {
		self.message = message
		self.kind = kind
	}
}

public struct PluginUserInput {
	public let value: Any
	public let commandRawValue: UInt

	public init(value: Any, commandRawValue: UInt) {
		self.value = value
		self.commandRawValue = commandRawValue
	}
}

public final class PluginPostedMessage: @unchecked Sendable {
	public var isProcessedInBulk = false
	public var messageContents = ""
	public var lineNumber = ""
	public var senderNickname: String?
	public var lineTypeRawValue: UInt = 0
	public var memberTypeRawValue: UInt = 0
	public var receivedAt = Date()
	public var hyperlinks: [AnyObject] = []
	public var users: [AnyObject] = []
	public var keywordMatchFound = false

	public init() {}
}

public final class PluginJavaScriptPayload: @unchecked Sendable {
	public var payloadLabel = ""
	public var payloadContents: Any?

	public init() {}
}

public final class PluginOutputSuppressionRule: @unchecked Sendable {
	public var match = ""
	public var restrictConsole = false
	public var restrictChannel = false
	public var restrictPrivateMessage = false

	public init() {}
}
