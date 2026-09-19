// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// What the reader chose when a link named a server they are already connected
/// to. Cancel is a real answer: a link that opens an alert with no way out is a
/// link that makes a connection whether or not it was wanted.
enum ServerConnectionMergeChoice: Sendable {
	case useExisting
	case createNew
	case cancel
}

/** Which connection a request means: one already saved, or a new one.

 The decision is the connection layer's -- it compares endpoints, TLS policy and
 stored passwords -- while the question it may have to ask the reader is the
 shell's. `confirmMerge` is that question, handed in rather than raised here. */
@MainActor
enum ServerConnectionResolution {
	/// Resolves `request` against the saved connections and acts on the answer.
	///
	/// `sessions` is the list to search; the application's chat session answers when
	/// nothing is supplied.
	static func resolve(
		using request: ServerConnectionRequest,
		sessions: [ServerSession]? = nil,
		confirmMerge: @MainActor (ServerSession, String, [String]) async -> ServerConnectionMergeChoice,
		mergeConnection: @MainActor (ServerConnectionRequest, ServerSession) -> Void = merge,
		createConnection: @MainActor (ServerConnectionRequest) -> Void = createSession
	) async {
		guard !Task.isCancelled else { return }
		var existingSession: ServerSession?
		/* Whether or not the link names a channel. A link to a server alone
		 used to skip this, so every one added another saved copy of a server
		 the reader already had. */
		if request.options.mergeConnectionIfPossible {
			for candidate in sessions ?? ChatServices.shared.chatSession?.sessions ?? []
				where await credentialsAllowReuse(candidate, for: request)
			{
				existingSession = candidate
				break
			}
		}
		guard !Task.isCancelled else { return }

		/* The question is about adding channels to that connection. With no
		 channel to add there is nothing to ask, and the existing connection is
		 the one the link means. */
		if let matchedSession = existingSession, request.channels.isEmpty == false {
			let startupIdentifier = matchedSession.startup.identifier
			let connection = matchedSession.socket?.uniqueIdentifier
			let choice = await confirmMerge(matchedSession, request.serverAddress, request.channels)
			guard !Task.isCancelled else { return }
			switch choice {
			case .cancel: return
			case .createNew:
				createConnection(request)
				return
			case .useExisting: break
			}
			let stillMatches = await credentialsAllowReuse(matchedSession, for: request)
			guard !Task.isCancelled, !matchedSession.isTerminating,
			      matchedSession.startup.identifier == startupIdentifier,
			      matchedSession.socket?.uniqueIdentifier == connection,
			      stillMatches,
			      (sessions ?? ChatServices.shared.chatSession?.sessions ?? []).contains(where: { $0 === matchedSession })
			else { return }
		}

		if let existingSession {
			mergeConnection(request, existingSession)
		} else {
			createConnection(request)
		}
	}

	static func canReuse(_ session: ServerSession, for request: ServerConnectionRequest) -> Bool {
		let config = session.config
		guard config.serverAddress?.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
		      config.serverPort == request.serverPort,
		      config.prefersSecuredConnection == request.connectSecurely,
		      config.cipherSuites == .system,
		      request.connectSecurely == false || config.validateServerCertificateChain
		else { return false }
		// A live connection can still be using the endpoint from before an edit.
		if let socket = session.socket {
			guard socket.config.serverAddress.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
			      socket.config.serverPort == request.serverPort,
			      socket.config.connectionPrefersSecuredConnection == request.connectSecurely,
			      socket.config.cipherSuites == .system,
			      request.connectSecurely == false || socket.config.connectionShouldValidateCertificateChain
			else { return false }
		}
		return true
	}

	private static func credentialsAllowReuse(
		_ session: ServerSession,
		for request: ServerConnectionRequest
	) async -> Bool {
		guard canReuse(session, for: request) else { return false }
		guard let password = request.serverPassword else { return true }
		guard let server = session.config.serverList.first else { return false }
		let passwords = await KeychainSecretLoader.passwords(for: [server.keychainItem])
		guard !Task.isCancelled, !session.isTerminating,
		      session.config.serverList.first == server, canReuse(session, for: request) else { return false }
		return server.pendingServerPassword.value(orStored: passwords[server.keychainItem]) == password
	}

	private static func merge(_ request: ServerConnectionRequest, into session: ServerSession) {
		var firstChannel: Conversation?
		for name in request.channels {
			let channel = session.findConversationOrCreate(name, isDirect: false)
			firstChannel = firstChannel ?? channel
			if request.options.connectWhenCreated, let channel {
				session.join(channel)
			}
		}

		session.chatSession?.save()
		if request.options.selectFirstChannelAdded, let firstChannel {
			session.output?.select(firstChannel)
		} else if request.channels.isEmpty {
			/* A link to the server alone opens that server. */
			session.output?.select(session)
		}
	}

	private static func createSession(for request: ServerConnectionRequest) {
		var config = ServerConfig()
		config.connectionName = request.serverAddress

		var server = ServerEndpoint(
			serverAddress: request.serverAddress,
			serverPort: request.serverPort,
			prefersSecuredConnection: request.connectSecurely
		)
		server.serverPassword = request.serverPassword
		config.serverList = [server]
		config.conversationList = request.channels.map(ConversationConfig.seed(withName:))

		guard let session = ChatServices.shared.chatSession?.createSession(with: config) else {
			return
		}
		ChatServices.shared.chatSession?.save()

		if request.options.connectWhenCreated {
			session.connect()
		}
		if request.options.selectFirstChannelAdded {
			session.selectFirstConversation()
		}
	}
}
