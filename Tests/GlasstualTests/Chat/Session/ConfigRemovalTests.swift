// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
final class RemovalPresentation: ChatItemPresenting {
	let presentationIdentifier = UUID().uuidString
	private(set) var preservedRemovals = 0
	private(set) var permanentRemovals = 0
	private(set) var applicationTerminations = 0

	func print(_: ChatLine, completionBlock _: PrintedLineCompletion?) {}
	func lastPrintedLine() -> ChatLine? {
		nil
	}

	func setTopic(_: String?) {}
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber _: String,
		state _: ChatLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}

	func prependEarlierChatLines(_: [ChatLine]) {}
	func tearDown(_ reason: ChatItemTeardown) {
		switch reason {
		case .applicationTermination: applicationTerminations += 1
		case .preservingRemoval: preservedRemovals += 1
		case .permanentRemoval: permanentRemovals += 1
		}
	}
}

@MainActor
@Suite("Config removal preserves local data")
struct ConfigRemovalTests {
	@Test("Restore removes the session and tears down every presentation without deleting secret intent")
	func preservingSessionRemoval() throws {
		let fixture = ChatEnvironmentFixture()
		var config = ServerConfig(connectionName: "Removal fixture")
		config.conversationList = [ConversationConfig(name: "#removed"),
		                           ConversationConfig(name: "Query", type: .direct)]
		let session = fixture.chatSession.createSession(with: config)
		// Install intent after construction so no password is written to the keychain.
		session.config.pendingNicknamePassword = .set("fixture-nickname")
		session.config.pendingProxyPassword = .set("fixture-proxy")
		session.config.serverList = [ServerEndpoint(
			serverAddress: "irc.example.test",
			pendingServerPassword: .set("fixture-server")
		)]
		session.config.conversationList[0].pendingSecretKey = .set("fixture-channel")
		let presentations = (0 ... session.conversationList.count).map { _ in RemovalPresentation() }
		session.presentation = presentations[0]
		for (index, channel) in session.conversationList.enumerated() {
			channel.presentation = presentations[index + 1]
			channel.activate()
		}
		session.startPongTimer()
		session.pendingConnectionTask = Task { try? await Task.sleep(for: .seconds(60)) }
		let scheduledConnection = try #require(session.pendingConnectionTask)

		fixture.chatSession.destroySession(session, preservingLocalData: true)

		#expect(fixture.chatSession.sessions.isEmpty)
		#expect(session.isTerminating)
		#expect(!session.pongTimer.isActive)
		#expect(session.pendingConnectionTask == nil)
		#expect(scheduledConnection.isCancelled)
		#expect(session.config.pendingNicknamePassword == .set("fixture-nickname"))
		#expect(session.config.pendingProxyPassword == .set("fixture-proxy"))
		#expect(session.config.serverList[0].pendingServerPassword == .set("fixture-server"))
		#expect(session.config.conversationList[0].pendingSecretKey == .set("fixture-channel"))
		#expect(fixture.output.closedSheetSessions == [session])
		#expect(fixture.output.closedSheetChannelIds == session.conversationList.map(\.uniqueIdentifier))
		#expect(fixture.applicationState.sessionsFinishedTerminating == 0)
		for channel in session.conversationList {
			#expect(channel.status == .terminated)
			#expect(channel.memberInfo == nil)
		}
		for presentation in presentations {
			#expect(presentation.preservedRemovals == 1)
			#expect(presentation.permanentRemovals == 0)
			#expect(presentation.applicationTerminations == 0)
		}
	}

	@Test("The disconnect callback retains the preserving removal option")
	func preservingSessionRemovalAfterDisconnect() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Deferred removal"))
		let presentation = RemovalPresentation()
		session.presentation = presentation
		session.config.pendingNicknamePassword = .set("fixture-nickname")
		session.isConnected = true
		session.isQuitting = true

		fixture.chatSession.destroySession(session, preservingLocalData: true)
		#expect(fixture.chatSession.sessions == [session])
		#expect(session.disconnectCallbacks.count == 1)
		#expect(presentation.preservedRemovals == 0)
		session.isConnected = false
		session.invokeDisconnectCallbacks()

