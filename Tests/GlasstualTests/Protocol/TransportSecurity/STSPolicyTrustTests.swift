import Foundation
@testable import Glasstual
import Testing

/// An STS policy outlives the connection that offered it, so IRCv3 requires it
/// to be ignored when the certificate did not validate on its own.
@Suite("STS policy trust")
@MainActor
struct STSPolicyTrustTests {
	/// A nil user defaults store keeps everything in memory.
	private func store() -> STSPolicyStore {
		STSPolicyStore(userDefaults: nil)
	}

	private func values(_ list: [String]) throws -> STSCapabilityValues {
		try #require(STSCapabilityValues.values(fromCapabilityValues: list))
	}

	@Test("A policy offered over an overridden certificate is ignored")
	func overriddenCertificateIsIgnored() throws {
		let store = store()
		let action = try store.applyCapabilityValues(
			values(["duration=300"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: false
		)

		#expect(action == .none)
		#expect(store.policy(forHost: "irc.example.net") == nil)
	}

	@Test("An overridden certificate cannot withdraw an existing policy either")
	func overriddenCertificateCannotClear() throws {
		let store = store()

		store.setPolicy(
			STSPolicy(port: 6697, expiresAt: Date(timeIntervalSinceNow: 300), preload: false),
			forHost: "irc.example.net"
		)

		let action = try store.applyCapabilityValues(
			values(["duration=0"]),
			forHost: "irc.example.net",
			connectedPort: 6697,
			secured: true,
			certificateChainValidated: false
		)

		#expect(action == .none)
		#expect(store.policy(forHost: "irc.example.net") != nil)
	}

	@Test("A plaintext connection still upgrades regardless of validation")
	func plaintextStillUpgrades() throws {
		let store = store()
		let action = try store.applyCapabilityValues(
			values(["port=6697", "duration=300"]),
			forHost: "irc.example.net",
			connectedPort: 6667,
			secured: false,
			certificateChainValidated: false
		)

		#expect(action == .upgrade(port: 6697))
	}

	@Test("A stored STS policy requires trusted TLS even when verification was disabled")
	func cachedPolicyForcesTrustedTLS() throws {
		let policyStore = store()
		policyStore.setPolicy(STSPolicy(port: 6697, expiresAt: .distantFuture, preload: false), forHost: "irc.example.net")
		let services = ChatServices(stsPolicies: policyStore)
		var config = ServerConfig()
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.net", serverPort: 6667)]
		config.validateServerCertificateChain = false
		let session = ServerSession(config: config, environment: ChatEnvironment(settings: .current(), services: services))
		let connection = try #require(session.takeConnectionEndpoint())
		#expect(connection.serverPort == 6697)
		#expect(connection.connectionPrefersSecuredConnection)
		#expect(connection.connectionRequiresTrustedCertificate)
	}

	@Test("An STS upgrade requires trusted TLS before a persistence policy exists")
	func upgradeRequiresTrustedTLS() throws {
		let services = ChatServices(stsPolicies: store())
		var config = ServerConfig()
		config.serverList = [ServerEndpoint(serverAddress: "irc.example.net", serverPort: 6667)]
		let session = ServerSession(config: config, environment: ChatEnvironment(settings: .current(), services: services))
		session.pendingEndpoint = PendingIRCEndpoint(
			host: "irc.example.net", port: 6697, secured: true, origin: nil, reason: .stsUpgrade
		)
		let connection = try #require(session.takeConnectionEndpoint())
		#expect(connection.connectionRequiresTrustedCertificate)
	}

	@Test("Closing a long-lived secure connection renews its last advertised STS duration")
	func disconnectRenewsExpiredPersistenceOffer() throws {
		let policyStore = store()
		let services = ChatServices(stsPolicies: policyStore)
		let session = ServerSession(config: ServerConfig(), environment: ChatEnvironment(settings: .current(), services: services))
		let offer = try values(["duration=300", "port=6697"])
		policyStore.setPolicy(STSPolicy(port: 7000, expiresAt: .distantPast, preload: false), forHost: "irc.example.net")
		session.activeSTSPolicy = STSConnectionPolicy(host: "irc.example.net", port: 7000, values: offer)
		let closedAt = Date()

		session.resetAllPropertyValues()

		let renewed = try #require(policyStore.policy(forHost: "irc.example.net"))
		#expect(renewed.port == 7000)
		#expect(renewed.expiresAt >= closedAt.addingTimeInterval(300))
		#expect(session.activeSTSPolicy == nil)
	}
}
