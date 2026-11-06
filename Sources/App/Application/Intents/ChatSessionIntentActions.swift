// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** Answers Shortcuts, Siri and Spotlight from the live chat session.

 Sends go through `ServerSession.sendText`, which delivers the text as a
 message. The command parser is not involved, so a message that starts with a
 slash reaches the channel as written. */
@MainActor
final class ChatSessionIntentActions: IntentActions {
	private static let readinessTimeout = Duration.seconds(20)
	private static let readinessPoll = Duration.milliseconds(500)

	private let chatSession: @MainActor () -> ChatSession?
	private let openLink: @MainActor (String) -> Void

	init(chatSession: @escaping @MainActor () -> ChatSession?, openLink: @escaping @MainActor (String) -> Void) {
		self.chatSession = chatSession
		self.openLink = openLink
	}

	func servers() -> [IntentServerSnapshot] {
		(chatSession()?.sessions ?? []).map {
			IntentServerSnapshot(id: $0.uniqueIdentifier, name: $0.name, isConnected: $0.isLoggedIn)
		}
	}

	func conversations() -> [IntentConversationSnapshot] {
		var snapshots: [IntentConversationSnapshot] = []
		for session in chatSession()?.sessions ?? [] {
			for conversation in session.conversationList {
				let kind: IntentConversationSnapshot.Kind
				if conversation.isChannel {
					kind = .channel
				} else if conversation.isDirect {
					kind = .directMessage
				} else {
					continue
				}
				snapshots.append(IntentConversationSnapshot(
					id: conversation.uniqueIdentifier,
					serverID: session.uniqueIdentifier,
					serverName: session.name,
					name: conversation.name,
					kind: kind
				))
			}
		}
		return snapshots
	}

	func sendMessage(_ text: String, toConversation id: String) async throws(IntentActionError) {
		let message = try IntentMessage.validated(text)
		guard let chatSession = chatSession() else { throw .applicationNotReady }
		guard let conversation = chatSession.findItem(withId: id) as? Conversation,
		      let session = conversation.associatedSession
		else { throw .conversationNotFound }

		try await awaitReady(session)
		session.sendText(NSAttributedString(string: message), as: .privmsg, to: conversation)
	}

	func joinChannel(_ name: String, onServer id: String) async throws(IntentActionError) {
		let channel = try IntentMessage.channelName(name)
		let session = try server(id)
		try await awaitReady(session)
		session.joinUnlistedChannel(channel)
	}

	func connect(server id: String) throws(IntentActionError) {
		let session = try server(id)
		guard session.isConnecting == false, session.isConnected == false else { return }
		session.connect()
	}

	func disconnect(server id: String) throws(IntentActionError) {
		try server(id).quit()
	}

	func openConversation(id: String) throws(IntentActionError) {
		guard let chatSession = chatSession() else { throw .applicationNotReady }
		guard chatSession.findItem(withId: id) != nil,
		      let link = ApplicationLink.conversationLink(identifier: id)
		else { throw .conversationNotFound }
		openLink(link)
	}

	private func server(_ id: String) throws(IntentActionError) -> ServerSession {
		guard let chatSession = chatSession() else { throw .applicationNotReady }
		guard let session = chatSession.findSession(withId: id) else { throw .serverNotFound }
		return session
	}

	/// Waits, bounded, for a server that is connecting to finish logging in, so
	/// a shortcut run right after launch does not fail on a race.
	private func awaitReady(_ session: ServerSession) async throws(IntentActionError) {
		let deadline = ContinuousClock.now + Self.readinessTimeout
		while true {
			switch IntentServerReadiness.of(
				isLoggedIn: session.isLoggedIn,
				isConnecting: session.isConnecting,
				isConnected: session.isConnected
			) {
			case .ready:
				return
			case .unavailable:
				throw .notConnected
			case .wait:
				guard ContinuousClock.now < deadline, Task.isCancelled == false else { throw .notConnected }
				try? await Task.sleep(for: Self.readinessPoll)
			}
		}
	}
}