		#expect(fixture.chatSession.sessions.isEmpty)
		#expect(session.config.pendingNicknamePassword == .set("fixture-nickname"))
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
	}

	@Test("Removing a session during credential preparation completes its disconnect", .timeLimit(.minutes(1)))
	func removalDuringCredentialPreparation() async throws {
		let fixture = ChatEnvironmentFixture()
		var config = ServerConfig(connectionName: "Preparing removal")
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.test")]
		let session = fixture.chatSession.createSession(with: config)
		let presentation = RemovalPresentation()
		session.presentation = presentation
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		// The backend can finish after cancellation, as a Security call can.
		let response = Task { for await _ in gate {} }
		defer {
			release.finish()
			response.cancel()
		}
		session.credentialLoader = { items in
			didStart.yield(())
			await response.value
			return Dictionary(items.map { ($0, "late credential") }, uniquingKeysWith: { _, newest in newest })
		}
		session.connect()
		let preparation = try #require(session.pendingCredentialTask)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		var disconnects = 0
		session.addDisconnectCallback {
			disconnects += 1
			#expect(!session.isConnecting)
			#expect(!session.isDisconnecting)
		}

		fixture.chatSession.destroySession(session, preservingLocalData: true)

		#expect(fixture.chatSession.sessions.isEmpty)
		#expect(session.isTerminating)
		#expect(session.pendingCredentialTask == nil)
		#expect(preparation.isCancelled)
		#expect(disconnects == 1)
		#expect(session.disconnectCallbacks.isEmpty)
		#expect(presentation.preservedRemovals == 1)
		release.finish()
		await preparation.value
		#expect(session.socket == nil)
		#expect(session.sessionNicknamePassword == nil)
		#expect(disconnects == 1)
	}

	@Test("A pre-socket quit can reconnect before the old credential lookup finishes", .timeLimit(.minutes(1)))
	func reconnectDuringCredentialPreparation() async throws {
		let fixture = ChatEnvironmentFixture()
		var config = ServerConfig(connectionName: "Preparing reconnect")
		config.serverList = [ServerEndpoint(serverAddress: "old.example.test")]
		let session = fixture.chatSession.createSession(with: config)
		let (oldGate, releaseOld) = AsyncStream<Void>.makeStream()
		let (newGate, releaseNew) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Int>.makeStream()
		let oldResponse = Task { for await _ in oldGate {} }
		let newResponse = Task { for await _ in newGate {} }
		defer {
			releaseOld.finish()
			releaseNew.finish()
			oldResponse.cancel()
			newResponse.cancel()
		}
		session.credentialLoader = { items in
			didStart.yield(1)
			await oldResponse.value
			return Dictionary(items.map { ($0, "old credential") }, uniquingKeysWith: { _, newest in newest })
		}
		session.connect()
		let oldPreparation = try #require(session.pendingCredentialTask)
		var iterator = started.makeAsyncIterator()
		#expect(await iterator.next() == 1)
		var disconnects = 0
		session.addDisconnectCallback {
			disconnects += 1
			session.config.serverList = [ServerEndpoint(serverAddress: "new.example.test")]
			session.credentialLoader = { _ in
				didStart.yield(2)
				await newResponse.value
				return [:]
			}
			session.connect()
		}

		session.quit()

		#expect(disconnects == 1)
		#expect(await iterator.next() == 2)
		let newPreparation = try #require(session.pendingCredentialTask)
		let newSession = session.startup.identifier
		releaseOld.finish()
		await oldPreparation.value
		#expect(session.isConnecting)
		#expect(session.startup.identifier == newSession)
		#expect(session.server?.serverAddress == "new.example.test")
		#expect(session.pendingCredentialTask != nil)
		#expect(!newPreparation.isCancelled)
		#expect(session.socket == nil)
		#expect(session.sessionNicknamePassword == nil)
		session.addDisconnectCallback { disconnects += 1 }
		session.cancelReconnect()
		session.disconnect()
		releaseNew.finish()
		await newPreparation.value
		#expect(disconnects == 2)
		#expect(session.disconnectCallbacks.isEmpty)
		#expect(!session.isConnecting)
		#expect(session.socket == nil)
	}

	@Test("Transfer reconciliation releases removed channels even when redraw is batched")
	func preservingChannelReconciliation() throws {
		let fixture = ChatEnvironmentFixture()
		let observer = RecordingDirectoryObserver()
		fixture.chatSession.addObserver(observer)
		var config = ServerConfig(connectionName: "Reconcile fixture")
		config.conversationList = [ConversationConfig(name: "#removed"), ConversationConfig(name: "#kept")]
		let session = fixture.chatSession.createSession(with: config)
		let removed = try #require(session.conversationList.first)
		let kept = try #require(session.conversationList.last)
		let presentation = RemovalPresentation()
		removed.presentation = presentation
		removed.activate()
		session.lastSelectedConversation = removed
		var replacement = session.config
		replacement.conversationList = [kept.config]

		session.updateConfig(replacement, for: .transfer)

		#expect(session.conversationList == [kept])
		#expect(session.config.conversationList == [kept.config])
		#expect(session.lastSelectedConversation == nil)
		#expect(removed.status == .terminated)
		#expect(removed.memberInfo == nil)
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
		#expect(observer.events.contains(.removedChannel(removed.name, on: session.uniqueIdentifier)))
		#expect(fixture.output.closedSheetChannelIds == [removed.uniqueIdentifier])
		#expect(!session.isTerminating)
	}

	@Test("A same-name conversation replaces the old identity and respects query persistence",
	      arguments: [false, true], [false, true])
	func replacingChannelIdentity(isQuery: Bool, rememberDirectConversations: Bool) throws {
		let fixture = ChatEnvironmentFixture()
		var settings = fixture.chatSession.environment.settings
		settings.remembersDirectConversations = rememberDirectConversations
		fixture.chatSession.applySettings(settings)
		var config = ServerConfig(connectionName: "Replacement fixture")
		config.conversationList = [ConversationConfig(
			name: isQuery ? "Peer" : "#same-name",
			type: isQuery ? .direct : .channel
		)]
		let session = fixture.chatSession.createSession(with: config)
		let oldChannel = try #require(session.conversationList.first)
		let presentation = RemovalPresentation()
		oldChannel.presentation = presentation
		var replacement = session.config
		let newChannel = ConversationConfig(name: oldChannel.name, type: oldChannel.type)
		replacement.conversationList = [newChannel]

		session.updateConfig(replacement, for: .transfer)

		#expect(session.conversationList.map(\.uniqueIdentifier) == [newChannel.uniqueIdentifier])
		#expect(session.config.conversationList == (isQuery && !rememberDirectConversations ? [] : [newChannel]))
		#expect(oldChannel.status == .terminated)
		#expect(presentation.preservedRemovals == 1)
	}

	@Test("Only legacy reconciliation retires a removed active endpoint's keychain item", arguments: [false, true])
	func serverPasswordRetirement(preservingLocalData: Bool) {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Endpoint fixture"))
		let endpoint = ServerEndpoint(serverAddress: "irc.example.test", pendingServerPassword: .set("fixture-server"))
		session.config.serverList = [endpoint]
		session.server = endpoint
		var replacement = session.config
		replacement.serverList = []

		if preservingLocalData {
			session.updateConfig(replacement, for: .transfer)
		} else {
			session.updateConfig(replacement)
		}

		#expect(session.config.serverList.isEmpty)
		#expect(session.lastServerSelected == nil)
		#expect(session.retiredServerKeychainItems.contains(endpoint.keychainItem) == !preservingLocalData)
		#expect(session.server?.pendingServerPassword == .set("fixture-server"))
		// The legacy path queued a deletion; do not flush it to the personal keychain.
		session.retiredServerKeychainItems.removeAll()
	}

	@Test("Ordinary server edits retain unmatched live queries")
	func serverEditorRetainsQueries() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Before edit"))
		let query = fixture.chatSession.createDirectConversation("KeptPeer", on: session)
		let presentation = RemovalPresentation()
		query.presentation = presentation
		var edited = session.config
		edited.connectionName = "After edit"
		edited.conversationList = []

		session.updateConfig(edited)

		#expect(session.config.connectionName == "After edit")
		#expect(session.conversationList == [query])
		#expect(query.status != .terminated)
		#expect(presentation.preservedRemovals == 0)
		#expect(presentation.permanentRemovals == 0)
	}

	@Test("Ordinary channel deactivation does not tear down its presentation")
	func deactivationKeepsPresentation() {
		let fixture = ChatEnvironmentFixture()
		let session = fixture.chatSession.createSession(with: ServerConfig(connectionName: "Deactivation fixture"))
		let channel = fixture.chatSession.createConversation(with: ConversationConfig(name: "#parted"), on: session)
		let presentation = RemovalPresentation()
		channel.presentation = presentation
		channel.activate()

		channel.deactivate()

		#expect(channel.status == .parted)
		#expect(session.conversationList == [channel])
		#expect(channel.presentation === presentation)
		#expect(presentation.preservedRemovals == 0)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
	}
}
