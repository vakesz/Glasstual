/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import os

private nonisolated let connectionConfigLogger = Logger( // nonisolated: let
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "Connection"
)

/// Raw values are persisted. Values 4 and 7 are retired and must not be reused.
nonisolated enum ConnectionProxyType: UInt, Codable, Sendable { // nonisolated: value
	case none = 0
	case automatic = 1
	case socks5 = 5
	case HTTP = 6
	case tor = 8
}

/// Controls which IP address families Network.framework may use.
nonisolated enum ConnectionAddressType: UInt, Codable, Sendable { // nonisolated: value
	case `default` = 0
	case v4 = 1
	case v6 = 2
}

nonisolated enum ConnectionDefaults { // nonisolated: value
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
nonisolated struct ConnectionConfig: Codable, Sendable, Equatable { // nonisolated: value
	var diagnostics: ConnectionDiagnostics?
	var serverAddress = ""
	var serverPort = ConnectionDefaults.serverPort
	var addressType = ConnectionAddressType.default

	var connectionPrefersSecuredConnection = false
	var connectionPrefersModernCiphersOnly = false
	var connectionShouldValidateCertificateChain = false
	var cipherSuites = CipherSuiteCollection.default
	var identityClientSideCertificate: Data?

	var proxyType = ConnectionProxyType.none
	var proxyAddress: String?
	var proxyPort = ConnectionDefaults.proxyPort
	var proxyUsername: String?
	/// Sent to the connection host so it can authenticate to the proxy.
	var proxyPassword: String?

	var floodControlDelayInterval = ConnectionDefaults.floodControlDelayInterval {
		didSet { floodControlDelayInterval = Self.clampedFloodValue(floodControlDelayInterval, oldValue) }
	}

	var floodControlMaximumMessages = ConnectionDefaults.floodControlMaximumMessages {
		didSet { floodControlMaximumMessages = Self.clampedFloodValue(floodControlMaximumMessages, oldValue) }
	}

	init() {}

	private enum CodingKeys: String, CodingKey {
		case diagnostics
		case serverAddress
		case serverPort
		case addressType
		case connectionPrefersSecuredConnection
		case connectionPrefersModernCiphersOnly
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
		addressType = ConnectionAddressType(
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
		connectionPrefersModernCiphersOnly = container.decode(
			Bool.self,
			forKey: .connectionPrefersModernCiphersOnly,
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
				default: CipherSuiteCollection.default.rawValue
			)
		) ?? .default
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
		try container.encode(connectionPrefersModernCiphersOnly, forKey: .connectionPrefersModernCiphersOnly)
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
	 zero. The flood-control range is the larger point: `init(from:)` assigns
	 inside an initializer, where the `didSet` observers that clamp these two do
	 not run, so whatever the envelope carried survives — and the host narrows
	 the message count to an `Int` on every write, which traps on a `UInt` above
	 `Int.max`. Clamping here is what the observers would have done. */
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
	private static func sanitizedProxyType(_ rawValue: UInt) -> ConnectionProxyType {
		guard let value = ConnectionProxyType(rawValue: rawValue) else {
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
 envelope rather than as a class with a property per setting. */
@objc(RCMConnectionConfigEnvelope)
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

/// A shared monotonic origin correlates app and XPC milestones without recording
/// server names, account names, credentials, or IRC message contents.
nonisolated struct ConnectionDiagnostics: Codable, Sendable, Equatable { // nonisolated: value
	let identifier: UUID
	let requestedAt: TimeInterval

	init() {
		identifier = UUID()
		requestedAt = ProcessInfo.processInfo.systemUptime
	}

	enum Event: String, Codable, Sendable {
		case requested, serviceRequested, hostStarted, transportStarted
		case certificateEvaluationStarted, certificateEvaluationCompleted, certificateAccepted
		case transportReady, transportFailed, capabilitiesCompleted, registered, identificationWritten, authenticated
		case firstJoin, disconnected
	}

	/** One `Logger`, and `debug` rather than `info`.

	 Every milestone here is a timing trace: a dozen of them per connection
	 attempt, useful only when someone is measuring where a connection spends
	 its time. `debug` is the level the unified log keeps out of the persisted
	 store and out of `log show` unless it is asked for, which is what makes the
	 trace free to emit on every attempt. The state a developer or a user acts
	 on — connected, secured, disconnected, failed — is logged by the paths that
	 decide it, at the level that decision deserves. */
	private static let logger = Logger(subsystem: "com.vakesz.glasstual", category: "IRCStartup")

	func record(_ event: Event) {
		let elapsed = ProcessInfo.processInfo.systemUptime - requestedAt
		Self.logger.debug(
			"Attempt \(identifier.uuidString, privacy: .public) \(event.rawValue, privacy: .public) elapsed=\(elapsed, privacy: .public)s"
		)
	}
}
