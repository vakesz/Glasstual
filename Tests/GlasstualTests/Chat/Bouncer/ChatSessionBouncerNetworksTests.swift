// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The connections a parent's networks turn into, and how they follow it.
@MainActor
@Suite("Bouncer network connections")
struct ChatSessionBouncerNetworksTests {
	private let fixture: ChatEnvironmentFixture
	private let chatSession: ChatSession
	private let parent: TestServerSession

	init() {
		let fixture = ChatEnvironmentFixture()
		let parent = TestServerSession(
			configDictionary: ["nickname": "me", "username": "me", "connectionName": "Account"],
			nicknamePassword: nil, fixture: fixture
		)
		var config = parent.config
		config.serverList = [ServerEndpoint(serverAddress: "bnc.example", serverPort: 6697, prefersSecuredConnection: true)]
		config.usesSASL = true
		parent.config = config
		let chatSession = ChatSession(environment: fixture.environment)
		chatSession.sessions = [parent]
		self.fixture = fixture
		self.chatSession = chatSession
		self.parent = parent
	}

	private func network(_ id: String, _ name: String, state: BouncerNetwork.State? = .connected) -> BouncerNetwork {
		BouncerNetwork(id: id, name: name, state: state)
	}

	private func children() -> [ServerSession] {
		chatSession.bouncerChildren(of: parent)
	}

	private func apply(_ changes: BouncerNetworkSet.Changes) {
		chatSession.applyBouncerChanges(changes, from: parent)
	}

