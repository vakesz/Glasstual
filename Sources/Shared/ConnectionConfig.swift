// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation
import os

private nonisolated let connectionConfigLogger = Logger(
	subsystem: LogSubsystem.current,
	category: "ConnectionConfig"
)

/// Raw values are persisted. Values 4 and 7 are retired and must not be reused.
nonisolated enum ConnectionProxyKind: UInt, Codable, Sendable {
	case none = 0
	case automatic = 1
	case socks5 = 5
	case HTTP = 6
	case tor = 8
}

/// Controls which IP address families Network.framework may use.
nonisolated enum ConnectionAddressKind: UInt, Codable, Sendable {
	case `default` = 0
	case v4 = 1
	case v6 = 2
}

nonisolated enum ConnectionDefaults {
	static let serverPort: UInt16 = 6667
	static let serverPortSecure: UInt16 = 6697
	static let proxyPort: UInt16 = 1080
	static let floodControlDelayInterval: UInt = 2
	static let floodControlMaximumMessages: UInt = 6
}

/** What one socket needs to reach one endpoint.

 This is what the application hands the isolated connection host, so it is a
 value: the host cannot reach back into the application's copy. The proxy
 password travels with it by design — the host is the process that has to
 present it — and it goes no further than that XPC connection. */
nonisolated struct ConnectionConfig: Codable, Sendable, Equatable {
	var diagnostics: ConnectionDiagnostics?
	var serverAddress = ""
	var serverPort = ConnectionDefaults.serverPort
	var addressType = ConnectionAddressKind.default

	var connectionPrefersSecuredConnection = false
	var connectionShouldValidateCertificateChain = false
	var cipherSuites = CipherSuiteCollection.system
	var identityClientSideCertificate: Data?

	var proxyType = ConnectionProxyKind.none
	var proxyAddress: String?
	var proxyPort = ConnectionDefaults.proxyPort
	var proxyUsername: String?
	/// Sent to the connection host so it can authenticate to the proxy.
	var proxyPassword: String?

	/// Set together through ``setFloodControl(delayInterval:maximumMessages:)``,
	/// which is where the supported range is applied.
	private(set) var floodControlDelayInterval = ConnectionDefaults.floodControlDelayInterval
	private(set) var floodControlMaximumMessages = ConnectionDefaults.floodControlMaximumMessages

	init() {}

	/** The pacing the connection host writes at.

	 One way in, so that the range is applied in one place rather than by a
	 `didSet` that only fires outside an initializer. A value outside the range
	 leaves that setting as it was: it used to trip a `precondition`, and an XPC
	 peer can reach this. */
	mutating func setFloodControl(delayInterval: UInt, maximumMessages: UInt) {
		floodControlDelayInterval = Self.clampedFloodValue(delayInterval, floodControlDelayInterval)
		floodControlMaximumMessages = Self.clampedFloodValue(maximumMessages, floodControlMaximumMessages)
	}

	private enum CodingKeys: String, CodingKey {
		case diagnostics
		case serverAddress
		case serverPort
		case addressType
		case connectionPrefersSecuredConnection
		case connectionShouldValidateCertificateChain
		case cipherSuites
		case identityClientSideCertificate
		case proxyType
		case proxyAddress
		case proxyPort
		case proxyUsername
		case proxyPassword
		case floodControlDelayInterval
		case floodControlMaximumMessages
	}

	init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		self.init()
		diagnostics = container.decodeOptional(ConnectionDiagnostics.self, forKey: .diagnostics)

		serverAddress = container.decode(String.self, forKey: .serverAddress, default: "")
		serverPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			default: ConnectionDefaults.serverPort
		)
		addressType = ConnectionAddressKind(
			rawValue: container.decode(UInt.self, forKey: .addressType, default: 0)
		) ?? .default

		decodeSecurity(from: container)
		decodeProxy(from: container)

		floodControlDelayInterval = container.decode(
			UInt.self,
			forKey: .floodControlDelayInterval,
			default: ConnectionDefaults.floodControlDelayInterval
		)
		floodControlMaximumMessages = container.decode(
			UInt.self,
			forKey: .floodControlMaximumMessages,
			default: ConnectionDefaults.floodControlMaximumMessages
		)

		repairDecodedValues()
	}

	private mutating func decodeSecurity(from container: KeyedDecodingContainer<CodingKeys>) {
		connectionPrefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .connectionPrefersSecuredConnection,
			default: false
		)
		connectionShouldValidateCertificateChain = container.decode(
			Bool.self,
			forKey: .connectionShouldValidateCertificateChain,
			default: false
		)
		cipherSuites = CipherSuiteCollection(
			rawValue: container.decode(
				UInt.self,
				forKey: .cipherSuites,
				default: CipherSuiteCollection.system.rawValue
			)
		) ?? .system
		identityClientSideCertificate = container.decodeOptional(
			Data.self,
			forKey: .identityClientSideCertificate
		)
	}

	private mutating func decodeProxy(from container: KeyedDecodingContainer<CodingKeys>) {
		let rawProxyType = container.decode(UInt.self, forKey: .proxyType, default: 0)
		proxyType = Self.sanitizedProxyType(rawProxyType)
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyAddress)
		proxyPort = container.decode(
			UInt16.self,
			forKey: .proxyPort,
			default: ConnectionDefaults.proxyPort
		)
		proxyUsername = container.decodeOptional(String.self, forKey: .proxyUsername)
		proxyPassword = container.decodeOptional(String.self, forKey: .proxyPassword)
	}

	func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)
		try container.encodeIfPresent(diagnostics, forKey: .diagnostics)

		try container.encode(serverAddress, forKey: .serverAddress)
		try container.encode(serverPort, forKey: .serverPort)
		try container.encode(addressType.rawValue, forKey: .addressType)
		try container.encode(connectionPrefersSecuredConnection, forKey: .connectionPrefersSecuredConnection)
		try container.encode(
			connectionShouldValidateCertificateChain,
			forKey: .connectionShouldValidateCertificateChain
		)
		try container.encode(cipherSuites.rawValue, forKey: .cipherSuites)
		try container.encodeIfPresent(identityClientSideCertificate, forKey: .identityClientSideCertificate)
		try container.encode(proxyType.rawValue, forKey: .proxyType)
		try container.encodeIfPresent(proxyAddress, forKey: .proxyAddress)
		try container.encode(proxyPort, forKey: .proxyPort)
		try container.encodeIfPresent(proxyUsername, forKey: .proxyUsername)
		try container.encodeIfPresent(proxyPassword, forKey: .proxyPassword)
		try container.encode(floodControlDelayInterval, forKey: .floodControlDelayInterval)
		try container.encode(floodControlMaximumMessages, forKey: .floodControlMaximumMessages)
	}

	/** Puts a decoded configuration back inside the range the rest of the host
	 assumes it is in.

	 A zero port means the sender left it out, not that it wanted a port of
	 zero. The flood-control range is the larger point: decoding writes the two
	 settings directly, so whatever the envelope carried survives — and the host
	 narrows the message count to an `Int` on every write, which traps on a
	 `UInt` above `Int.max`. The range is applied here for that reason. */
	private mutating func repairDecodedValues() {
		if proxyPort == 0 {
			proxyPort = ConnectionDefaults.proxyPort
		}

		if serverPort == 0 {
			serverPort = ConnectionDefaults.serverPort
		}

		floodControlDelayInterval = Self.clampedFloodValue(
			floodControlDelayInterval,
			ConnectionDefaults.floodControlDelayInterval
		)
		floodControlMaximumMessages = Self.clampedFloodValue(
			floodControlMaximumMessages,
			ConnectionDefaults.floodControlMaximumMessages
		)
	}

	/** A value outside the supported set means a configuration written by a
	 build that offered a proxy this one does not; refusing the proxy is safer
	 than guessing at one. */
	private static func sanitizedProxyType(_ rawValue: UInt) -> ConnectionProxyKind {
		guard let value = ConnectionProxyKind(rawValue: rawValue) else {
			connectionConfigLogger.error(
				"Unsupported proxy type \(rawValue, privacy: .public) in stored configuration; using no proxy"
			)

			return .none
		}

		return value
	}

	/// The range the connection host reads these two settings in.
	private static let floodValueRange: ClosedRange<UInt> = 1 ... 60

	/// A value outside ``floodValueRange`` used to trip a `precondition`; it is
	/// now clamped back to the last good one.
	private static func clampedFloodValue(_ value: UInt, _ previous: UInt) -> UInt {
		floodValueRange.contains(value) ? value : previous
	}
}

