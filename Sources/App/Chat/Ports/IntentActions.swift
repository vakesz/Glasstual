// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/// A configured server as Shortcuts and Spotlight see it: identity and state,
/// never credentials.
nonisolated struct IntentServerSnapshot: Sendable, Equatable {
	let id: String
	let name: String
	let isConnected: Bool
}

/// A channel or direct conversation. The console is not one.
nonisolated struct IntentConversationSnapshot: Sendable, Equatable {
	enum Kind: String, Sendable {
		case channel
		case directMessage
	}

	let id: String
	let serverID: String
	let serverName: String
	let name: String
	let kind: Kind
}

nonisolated enum IntentActionError: Error, Equatable, Sendable {
	case applicationNotReady
	case serverNotFound
	case conversationNotFound
	case notConnected
	case invalidChannelName
	case emptyMessage
	case messageTooLong
}

/// Whether a server can take a message or a join now.
nonisolated enum IntentServerReadiness: Equatable, Sendable {
	case ready
	/// Connecting: worth waiting for.
	case wait
	case unavailable

	static func of(isLoggedIn: Bool, isConnecting: Bool, isConnected: Bool) -> Self {
		if isLoggedIn {
			return .ready
		}
		return isConnecting || isConnected ? .wait : .unavailable
	}
}

/** What a typed message must satisfy before an intent sends it.

 The limits are the ones the input field warns at, so a shortcut cannot flood
 a channel the typed path would have asked about. The text is returned
 unchanged otherwise: a leading slash is part of the message, never a command. */
nonisolated enum IntentMessage {
	static let maximumLines = 4
	static let maximumCharacters = 2040

	static func validated(_ text: String) throws(IntentActionError) -> String {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.isEmpty == false else { throw .emptyMessage }
		let lines = trimmed.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
		guard lines <= maximumLines, trimmed.count <= maximumCharacters else { throw .messageTooLong }
		return trimmed
	}

	/// The channel name with a `#` added when it carries no channel prefix.
	static func channelName(_ text: String) throws(IntentActionError) -> String {
		let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard trimmed.isEmpty == false,
		      trimmed.rangeOfCharacter(from: .whitespacesAndNewlines.union(.controlCharacters)) == nil,
		      trimmed.contains(",") == false
		else { throw .invalidChannelName }
		let name = trimmed.first.map { "#&+!".contains($0) } == true ? trimmed : "#" + trimmed
		guard name.count > 1 else { throw .invalidChannelName }
		return name
	}
}

/** What Shortcuts, Siri and Spotlight may ask of the chat layer.

 Everything crosses as a `Sendable` snapshot or an identifier. `sendMessage`
 delivers literal text to a conversation and never parses a command. */
@MainActor
protocol IntentActions: AnyObject {
	func servers() -> [IntentServerSnapshot]
	func conversations() -> [IntentConversationSnapshot]

	func sendMessage(_ text: String, toConversation id: String) async throws(IntentActionError)
	func joinChannel(_ name: String, onServer id: String) async throws(IntentActionError)
	func connect(server id: String) throws(IntentActionError)
	func disconnect(server id: String) throws(IntentActionError)
	func openConversation(id: String) throws(IntentActionError)
}
