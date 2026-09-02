/* *********************************************************************
 * Copyright (c) 2026 Codeux Software, LLC & respective contributors.
 * Please see Acknowledgements.pdf for additional information.
 *********************************************************************** */

import CocoaExtensions
import Foundation
@testable import Glasstual
import Testing

/// The connection host receives its configuration as a value inside an
/// `NSSecureCoding` envelope, so everything it needs has to survive the
/// archive-and-unarchive that `NSXPCConnection` performs.
@Suite("Connection configuration XPC envelope")
struct IRCConnectionConfigEnvelopeTests {
	private func sampleConfig() -> IRCConnectionConfig {
		var config = IRCConnectionConfig()
		config.serverAddress = "irc.example.test"
		config.serverPort = 6697
		config.addressType = .v6
		config.connectionPrefersSecuredConnection = true
		config.connectionPrefersModernCiphersOnly = true
		config.connectionShouldValidateCertificateChain = true
		config.identityClientSideCertificate = Data([0x01, 0x02, 0x03])
		config.proxyType = .socks5
		config.proxyAddress = "proxy.example.test"
		config.proxyPort = 1081
		config.proxyUsername = "user"
		config.proxyPassword = "hunter2"
		config.floodControlDelayInterval = 5
		config.floodControlMaximumMessages = 3
		config.primaryEncoding = String.Encoding.utf8.rawValue
		config.fallbackEncoding = String.Encoding.isoLatin1.rawValue

		return config
	}

	private func roundTrip(_ config: IRCConnectionConfig) throws -> IRCConnectionConfig {
		let archived = try NSKeyedArchiver.archivedData(
			withRootObject: ConnectionConfigEnvelope(config: config),
			requiringSecureCoding: true
		)
		let unarchived = try NSKeyedUnarchiver.unarchivedObject(
			ofClass: ConnectionConfigEnvelope.self,
			from: archived
		)

		return try #require(unarchived).config
	}

	@Test("Every setting survives the envelope")
	func envelopeRoundTrips() throws {
		let config = sampleConfig()
		let restored = try roundTrip(config)

		#expect(restored == config)
	}

	/// The connection host is the process that presents the proxy password, so
	/// it travels with the configuration by design.
	@Test("The proxy password reaches the connection host")
	func proxyPasswordIsCarried() throws {
		let restored = try roundTrip(sampleConfig())

		#expect(restored.proxyPassword == "hunter2")
	}

	@Test("A zero port means the sender left it out, not a port of zero")
	func absentPortsFallBackToTheDefault() throws {
		var config = IRCConnectionConfig()
		config.serverAddress = "irc.example.test"

		let restored = try roundTrip(config)

		#expect(restored.serverPort == IRCConnectionDefaults.serverPort)
		#expect(restored.proxyPort == IRCConnectionDefaults.proxyPort)
	}

	/// Out-of-range flood-control values used to trip a `precondition` in a
	/// setter that an XPC peer could reach.
	@Test("An out-of-range flood-control value is refused rather than fatal")
	func floodControlValuesAreClamped() {
		var config = IRCConnectionConfig()
		config.floodControlDelayInterval = 5
		config.floodControlDelayInterval = 900

		#expect(config.floodControlDelayInterval == 5)

		config.floodControlMaximumMessages = 4
		config.floodControlMaximumMessages = 0

		#expect(config.floodControlMaximumMessages == 4)
	}

	/// `init(from:)` assigns inside an initializer, where the clamping `didSet`
	/// observers do not run, so a stored zero reaches `applyMissingDefaults`
	/// and is repaired there.
	@Test("A decoded zero flood-control value comes back as the default")
	func decodedFloodControlZeroesFallBackToTheDefault() throws {
		let data = try PropertyListEncoder().encode(sampleConfig())
		let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		var encoded = try #require([String: PropertyListValue](propertyList: plist))
		encoded["floodControlDelayInterval"] = 0
		encoded["floodControlMaximumMessages"] = 0

		let config = try #require(PropertyListModel.decode(IRCConnectionConfig.self, from: encoded))

		#expect(config.floodControlDelayInterval == IRCConnectionDefaults.floodControlDelayInterval)
		#expect(config.floodControlMaximumMessages == IRCConnectionDefaults.floodControlMaximumMessages)
	}

	@Test("A proxy type this build does not know becomes no proxy")
	func unsupportedProxyTypeIsRefused() throws {
		let data = try PropertyListEncoder().encode(sampleConfig())
		let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
		var encoded = try #require([String: PropertyListValue](propertyList: plist))
		encoded["proxyType"] = 4

		let config = try #require(PropertyListModel.decode(IRCConnectionConfig.self, from: encoded))

		#expect(config.proxyType == .none)
	}
}
