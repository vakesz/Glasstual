/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
final class RemovalPresentation: ChatItemPresentation {
	let presentationIdentifier = UUID().uuidString
	private(set) var preservedRemovals = 0
	private(set) var permanentRemovals = 0
	private(set) var applicationTerminations = 0

	func print(_: LogLine, completionBlock _: PrintedLineCompletion?) {}
	func lastPrintedLine() -> LogLine? {
		nil
	}

	func setTopic(_: String?) {}
	func mark() {}
	func mark(at _: Date) {}
	func noteReaction(_: String, fromNickname _: String, toMessageIdentifier _: String) {}
	func updateDeliveryState(
		forLineNumber _: String,
		state _: LogLineDeliveryState,
		messageIdentifier _: String?,
		reason _: String?
	) {}

	func prependHistoricLogLines(_: [LogLine]) {}
	func tearDown(_ reason: ChatItemTeardown) {
		switch reason {
		case .applicationTermination: applicationTerminations += 1
		case .preservingRemoval: preservedRemovals += 1
		case .permanentRemoval: permanentRemovals += 1
		}
	}
}

@MainActor
@Suite("Configuration removal preserves local data")
struct ConfigurationRemovalTests {
	@Test("Restore removes the client and tears down every presentation without deleting secret intent")
	func preservingClientRemoval() throws {
		let fixture = ClientEnvironmentFixture()
		var config = ClientConfig(connectionName: "Removal fixture")
		config.channelList = [ChannelConfig(channelName: "#removed"),
		                      ChannelConfig(channelName: "Query", type: .privateMessage)]
		let client = fixture.clientDirectory.createClient(with: config)
		// Install intent after construction so no password is written to the keychain.
		client.config.pendingNicknamePassword = .set("fixture-nickname")
		client.config.pendingProxyPassword = .set("fixture-proxy")
		client.config.serverList = [Server(
			serverAddress: "irc.example.test",
			pendingServerPassword: .set("fixture-server")
		)]
		client.config.channelList[0].pendingSecretKey = .set("fixture-channel")
		let presentations = (0 ... client.channelList.count).map { _ in RemovalPresentation() }
		client.presentation = presentations[0]
		for (index, channel) in client.channelList.enumerated() {
			channel.presentation = presentations[index + 1]
			channel.activate()
		}
		client.startPongTimer()
		client.pendingConnectionTask = Task { try? await Task.sleep(for: .seconds(60)) }
		let scheduledConnection = try #require(client.pendingConnectionTask)

		fixture.clientDirectory.destroyClient(client, preservingLocalData: true)

		#expect(fixture.clientDirectory.clientList.isEmpty)
		#expect(client.isTerminating)
		#expect(!client.pongTimer.isActive)
		#expect(client.pendingConnectionTask == nil)
		#expect(scheduledConnection.isCancelled)
		#expect(client.config.pendingNicknamePassword == .set("fixture-nickname"))
		#expect(client.config.pendingProxyPassword == .set("fixture-proxy"))
		#expect(client.config.serverList[0].pendingServerPassword == .set("fixture-server"))
		#expect(client.config.channelList[0].pendingSecretKey == .set("fixture-channel"))
		#expect(fixture.output.closedSheetClients == [client])
		#expect(fixture.output.closedSheetChannelIds == client.channelList.map(\.uniqueIdentifier))
		#expect(fixture.applicationState.clientsFinishedTerminating == 0)
		for channel in client.channelList {
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
	func preservingClientRemovalAfterDisconnect() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Deferred removal"))
		let presentation = RemovalPresentation()
		client.presentation = presentation
		client.config.pendingNicknamePassword = .set("fixture-nickname")
		client.isConnected = true
		client.isQuitting = true

		fixture.clientDirectory.destroyClient(client, preservingLocalData: true)
		#expect(fixture.clientDirectory.clientList == [client])
		#expect(client.disconnectCallbacks.count == 1)
		#expect(presentation.preservedRemovals == 0)
		client.isConnected = false
		client.invokeDisconnectCallbacks()

		#expect(fixture.clientDirectory.clientList.isEmpty)
		#expect(client.config.pendingNicknamePassword == .set("fixture-nickname"))
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
	}

	@Test("Removing a client during credential preparation completes its disconnect", .timeLimit(.minutes(1)))
	func removalDuringCredentialPreparation() async throws {
		let fixture = ClientEnvironmentFixture()
		var config = ClientConfig(connectionName: "Preparing removal")
		config.serverList = [Server(serverAddress: "irc.example.test")]
		let client = fixture.clientDirectory.createClient(with: config)
		let presentation = RemovalPresentation()
		client.presentation = presentation
		let (gate, release) = AsyncStream<Void>.makeStream()
		let (started, didStart) = AsyncStream<Void>.makeStream()
		// The backend can finish after cancellation, as a Security call can.
		let response = Task { for await _ in gate {} }
		defer {
			release.finish()
			response.cancel()
		}
		client.credentialLoader = { items in
			didStart.yield(())
			await response.value
			return Dictionary(items.map { ($0, "late credential") }, uniquingKeysWith: { _, newest in newest })
		}
		client.connect()
		let preparation = try #require(client.pendingCredentialTask)
		var iterator = started.makeAsyncIterator()
		_ = await iterator.next()
		var disconnects = 0
		client.addDisconnectCallback {
			disconnects += 1
			#expect(!client.isConnecting)
			#expect(!client.isDisconnecting)
		}

		fixture.clientDirectory.destroyClient(client, preservingLocalData: true)

		#expect(fixture.clientDirectory.clientList.isEmpty)
		#expect(client.isTerminating)
		#expect(client.pendingCredentialTask == nil)
		#expect(preparation.isCancelled)
		#expect(disconnects == 1)
		#expect(client.disconnectCallbacks.isEmpty)
		#expect(presentation.preservedRemovals == 1)
		release.finish()
		await preparation.value
		#expect(client.socket == nil)
		#expect(client.sessionNicknamePassword == nil)
		#expect(disconnects == 1)
	}

	@Test("A pre-socket quit can reconnect before the old credential lookup finishes", .timeLimit(.minutes(1)))
	func reconnectDuringCredentialPreparation() async throws {
		let fixture = ClientEnvironmentFixture()
		var config = ClientConfig(connectionName: "Preparing reconnect")
		config.serverList = [Server(serverAddress: "old.example.test")]
		let client = fixture.clientDirectory.createClient(with: config)
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
		client.credentialLoader = { items in
			didStart.yield(1)
			await oldResponse.value
			return Dictionary(items.map { ($0, "old credential") }, uniquingKeysWith: { _, newest in newest })
		}
		client.connect()
		let oldPreparation = try #require(client.pendingCredentialTask)
		var iterator = started.makeAsyncIterator()
		#expect(await iterator.next() == 1)
		var disconnects = 0
		client.addDisconnectCallback {
			disconnects += 1
			client.config.serverList = [Server(serverAddress: "new.example.test")]
			client.credentialLoader = { _ in
				didStart.yield(2)
				await newResponse.value
				return [:]
			}
			client.connect()
		}

		client.quit()

		#expect(disconnects == 1)
		#expect(await iterator.next() == 2)
		let newPreparation = try #require(client.pendingCredentialTask)
		let newSession = client.startup.identifier
		releaseOld.finish()
		await oldPreparation.value
		#expect(client.isConnecting)
		#expect(client.startup.identifier == newSession)
		#expect(client.server?.serverAddress == "new.example.test")
		#expect(client.pendingCredentialTask != nil)
		#expect(!newPreparation.isCancelled)
		#expect(client.socket == nil)
		#expect(client.sessionNicknamePassword == nil)
		client.addDisconnectCallback { disconnects += 1 }
		client.cancelReconnect()
		client.disconnect()
		releaseNew.finish()
		await newPreparation.value
		#expect(disconnects == 2)
		#expect(client.disconnectCallbacks.isEmpty)
		#expect(!client.isConnecting)
		#expect(client.socket == nil)
	}

	@Test("Transfer reconciliation releases removed channels even when redraw is batched")
	func preservingChannelReconciliation() throws {
		let fixture = ClientEnvironmentFixture()
		let observer = RecordingDirectoryObserver()
		fixture.clientDirectory.addObserver(observer)
		var config = ClientConfig(connectionName: "Reconcile fixture")
		config.channelList = [ChannelConfig(channelName: "#removed"), ChannelConfig(channelName: "#kept")]
		let client = fixture.clientDirectory.createClient(with: config)
		let removed = try #require(client.channelList.first)
		let kept = try #require(client.channelList.last)
		let presentation = RemovalPresentation()
		removed.presentation = presentation
		removed.activate()
		client.lastSelectedChannel = removed
		var replacement = client.config
		replacement.channelList = [kept.config]

		client.updateConfig(replacement, for: .transfer)

		#expect(client.channelList == [kept])
		#expect(client.config.channelList == [kept.config])
		#expect(client.lastSelectedChannel == nil)
		#expect(removed.status == .terminated)
		#expect(removed.memberInfo == nil)
		#expect(presentation.preservedRemovals == 1)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
		#expect(observer.events.contains(.removedChannel(removed.name, on: client.uniqueIdentifier)))
		#expect(fixture.output.closedSheetChannelIds == [removed.uniqueIdentifier])
		#expect(!client.isTerminating)
	}

	@Test("A same-name conversation replaces the old identity and respects query persistence",
	      arguments: [false, true], [false, true])
	func replacingChannelIdentity(isQuery: Bool, rememberQueries: Bool) throws {
		let fixture = ClientEnvironmentFixture()
		var preferences = fixture.clientDirectory.environment.preferences
		preferences.rememberServerListQueryStates = rememberQueries
		fixture.clientDirectory.applyPreferences(preferences)
		var config = ClientConfig(connectionName: "Replacement fixture")
		config.channelList = [ChannelConfig(
			channelName: isQuery ? "Peer" : "#same-name",
			type: isQuery ? .privateMessage : .channel
		)]
		let client = fixture.clientDirectory.createClient(with: config)
		let oldChannel = try #require(client.channelList.first)
		let presentation = RemovalPresentation()
		oldChannel.presentation = presentation
		var replacement = client.config
		let newChannel = ChannelConfig(channelName: oldChannel.name, type: oldChannel.type)
		replacement.channelList = [newChannel]

		client.updateConfig(replacement, for: .transfer)

		#expect(client.channelList.map(\.uniqueIdentifier) == [newChannel.uniqueIdentifier])
		#expect(client.config.channelList == (isQuery && !rememberQueries ? [] : [newChannel]))
		#expect(oldChannel.status == .terminated)
		#expect(presentation.preservedRemovals == 1)
	}

	@Test("Only legacy reconciliation retires a removed active endpoint's keychain item", arguments: [false, true])
	func serverPasswordRetirement(preservingLocalData: Bool) {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Endpoint fixture"))
		let endpoint = Server(serverAddress: "irc.example.test", pendingServerPassword: .set("fixture-server"))
		client.config.serverList = [endpoint]
		client.server = endpoint
		var replacement = client.config
		replacement.serverList = []

		if preservingLocalData {
			client.updateConfig(replacement, for: .transfer)
		} else {
			client.updateConfig(replacement)
		}

		#expect(client.config.serverList.isEmpty)
		#expect(client.lastServerSelected == UInt(NSNotFound))
		#expect(client.retiredServerKeychainItems.contains(endpoint.keychainItem) == !preservingLocalData)
		#expect(client.server?.pendingServerPassword == .set("fixture-server"))
		// The legacy path queued a deletion; do not flush it to the personal keychain.
		client.retiredServerKeychainItems.removeAll()
	}

	@Test("Ordinary server edits retain unmatched live queries")
	func serverEditorRetainsQueries() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Before edit"))
		let query = fixture.clientDirectory.createPrivateMessage("KeptPeer", on: client)
		let presentation = RemovalPresentation()
		query.presentation = presentation
		var edited = client.config
		edited.connectionName = "After edit"
		edited.channelList = []

		client.updateConfig(edited)

		#expect(client.config.connectionName == "After edit")
		#expect(client.channelList == [query])
		#expect(query.status != .terminated)
		#expect(presentation.preservedRemovals == 0)
		#expect(presentation.permanentRemovals == 0)
	}

	@Test("Ordinary channel deactivation does not tear down its presentation")
	func deactivationKeepsPresentation() {
		let fixture = ClientEnvironmentFixture()
		let client = fixture.clientDirectory.createClient(with: ClientConfig(connectionName: "Deactivation fixture"))
		let channel = fixture.clientDirectory.createChannel(with: ChannelConfig(channelName: "#parted"), on: client)
		let presentation = RemovalPresentation()
		channel.presentation = presentation
		channel.activate()

		channel.deactivate()

		#expect(channel.status == .parted)
		#expect(client.channelList == [channel])
		#expect(channel.presentation === presentation)
		#expect(presentation.preservedRemovals == 0)
		#expect(presentation.permanentRemovals == 0)
		#expect(presentation.applicationTerminations == 0)
	}
}
