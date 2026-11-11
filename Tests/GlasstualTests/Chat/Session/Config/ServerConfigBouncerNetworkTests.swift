// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Bouncer network configuration")
struct ServerConfigBouncerNetworkTests {
	private func account() -> ServerConfig {
		var config = ServerConfig(connectionName: "Account")
		config.nickname = "me"
		config.serverList = [ServerEndpoint(serverAddress: "bnc.example", serverPort: 6697, prefersSecuredConnection: true)]
		config.proxyType = .socks5
		config.proxyAddress = "proxy.example"
		config.validateServerCertificateChain = false
		return config
	}

	@Test("The identifier is stable and depends on both the account and the network")
	func identifierIsStable() {
		let first = ServerConfig.bouncerNetworkConnectionIdentifier(parent: "A", network: "1")

		#expect(first == ServerConfig.bouncerNetworkConnectionIdentifier(parent: "A", network: "1"))
		#expect(first != ServerConfig.bouncerNetworkConnectionIdentifier(parent: "A", network: "2"))
		#expect(first != ServerConfig.bouncerNetworkConnectionIdentifier(parent: "B", network: "1"))
		#expect(UUID(uuidString: first) != nil)
	}

	@Test("A different split of the same characters is a different identifier")
	func identifierSeparatesItsParts() {
		#expect(
			ServerConfig.bouncerNetworkConnectionIdentifier(parent: "A1", network: "2")
				!= ServerConfig.bouncerNetworkConnectionIdentifier(parent: "A", network: "12")
		)
	}

	@Test("A derived connection is named for the network and bound to it")
	func derivation() {
		let parent = account()
		let child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))

		#expect(child.connectionName == "Libera")
		#expect(child.uniqueIdentifier != parent.uniqueIdentifier)
		#expect(child.bouncerNetwork == BouncerNetworkBinding(parentIdentifier: parent.uniqueIdentifier, networkIdentifier: "7"))
		#expect(child.uniqueIdentifier == ServerConfig.bouncerNetworkConnectionIdentifier(
			parent: parent.uniqueIdentifier, network: "7"
		))
		#expect(child.bouncerDiscoversNetworks == false)
		#expect(child.bouncerHidesParent == false)
		#expect(parent.bouncerNetwork == nil)
	}

	@Test("A derived connection inherits the account's endpoint, identity, security and proxy")
	func derivationInherits() {
		let parent = account()
		let child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))

		#expect(child.serverList == parent.serverList)
		#expect(child.nickname == "me")
		#expect(child.proxyType == .socks5)
		#expect(child.proxyAddress == "proxy.example")
		#expect(child.validateServerCertificateChain == false)
		#expect(child.usesSASL == parent.usesSASL)
	}

	@Test("What belongs to the network alone survives a refresh from the account")
	func refreshKeepsNetworkOwnedValues() {
		let parent = account()
		var child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))
		child.conversationList = [ConversationConfig(name: "#chat")]
		child.loginCommands = ["/msg x y"]
		child.lastMessageServerTime = 42
		child.sidebarItemExpanded = false
		child.connectionName = "Renamed by the bouncer"
		var edited = parent
		edited.nickname = "other"

		let refreshed = child.inheritingConnectionSettings(from: edited)

		#expect(refreshed.nickname == "other")
		#expect(refreshed.conversationList.map(\.name) == ["#chat"])
		#expect(refreshed.loginCommands == ["/msg x y"])
		#expect(refreshed.lastMessageServerTime == 42)
		#expect(refreshed.sidebarItemExpanded == false)
		#expect(refreshed.connectionName == "Renamed by the bouncer")
		#expect(refreshed.uniqueIdentifier == child.uniqueIdentifier)
		#expect(refreshed.bouncerNetwork == child.bouncerNetwork)
	}

	@Test("A connection that is not a network keeps its own secrets")
	func plainConnectionUsesItsOwnIdentifier() {
		let config = account()

		#expect(config.credentialIdentifier == config.uniqueIdentifier)
		#expect(config.nicknamePasswordKeychainItem == .nicknamePassword(config.uniqueIdentifier))
		#expect(config.proxyPasswordKeychainItem == .proxyPassword(config.uniqueIdentifier))
		#expect(config.saslSigningKeyKeychainItem == .saslSigningKey(config.uniqueIdentifier))
	}

	@Test("A network reads the account's keychain items instead of keeping copies")
	func networkReadsTheAccountsSecrets() {
		let parent = account()
		let child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))

		#expect(child.credentialIdentifier == parent.uniqueIdentifier)
		#expect(child.nicknamePasswordKeychainItem == parent.nicknamePasswordKeychainItem)
		#expect(child.proxyPasswordKeychainItem == parent.proxyPasswordKeychainItem)
		#expect(child.saslSigningKeyKeychainItem == parent.saslSigningKeyKeychainItem)
		#expect(child.serverList.map(\.keychainItem) == parent.serverList.map(\.keychainItem))
		for item in parent.keychainItems {
			#expect(child.keychainItems.contains(item))
		}
	}

	@Test("A redirect to a host outside the account's servers carries no credentials to a network either")
	func redirectsFollowTheAccountsServerList() {
		let parent = account()
		let child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))
		let origin = parent.serverList[0]
		func redirect(to host: String) -> PendingIRCEndpoint {
			PendingIRCEndpoint(host: host, port: 6697, secured: true, origin: origin, reason: .serverRedirect)
		}

		#expect(redirect(to: "bnc.example").credentialEndpoint(among: child.serverList) == origin)
		#expect(redirect(to: "elsewhere.example").credentialEndpoint(among: child.serverList) == nil)
	}

	@Test("A network carries no pending secret of its own, even when the account has one")
	func networkHoldsNoPendingSecrets() {
		var parent = account()
		parent.pendingNicknamePassword = .set("secret")
		parent.pendingProxyPassword = .set("proxy")
		parent.pendingSASLSigningKey = .set("key")
		parent.serverList[0].pendingServerPassword = .set("server")

		let child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))

		#expect(child.pendingKeychainEdits.isEmpty)
	}

	@Test("Removing a network deletes its channels' keys and DCC identity, never the account's secrets")
	func removalLeavesTheAccountsSecrets() {
		let parent = account()
		var child = parent.derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))
		child.conversationList = [ConversationConfig(name: "#chat")]

		#expect(child.ownedKeychainItems == child.conversationList.map(\.keychainItem) + [
			.dccIdentityKey(child.uniqueIdentifier), .dccIdentityCertificate(child.uniqueIdentifier),
		])
		#expect(child.ownedKeychainItems.contains(parent.nicknamePasswordKeychainItem) == false)
		#expect(child.ownedKeychainItems.contains(.dccIdentityKey(parent.uniqueIdentifier)) == false)
		#expect(parent.ownedKeychainItems == parent.keychainItems + parent.dccIdentityKeychainItems)
	}

	@Test("The binding and the account's switches round-trip through the stored dictionary")
	func codingRoundTrips() throws {
		var parent = account()
		parent.bouncerDiscoversNetworks = false
		parent.bouncerHidesParent = true
		var child = account().derivingBouncerNetwork(BouncerNetwork(id: "7", name: "Libera"))
		child.bouncerNetwork?.isRemoved = true

		let decodedParent = try #require(PropertyListModel.decode(ServerConfig.self, from: parent.dictionaryValue))
		let decodedChild = try #require(PropertyListModel.decode(ServerConfig.self, from: child.dictionaryValue))

		#expect(decodedParent.bouncerDiscoversNetworks == false)
		#expect(decodedParent.bouncerHidesParent)
		#expect(decodedParent.bouncerNetwork == nil)
		#expect(decodedChild.bouncerNetwork == child.bouncerNetwork)
		#expect(decodedChild.bouncerNetwork?.isRemoved == true)
	}

	@Test("A stored configuration from before bouncer networks reads as an ordinary connection")
	func olderConfigurationDefaults() throws {
		let config = try #require(PropertyListModel.decode(ServerConfig.self, from: ["uniqueIdentifier": .string("legacy")]))

		#expect(config.bouncerDiscoversNetworks)
		#expect(config.bouncerHidesParent == false)
		#expect(config.bouncerNetwork == nil)
	}

	@Test("A parent that keeps the defaults writes none of the bouncer keys")
	func defaultsAreNotWritten() {
		let dictionary = account().dictionaryValue

		#expect(dictionary["bouncerDiscoversNetworks"] == nil)
		#expect(dictionary["bouncerHidesParent"] == nil)
		#expect(dictionary["bouncerNetwork"] == nil)
	}
}
