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

private nonisolated let connectionConfigLogger = Logger(
	subsystem: "com.vakesz.glasstual",
	category: "Connection"
)

/// Raw values are persisted. Values 4 and 7 are retired and must not be reused.
@objc
public nonisolated enum IRCConnectionProxyType: UInt, Codable, Sendable {
	case none = 0
	case automatic = 1
	case socks5 = 5
	case HTTP = 6
	case tor = 8
}

/// Controls which IP address families Network.framework may use.
@objc
public nonisolated enum IRCConnectionAddressType: UInt, Codable, Sendable {
	case `default` = 0
	case v4 = 1
	case v6 = 2
}

public nonisolated enum IRCConnectionDefaults {
	public static let serverPort: UInt16 = 6667
	public static let proxyPort: UInt16 = 1080
	public static let floodControlDelayInterval: UInt = 2
	public static let minimumFloodControlDelayInterval: UInt = 1
	public static let maximumFloodControlDelayInterval: UInt = 60
	public static let floodControlMaximumMessages: UInt = 6
	public static let minimumFloodControlMaximumMessages: UInt = 1
	public static let maximumFloodControlMaximumMessages: UInt = 60
}

/** What one socket needs to reach one endpoint.

 This is what the application hands the isolated connection host, so it is a
 value: the host cannot reach back into the application's copy. The proxy
 password travels with it by design — the host is the process that has to
 present it — and it goes no further than that XPC connection. */
