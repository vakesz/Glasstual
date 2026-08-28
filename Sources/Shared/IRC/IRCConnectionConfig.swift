/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

/// Raw values are persisted. Values 4 and 7 are retired and must not be reused.
@objc
public nonisolated enum IRCConnectionProxyType: UInt {
	case none = 0
	case automatic = 1
	case socks5 = 5
	case HTTP = 6
	case tor = 8
}

/// Controls which IP address families Network.framework may use.
@objc
public nonisolated enum IRCConnectionAddressType: UInt {
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

@objc(IRCConnectionConfig)
@objcMembers
open nonisolated class IRCConnectionConfig: PortablePropertyObject {
	fileprivate var addressTypeStorage = IRCConnectionAddressType.default
	fileprivate var prefersModernCiphersStorage = false
	fileprivate var prefersSecureConnectionStorage = false
	fileprivate var validatesCertificateChainStorage = false
	fileprivate var floodDelayStorage = IRCConnectionDefaults.floodControlDelayInterval
	fileprivate var floodMaximumStorage = IRCConnectionDefaults.floodControlMaximumMessages
	fileprivate var identityCertificateStorage: Data?
	fileprivate var proxyAddressStorage: String?
	fileprivate var proxyPasswordStorage: String?
	fileprivate var proxyPortStorage = IRCConnectionDefaults.proxyPort
	fileprivate var proxyTypeStorage = IRCConnectionProxyType.none
	fileprivate var proxyUsernameStorage: String?
	fileprivate var serverAddressStorage = ""
	fileprivate var serverPortStorage = IRCConnectionDefaults.serverPort
	fileprivate var primaryEncodingStorage: UInt = 0
	fileprivate var fallbackEncodingStorage: UInt = 0
	fileprivate var cipherSuitesStorage = CipherSuiteCollection.default

	open var addressType: IRCConnectionAddressType {
		addressTypeStorage
	}

	open var connectionPrefersModernCiphersOnly: Bool {
		prefersModernCiphersStorage
	}

	open var connectionPrefersSecuredConnection: Bool {
		prefersSecureConnectionStorage
	}

	open var connectionShouldValidateCertificateChain: Bool {
		validatesCertificateChainStorage
	}

	open var floodControlDelayInterval: UInt {
		floodDelayStorage
	}

	open var floodControlMaximumMessages: UInt {
		floodMaximumStorage
	}

	open var identityClientSideCertificate: Data? {
		identityCertificateStorage
	}

	open var proxyAddress: String? {
		proxyAddressStorage
	}

	open var proxyPassword: String? {
		proxyPasswordStorage
	}

	open var proxyPort: UInt16 {
		proxyPortStorage
	}

	open var proxyType: IRCConnectionProxyType {
		proxyTypeStorage
	}

	open var proxyUsername: String? {
		proxyUsernameStorage
	}

	open var serverAddress: String {
		serverAddressStorage
	}

	open var serverPort: UInt16 {
		serverPortStorage
	}

	open var primaryEncoding: UInt {
		primaryEncodingStorage
	}

	open var fallbackEncoding: UInt {
		fallbackEncodingStorage
	}

	open var cipherSuites: CipherSuiteCollection {
		cipherSuitesStorage
	}

	override public required init() {
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override open class var supportsSecureCoding: Bool {
		true
	}

	override open func populate(with decoder: NSCoder) -> Bool {
		addressTypeStorage = IRCConnectionAddressType(rawValue: decoder.decodeUInt(forKey: "addressType")) ?? .default
		prefersModernCiphersStorage = decoder.decodeBool(forKey: "connectionPrefersModernCiphersOnly")
		prefersSecureConnectionStorage = decoder.decodeBool(forKey: "connectionPrefersSecuredConnection")
		validatesCertificateChainStorage = decoder.decodeBool(forKey: "connectionShouldValidateCertificateChain")
		floodDelayStorage = decoder.decodeUInt(forKey: "floodControlDelayInterval")
		floodMaximumStorage = decoder.decodeUInt(forKey: "floodControlMaximumMessages")
		identityCertificateStorage = decoder.decodeObject(
			of: NSData.self,
			forKey: "identityClientSideCertificate"
		) as Data?
		proxyAddressStorage = decoder.decodeObject(of: NSString.self, forKey: "proxyAddress") as String?
		proxyPasswordStorage = decoder.decodeObject(of: NSString.self, forKey: "proxyPassword") as String?
		proxyPortStorage = UInt16(truncatingIfNeeded: decoder.decodeUInt(forKey: "proxyPort"))
		proxyTypeStorage = Self.sanitizedProxyType(decoder.decodeUInt(forKey: "proxyType"))
		proxyUsernameStorage = decoder.decodeObject(of: NSString.self, forKey: "proxyUsername") as String?
		serverAddressStorage = decoder.decodeObject(of: NSString.self, forKey: "serverAddress") as String? ?? ""
		serverPortStorage = UInt16(truncatingIfNeeded: decoder.decodeUInt(forKey: "serverPort"))
		primaryEncodingStorage = decoder.decodeUInt(forKey: "primaryEncoding")
		fallbackEncodingStorage = decoder.decodeUInt(forKey: "fallbackEncoding")
		cipherSuitesStorage = CipherSuiteCollection(rawValue: decoder.decodeUInt(forKey: "cipherSuites")) ?? .default
		applyMissingDefaults()
		return true
	}

	override open func encode(with coder: NSCoder) {
		coder.encode(NSNumber(value: addressType.rawValue), forKey: "addressType")
		coder.encode(connectionPrefersModernCiphersOnly, forKey: "connectionPrefersModernCiphersOnly")
		coder.encode(connectionPrefersSecuredConnection, forKey: "connectionPrefersSecuredConnection")
		coder.encode(connectionShouldValidateCertificateChain, forKey: "connectionShouldValidateCertificateChain")
		coder.encode(NSNumber(value: floodControlDelayInterval), forKey: "floodControlDelayInterval")
		coder.encode(NSNumber(value: floodControlMaximumMessages), forKey: "floodControlMaximumMessages")
		if let identityClientSideCertificate {
			coder.encode(
				identityClientSideCertificate,
				forKey: "identityClientSideCertificate"
			)
		}
		if let proxyAddress {
			coder.encode(proxyAddress, forKey: "proxyAddress")
		}
		if let proxyPassword {
			coder.encode(proxyPassword, forKey: "proxyPassword")
		}
		coder.encode(NSNumber(value: proxyPort), forKey: "proxyPort")
		coder.encode(NSNumber(value: proxyType.rawValue), forKey: "proxyType")
		if let proxyUsername {
			coder.encode(proxyUsername, forKey: "proxyUsername")
		}
		coder.encode(serverAddress, forKey: "serverAddress")
		coder.encode(NSNumber(value: serverPort), forKey: "serverPort")
		coder.encode(NSNumber(value: primaryEncoding), forKey: "primaryEncoding")
		coder.encode(NSNumber(value: fallbackEncoding), forKey: "fallbackEncoding")
		coder.encode(NSNumber(value: cipherSuites.rawValue), forKey: "cipherSuites")
	}

	override open func copy(asMutable mutableCopy: Bool, uniquing _: Bool) -> Any {
		let object = mutableCopy ? IRCConnectionConfigMutable() : IRCConnectionConfig()
		object.addressTypeStorage = addressTypeStorage
		object.prefersModernCiphersStorage = prefersModernCiphersStorage
		object.prefersSecureConnectionStorage = prefersSecureConnectionStorage
		object.validatesCertificateChainStorage = validatesCertificateChainStorage
		object.floodDelayStorage = floodDelayStorage
		object.floodMaximumStorage = floodMaximumStorage
		object.identityCertificateStorage = identityCertificateStorage
		object.proxyAddressStorage = proxyAddressStorage
		object.proxyPasswordStorage = proxyPasswordStorage
		object.proxyPortStorage = proxyPortStorage
		object.proxyTypeStorage = proxyTypeStorage
		object.proxyUsernameStorage = proxyUsernameStorage
		object.serverAddressStorage = serverAddressStorage
		object.serverPortStorage = serverPortStorage
		object.primaryEncodingStorage = primaryEncodingStorage
		object.fallbackEncodingStorage = fallbackEncodingStorage
		object.cipherSuitesStorage = cipherSuitesStorage
		return object
	}

	override open var mutableClass: PortablePropertyObject {
		IRCConnectionConfigMutable()
	}

	private func applyMissingDefaults() {
		if proxyPortStorage == 0 {
			proxyPortStorage = IRCConnectionDefaults.proxyPort
		}
		if serverPortStorage == 0 {
			serverPortStorage = IRCConnectionDefaults.serverPort
		}
		if floodDelayStorage == 0 {
			floodDelayStorage = IRCConnectionDefaults.floodControlDelayInterval
		}
		if floodMaximumStorage == 0 {
			floodMaximumStorage = IRCConnectionDefaults.floodControlMaximumMessages
		}
	}

	private class func sanitizedProxyType(_ rawValue: UInt) -> IRCConnectionProxyType {
		if [0, 1, 5, 6, 8].contains(rawValue), let value = IRCConnectionProxyType(rawValue: rawValue) {
			return value
		}
		Logger(subsystem: "com.vakesz.glasstual", category: "Connection").error(
			"Unsupported proxy type \(rawValue, privacy: .public) in stored configuration; using no proxy"
		)
		return .none
	}
}

private nonisolated extension NSCoder {
	func decodeUInt(forKey key: String) -> UInt {
		decodeObject(of: NSNumber.self, forKey: key)?.uintValue ?? 0
	}
}

@objc(IRCConnectionConfigMutable)
@objcMembers
public final nonisolated class IRCConnectionConfigMutable: IRCConnectionConfig {
	public required init() {
		super.init()
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	override public var addressType: IRCConnectionAddressType {
		get { addressTypeStorage } set { addressTypeStorage = newValue }
	}

	override public var connectionPrefersModernCiphersOnly: Bool {
		get { prefersModernCiphersStorage } set { prefersModernCiphersStorage = newValue }
	}

	override public var connectionPrefersSecuredConnection: Bool {
		get { prefersSecureConnectionStorage } set { prefersSecureConnectionStorage = newValue }
	}

	override public var connectionShouldValidateCertificateChain: Bool {
		get { validatesCertificateChainStorage } set { validatesCertificateChainStorage = newValue }
	}

	override public var floodControlDelayInterval: UInt {
		get { floodDelayStorage } set { precondition((1 ... 60).contains(newValue)); floodDelayStorage = newValue }
	}

	override public var floodControlMaximumMessages: UInt {
		get { floodMaximumStorage } set { precondition((1 ... 60).contains(newValue)); floodMaximumStorage = newValue }
	}

	override public var identityClientSideCertificate: Data? {
		get { identityCertificateStorage } set { identityCertificateStorage = newValue }
	}

	override public var proxyAddress: String? {
		get { proxyAddressStorage } set { proxyAddressStorage = newValue }
	}

	override public var proxyPassword: String? {
		get { proxyPasswordStorage } set { proxyPasswordStorage = newValue }
	}

	override public var proxyPort: UInt16 {
		get { proxyPortStorage } set { proxyPortStorage = newValue }
	}

	override public var proxyType: IRCConnectionProxyType {
		get { proxyTypeStorage } set { proxyTypeStorage = newValue }
	}

	override public var proxyUsername: String? {
		get { proxyUsernameStorage } set { proxyUsernameStorage = newValue }
	}

	override public var serverAddress: String {
		get { serverAddressStorage } set { serverAddressStorage = newValue }
	}

	override public var serverPort: UInt16 {
		get { serverPortStorage } set { serverPortStorage = newValue }
	}

	override public var primaryEncoding: UInt {
		get { primaryEncodingStorage } set { primaryEncodingStorage = newValue }
	}

	override public var fallbackEncoding: UInt {
		get { fallbackEncodingStorage } set { fallbackEncodingStorage = newValue }
	}

	override public var cipherSuites: CipherSuiteCollection {
		get { cipherSuitesStorage } set { cipherSuitesStorage = newValue }
	}

	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		IRCConnectionConfig()
	}
}