	@Test("A discovered network becomes a connection of its own under a stable identifier")
	func discoveredNetworkBecomesAConnection() throws {
		apply(.init(added: [network("1", "Libera"), network("2", "OFTC")]))

		#expect(chatSession.sessions.count == 3)
		#expect(children().map(\.label) == ["Libera", "OFTC"])
		let libera = try #require(children().first)
		#expect(libera.config.uniqueIdentifier == ServerConfig.bouncerNetworkConnectionIdentifier(
			parent: parent.uniqueIdentifier, network: "1"
		))
		#expect(libera.config.bouncerNetwork == BouncerNetworkBinding(
			parentIdentifier: parent.uniqueIdentifier, networkIdentifier: "1"
		))
		#expect(libera.isBouncerNetwork)
		#expect(parent.isBouncerNetwork == false)
	}

	@Test("A child takes the account's endpoint, identity and security, and starts without conversations")
	func childInheritsFromTheAccount() throws {
		var config = parent.config
		config.nickname = "account-nick"
		config.usesSASL = true
		config.alternateNicknames = ["alt"]
		config.conversationList = [ConversationConfig(name: "#parent-only")]
		config.autoConnect = false
		parent.config = config

		apply(.init(added: [network("1", "Libera")]))

		let child = try #require(children().first)
		#expect(child.config.serverList.map(\.serverAddress) == ["bnc.example"])
		#expect(child.config.nickname == "account-nick")
		#expect(child.config.alternateNicknames == ["alt"])
		#expect(child.config.usesSASL)
		#expect(child.config.conversationList.isEmpty)
		#expect(child.config.bouncerDiscoversNetworks == false)
		#expect(child.config.autoConnect == false)
	}

	@Test("A network the account keeps discovering is not made twice")
	func rediscoveryReusesTheConnection() throws {
		apply(.init(added: [network("1", "Libera")]))
		let first = try #require(children().first)

		apply(.init(added: [network("1", "Libera")]))

		#expect(children().count == 1)
		#expect(children().first === first)
	}

	@Test("A network the bouncer renames keeps its connection and its state is followed")
	func changeUpdatesTheConnection() throws {
		apply(.init(added: [network("1", "Libera")]))
		let child = try #require(children().first)

		var changed = network("1", "Libera Chat", state: .disconnected)
		changed.error = "Connection refused"
		apply(.init(changed: [changed]))

		#expect(children().first === child)
		#expect(child.label == "Libera Chat")
		#expect(child.bouncer.networkState == .disconnected)
		#expect(child.bouncer.networkError == "Connection refused")
	}

	@Test("A deleted network stays as read-only history and cannot connect")
	func removedNetworkIsKept() throws {
		apply(.init(added: [network("1", "Libera")]))
		let child = try #require(children().first)
		let channel = chatSession.createConversation(with: ConversationConfig(name: "#chat"), on: child)

		apply(.init(removed: ["1"]))

		#expect(children().count == 1)
		#expect(child.config.bouncerNetwork?.isRemoved == true)
		#expect(child.canContinueConnecting == false)
		#expect(child.conversationList.contains { $0 === channel })
		child.connect()
		#expect(child.isConnecting == false)
	}

	@Test("A network that returns is connectable again")
	func returningNetworkIsRestored() throws {
		apply(.init(added: [network("1", "Libera")]))
		apply(.init(removed: ["1"]))
		let child = try #require(children().first)
		#expect(child.config.bouncerNetwork?.isRemoved == true)

		apply(.init(added: [network("1", "Libera")]))

		#expect(children().count == 1)
		#expect(children().first === child)
		#expect(child.config.bouncerNetwork?.isRemoved == false)
	}

	@Test("A complete listing retires a saved network it no longer names")
	func listingRetiresUnknownNetworks() {
		apply(.init(added: [network("1", "Libera"), network("2", "OFTC")]))

		// A fresh launch knows the networks only from what was saved.
		parent.bouncer = BouncerSession()
		var changes = BouncerNetworkSet.Changes(changed: [])
		changes.completeListing = ["2"]
		apply(changes)

		let removed = children().filter { $0.config.bouncerNetwork?.isRemoved == true }
		#expect(removed.map(\.label) == ["Libera"])
	}

	@Test("Editing the account reaches its networks without touching their own conversations")
	func parentEditsPropagate() throws {
		apply(.init(added: [network("1", "Libera")]))
		let child = try #require(children().first)
		let channel = chatSession.createConversation(with: ConversationConfig(name: "#chat"), on: child)
		child.updateStoredConversationList()

		var edited = parent.config
		edited.nickname = "renamed"
		edited.realName = "New Name"
		parent.updateConfig(edited)

		#expect(child.config.nickname == "renamed")
		#expect(child.config.realName == "New Name")
		#expect(child.label == "Libera")
		#expect(child.conversationList.contains { $0 === channel })
		#expect(child.config.bouncerNetwork?.parentIdentifier == parent.uniqueIdentifier)
	}

	@Test("Networks nest under their account in the order the list holds them")
	func hierarchyFollowsTheList() {
		apply(.init(added: [network("1", "Libera"), network("2", "OFTC")]))
		let other = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		chatSession.sessions.append(other)

		let hierarchy = BouncerHierarchy(sessions: chatSession.sessions)

		#expect(hierarchy.roots.count == 2)
		#expect(hierarchy.roots.first === parent)
		#expect(hierarchy.ordered.map(\.label) == ["Account", "Libera", "OFTC", other.label])
		#expect(hierarchy.children(of: other).isEmpty)
	}

	@Test("A network whose account is gone is still reachable at the top level")
	func orphanedNetworkIsARoot() throws {
		apply(.init(added: [network("1", "Libera")]))
		let child = try #require(children().first)

		let hierarchy = BouncerHierarchy(sessions: [child])

		#expect(hierarchy.roots.count == 1)
		#expect(hierarchy.roots.first === child)
	}

	@Test("Deleting an account removes its networks with it and leaves other connections alone")
	func deletingAnAccountRemovesItsNetworks() {
		apply(.init(added: [network("1", "Libera"), network("2", "OFTC")]))
		let other = TestServerSession(configDictionary: [:], nicknamePassword: nil, fixture: fixture)
		chatSession.sessions.append(other)
		#expect(chatSession.bouncerChildren(of: parent).count == 2)

		chatSession.destroySessionWithBouncerNetworks(parent)

		#expect(chatSession.sessions.count == 1)
		#expect(chatSession.sessions.first === other)
	}

	@Test("Deleting a single network leaves its account and siblings in place")
	func deletingANetworkLeavesTheAccount() throws {
		apply(.init(added: [network("1", "Libera"), network("2", "OFTC")]))
		let libera = try #require(children().first)

		chatSession.destroySessionWithBouncerNetworks(libera)

		#expect(chatSession.sessions.contains { $0 === parent })
		#expect(children().map(\.label) == ["OFTC"])
	}

	@Test("A network whose account vanished another way stays reachable as a top-level connection")
	func orphansSurviveWhenTheAccountVanishes() throws {
		apply(.init(added: [network("1", "Libera")]))
		let libera = try #require(children().first)

		chatSession.sessions.removeAll { $0 === parent }

		#expect(BouncerHierarchy(sessions: chatSession.sessions).roots.first === libera)
	}

	@Test("A listing that creates several networks connects them one second apart when the account does")
	func connectsAreStaggered() {
		var config = parent.config
		config.autoConnect = true
		parent.config = config
		// No connection is opened: a session that is shutting down refuses to.
		fixture.applicationState.applicationIsTerminating = true

		apply(.init(added: [network("1", "A"), network("2", "B"), network("3", "C")]))

		#expect(children().map(\.reconnect.connectDelay) == [0, 1, 2])
	}
}
