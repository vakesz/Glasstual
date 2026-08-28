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

/// Holds live `PluginClient`/`PluginChannel` references, so it lives on the
/// main actor with them.
@MainActor
public final class PluginTextEvent {
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

@MainActor
public final class PluginCommandInvocation {
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

@MainActor
public final class PluginIncomingCommandEvent {
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

/// Wraps an untyped host value, so it is neither sendable nor usable off the
/// main actor.
@MainActor
public struct PluginUserInput {
	public let value: Any
	public let commandRawValue: UInt

	public init(value: Any, commandRawValue: UInt) {
		self.value = value
		self.commandRawValue = commandRawValue
	}
}

/// One rendered message, handed to plugins after it appears in the view.
///
/// The host builds it inside the renderer, which runs off the main actor, so
/// this type stays nonisolated.
public final nonisolated class PluginPostedMessage {
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

@MainActor
public final class PluginJavaScriptPayload {
	public var payloadLabel = ""
	public var payloadContents: Any?

	public init() {}
}

/// A value: the plugin manager publishes these rules to the IRC layer, which
/// reads them off the main actor.
public struct PluginOutputSuppressionRule: Equatable, Sendable {
	public var match = ""
	public var restrictConsole = false
	public var restrictChannel = false
	public var restrictPrivateMessage = false

	public init() {}

	public init(
		match: String,
		restrictConsole: Bool = false,
		restrictChannel: Bool = false,
		restrictPrivateMessage: Bool = false
	) {
		self.match = match
		self.restrictConsole = restrictConsole
		self.restrictChannel = restrictChannel
		self.restrictPrivateMessage = restrictPrivateMessage
	}
}