public nonisolated struct IRCConnectionConfig: Codable, Sendable, Equatable {
	public var serverAddress = ""
	public var serverPort = IRCConnectionDefaults.serverPort
	public var addressType = IRCConnectionAddressType.default

	public var connectionPrefersSecuredConnection = false
	public var connectionPrefersModernCiphersOnly = false
	public var connectionShouldValidateCertificateChain = false
	public var cipherSuites = CipherSuiteCollection.default
	public var identityClientSideCertificate: Data?

	public var proxyType = IRCConnectionProxyType.none
	public var proxyAddress: String?
	public var proxyPort = IRCConnectionDefaults.proxyPort
	public var proxyUsername: String?
	/// Sent to the connection host so it can authenticate to the proxy.
	public var proxyPassword: String?

	public var floodControlDelayInterval = IRCConnectionDefaults.floodControlDelayInterval {
		didSet { floodControlDelayInterval = Self.clampedFloodValue(floodControlDelayInterval, oldValue) }
	}

	public var floodControlMaximumMessages = IRCConnectionDefaults.floodControlMaximumMessages {
		didSet { floodControlMaximumMessages = Self.clampedFloodValue(floodControlMaximumMessages, oldValue) }
	}

	public var primaryEncoding: UInt = 0
	public var fallbackEncoding: UInt = 0

	public init() {}

	private enum CodingKeys: String, CodingKey {
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
		case primaryEncoding
		case fallbackEncoding
	}

	public init(from decoder: any Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		self.init()

		serverAddress = container.decode(String.self, forKey: .serverAddress, aliases: [], default: "")
		serverPort = container.decode(
			UInt16.self,
			forKey: .serverPort,
			aliases: [],
			default: IRCConnectionDefaults.serverPort
		)
		addressType = IRCConnectionAddressType(
			rawValue: container.decode(UInt.self, forKey: .addressType, aliases: [], default: 0)
		) ?? .default

		decodeSecurity(from: container)
		decodeProxy(from: container)

		floodControlDelayInterval = container.decode(
			UInt.self,
			forKey: .floodControlDelayInterval,
			aliases: [],
			default: IRCConnectionDefaults.floodControlDelayInterval
		)
		floodControlMaximumMessages = container.decode(
			UInt.self,
			forKey: .floodControlMaximumMessages,
			aliases: [],
			default: IRCConnectionDefaults.floodControlMaximumMessages
		)
		primaryEncoding = container.decode(UInt.self, forKey: .primaryEncoding, aliases: [], default: 0)
		fallbackEncoding = container.decode(UInt.self, forKey: .fallbackEncoding, aliases: [], default: 0)

		applyMissingDefaults()
	}

	private mutating func decodeSecurity(from container: KeyedDecodingContainer<CodingKeys>) {
		connectionPrefersSecuredConnection = container.decode(
			Bool.self,
			forKey: .connectionPrefersSecuredConnection,
			aliases: [],
			default: false
		)
		connectionPrefersModernCiphersOnly = container.decode(
			Bool.self,
			forKey: .connectionPrefersModernCiphersOnly,
			aliases: [],
			default: false
		)
		connectionShouldValidateCertificateChain = container.decode(
			Bool.self,
			forKey: .connectionShouldValidateCertificateChain,
			aliases: [],
			default: false
		)
		cipherSuites = CipherSuiteCollection(
			rawValue: container.decode(
				UInt.self,
				forKey: .cipherSuites,
				aliases: [],
				default: CipherSuiteCollection.default.rawValue
			)
		) ?? .default
		identityClientSideCertificate = container.decodeOptional(
			Data.self,
			forKey: .identityClientSideCertificate
		)
	}

	private mutating func decodeProxy(from container: KeyedDecodingContainer<CodingKeys>) {
		let rawProxyType = container.decode(UInt.self, forKey: .proxyType, aliases: [], default: 0)
		proxyType = Self.sanitizedProxyType(rawProxyType)
		proxyAddress = container.decodeOptional(String.self, forKey: .proxyAddress)
		proxyPort = container.decode(
			UInt16.self,
			forKey: .proxyPort,
			aliases: [],
			default: IRCConnectionDefaults.proxyPort
		)
		proxyUsername = container.decodeOptional(String.self, forKey: .proxyUsername)
		proxyPassword = container.decodeOptional(String.self, forKey: .proxyPassword)
	}

	public func encode(to encoder: any Encoder) throws {
		var container = encoder.container(keyedBy: CodingKeys.self)

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
		try container.encode(primaryEncoding, forKey: .primaryEncoding)
		try container.encode(fallbackEncoding, forKey: .fallbackEncoding)
	}

	/// A zero for any of these means the sender left it out, not that it wanted
	/// a port of zero or a flood window of nothing.
	private mutating func applyMissingDefaults() {
		if proxyPort == 0 {
			proxyPort = IRCConnectionDefaults.proxyPort
		}

		if serverPort == 0 {
			serverPort = IRCConnectionDefaults.serverPort
		}

		if floodControlDelayInterval == 0 {
			floodControlDelayInterval = IRCConnectionDefaults.floodControlDelayInterval
		}

		if floodControlMaximumMessages == 0 {
			floodControlMaximumMessages = IRCConnectionDefaults.floodControlMaximumMessages
		}
	}

	/** A value outside the supported set means a configuration written by a
	 build that offered a proxy this one does not; refusing the proxy is safer
	 than guessing at one. */
	private static func sanitizedProxyType(_ rawValue: UInt) -> IRCConnectionProxyType {
		guard let value = IRCConnectionProxyType(rawValue: rawValue) else {
			connectionConfigLogger.error(
				"Unsupported proxy type \(rawValue, privacy: .public) in stored configuration; using no proxy"
			)

			return .none
		}

		return value
	}

	/// Flood-control values outside 1...60 used to trip a `precondition`; an
	/// out-of-range value is now clamped back to the last good one.
	private static func clampedFloodValue(_ value: UInt, _ previous: UInt) -> UInt {
		(1 ... 60).contains(value) ? value : previous
	}
}

/** Carries an `IRCConnectionConfig` across the XPC boundary.

 `NSXPCConnection` speaks `NSSecureCoding`, which a value type cannot conform
 to, so the encoded configuration travels as one `Data` blob inside this
 envelope rather than as a class with a property per setting. */
@objc(RCMConnectionConfigEnvelope)
public final nonisolated class ConnectionConfigEnvelope: NSObject, NSSecureCoding {
	public let config: IRCConnectionConfig

	public init(config: IRCConnectionConfig) {
		self.config = config

		super.init()
	}

	public static var supportsSecureCoding: Bool {
		true
	}

	public init?(coder: NSCoder) {
		guard let data = coder.decodeObject(of: NSData.self, forKey: "config") as Data?,
		      let config = try? PropertyListDecoder().decode(IRCConnectionConfig.self, from: data)
		else {
			connectionConfigLogger.error("Received a connection configuration that could not be read")

			return nil
		}

		self.config = config

		super.init()
	}

	public func encode(with coder: NSCoder) {
		let encoder = PropertyListEncoder()
		encoder.outputFormat = .binary

		guard let data = try? encoder.encode(config) else {
			connectionConfigLogger.error("Could not write a connection configuration for the connection host")

			return
		}

		coder.encode(data, forKey: "config")
	}
}
