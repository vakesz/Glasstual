// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// The response to adding channels to an existing connection.
enum ServerConnectionMergeChoice: Sendable {
	case useExisting
	case createNew
	case cancel
}

/// Reuses a compatible session or creates one through the supplied handler.
@MainActor
enum ServerConnectionResolution {
	/// Reads the current session directory again after asynchronous confirmation.
	static func resolve(
		using request: ServerConnectionRequest,
		sessions: @MainActor () -> [ServerSession],
		confirmMerge: @MainActor (ServerSession, String, [String]) async -> ServerConnectionMergeChoice,
		mergeConnection: @MainActor (ServerConnectionRequest, ServerSession) -> Void = merge,
		createConnection: @MainActor (ServerConnectionRequest) -> Void
	) async {
		guard !Task.isCancelled else { return }
		var existingSession: ServerSession?
		if request.options.mergeConnectionIfPossible {
			for candidate in sessions()
				where await credentialsAllowReuse(candidate, for: request)
			{
				existingSession = candidate
				break
			}
		}
		guard !Task.isCancelled else { return }

		// Only adding channels requires confirmation. A server-only link selects its session.
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
			      sessions().contains(where: { $0 === matchedSession })
			else { return }
		}

		if let existingSession {
			guard sessions().contains(where: { $0 === existingSession }), canReuse(existingSession, for: request) else { return }
			mergeConnection(request, existingSession)
		} else {
			createConnection(request)
		}
	}

	static func canReuse(_ session: ServerSession, for request: ServerConnectionRequest) -> Bool {
		let config = session.config
		guard !session.isTerminating, config.serverAddress?.caseInsensitiveCompare(request.serverAddress) == .orderedSame,
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
}

extension ChatSession {
	func createSession(for request: ServerConnectionRequest) {
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

		let session = createSession(with: config)
		save()

		if request.options.connectWhenCreated {
			session.connect()
		}
		if request.options.selectFirstChannelAdded {
			session.selectFirstConversation()
		}
	}
}