/** Carries an `ConnectionConfig` across the XPC boundary.

 `NSXPCConnection` speaks `NSSecureCoding`, which a value type cannot conform
 to, so the encoded configuration travels as one `Data` blob inside this
 envelope rather than as a class with a property per setting.

 The explicit Objective-C name is the archive's, for the reason
 `SecureConnectionInformation` spells out: this file compiles into both targets,
 so without one the class is named after whichever of them encoded it. */
@objc(RemoteConnectionConfigEnvelope)
final nonisolated class ConnectionConfigEnvelope: NSObject, NSSecureCoding { // nonisolated: immutable
	private static let configurationCodingKey = "config"

	let config: ConnectionConfig

	init(config: ConnectionConfig) {
		self.config = config

		super.init()
	}

	static var supportsSecureCoding: Bool {
		true
	}

	init?(coder: NSCoder) {
		guard let data = coder.decodeObject(of: NSData.self, forKey: Self.configurationCodingKey) as Data?,
		      let config = try? PropertyListDecoder().decode(ConnectionConfig.self, from: data)
		else {
			connectionConfigLogger.error("Received a connection configuration that could not be read")

			return nil
		}

		self.config = config

		super.init()
	}

	func encode(with coder: NSCoder) {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		guard let data = try? encoder.encode(config) else {
			connectionConfigLogger.error("Could not write a connection configuration for the connection host")

			return
		}

		coder.encode(data, forKey: Self.configurationCodingKey)
	}
}
