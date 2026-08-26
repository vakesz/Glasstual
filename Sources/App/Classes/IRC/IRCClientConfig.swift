/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import Foundation
import os

private enum ClientConfigDefaults {
	static let dictionaryVersion: UInt = 710
	static let proxyPort: UInt16 = 1080
	static let serverPort: UInt16 = 6667
	static let floodDelay: UInt = 2
	static let floodMaximum: UInt = 6
	static let limitedFloodDelay: UInt = 2
	static let limitedFloodMaximum: UInt = 2
	static let minimumFloodDelay: UInt = 1
	static let maximumFloodDelay: UInt = 60
	static let minimumFloodMessages: UInt = 1
	static let maximumFloodMessages: UInt = 60
}

@objc(IRCClientConfig)
open class ClientConfig: XRPortablePropertyDict {
	fileprivate var autoConnectStorage = false
	fileprivate var autoReconnectStorage = false
	fileprivate var autoSleepModeDisconnectStorage = true
	fileprivate var autojoinWaitsForNickServStorage = false
	fileprivate var connectionPrefersIPv4Storage = false
	fileprivate var hideAutojoinDelayedWarningsStorage = false
	fileprivate var hideNetworkUnavailabilityNoticesStorage = false
	fileprivate var performDisconnectOnPongTimerStorage = false
	fileprivate var performDisconnectOnReachabilityChangeStorage = true
	fileprivate var performPongTimerStorage = true
	fileprivate var prefersSecuredConnectionStorage = false
	fileprivate var saslAuthenticationDisableExternalMechanismStorage = false
	fileprivate var sendAuthenticationRequestsToUserServStorage = false
	fileprivate var sendWhoCommandRequestsToChannelsStorage = true
	fileprivate var setInvisibleModeOnConnectStorage = false
	fileprivate var runConnectCommandsSilentlyStorage = true
	fileprivate var sidebarItemExpandedStorage = true
	fileprivate var validateServerCertificateChainStorage = true
	fileprivate var zncIgnoreConfiguredAutojoinStorage = false
	fileprivate var zncIgnorePlaybackNotificationsStorage = true
	fileprivate var zncIgnoreUserNotificationsStorage = false
	fileprivate var zncOnlyPlaybackLatestStorage = true
	fileprivate var addressTypeStorage = IRCConnectionAddressType.default
	fileprivate var proxyTypeStorage = IRCConnectionProxyType.automatic
	fileprivate var fallbackEncodingStorage = String.Encoding.isoLatin1.rawValue
	fileprivate var primaryEncodingStorage = String.Encoding.utf8.rawValue
	fileprivate var lastMessageServerTimeStorage: TimeInterval = 0
	fileprivate var floodControlDelayTimerIntervalStorage = ClientConfigDefaults.floodDelay
	fileprivate var floodControlMaximumMessagesStorage = ClientConfigDefaults.floodMaximum
	fileprivate var proxyPortStorage = ClientConfigDefaults.proxyPort
	fileprivate var channelListStorage: [ChannelConfig] = []
	fileprivate var highlightListStorage: [HighlightMatchCondition] = []
	fileprivate var ignoreListStorage: [AddressBookEntry] = []
	fileprivate var alternateNicknamesStorage: [String] = []
	fileprivate var loginCommandsStorage: [String] = []
	fileprivate var serverListStorage: [Server] = []
	fileprivate var connectionNameStorage = ""
	fileprivate var nicknameStorage = ""
	fileprivate var normalLeavingCommentStorage = ""
	fileprivate var realNameStorage = ""
	fileprivate var sleepModeLeavingCommentStorage = ""
	fileprivate var uniqueIdentifierStorage = ""
	fileprivate var usernameStorage = ""
	fileprivate var identityClientSideCertificateStorage: Data?
	fileprivate var awayNicknameStorage: String?
	fileprivate var saslMechanismPreferenceStorage: String?
	fileprivate var ctcpVersionReplyStorage: String?
	fileprivate var nicknamePasswordStorage: String?
	fileprivate var proxyAddressStorage: String?
	fileprivate var proxyPasswordStorage: String?
	fileprivate var proxyUsernameStorage: String?
	fileprivate var cipherSuitesStorage = RCMCipherSuiteCollection.default

	private var nicknamePasswordKeychainCache: String?
	private var nicknamePasswordKeychainCacheIsValid = false
	private var migratedServerPasswordPendingDestroy = false
	private var dictionaryVersionStorage: UInt = 0
	private var defaultsStorage: [String: Any] = [:]
	private var legacyServerAddressStorage: String?
	private var legacyServerPortStorage = ClientConfigDefaults.serverPort

	@objc public var autoConnect: Bool {
		autoConnectStorage
	}

	@objc public var autoReconnect: Bool {
		autoReconnectStorage
	}

	@objc public var autoSleepModeDisconnect: Bool {
		autoSleepModeDisconnectStorage
	}

	@objc public var autojoinWaitsForNickServ: Bool {
		autojoinWaitsForNickServStorage
	}

	@objc public var hideAutojoinDelayedWarnings: Bool {
		hideAutojoinDelayedWarningsStorage
	}

	@objc public var hideNetworkUnavailabilityNotices: Bool {
		hideNetworkUnavailabilityNoticesStorage
	}

	@objc public var performDisconnectOnPongTimer: Bool {
		performDisconnectOnPongTimerStorage
	}

	@objc public var performDisconnectOnReachabilityChange: Bool {
		performDisconnectOnReachabilityChangeStorage
	}

	@objc public var performPongTimer: Bool {
		performPongTimerStorage
	}

	@objc public var saslAuthenticationDisableExternalMechanism: Bool {
		saslAuthenticationDisableExternalMechanismStorage
	}

	@objc public var sendAuthenticationRequestsToUserServ: Bool {
		sendAuthenticationRequestsToUserServStorage
	}

	@objc public var sendWhoCommandRequestsToChannels: Bool {
		sendWhoCommandRequestsToChannelsStorage
	}

	@objc public var setInvisibleModeOnConnect: Bool {
		setInvisibleModeOnConnectStorage
	}

	@objc public var runConnectCommandsSilently: Bool {
		runConnectCommandsSilentlyStorage
	}

	@objc public var sidebarItemExpanded: Bool {
		sidebarItemExpandedStorage
	}

	@objc public var validateServerCertificateChain: Bool {
		validateServerCertificateChainStorage
	}

	@objc public var zncIgnoreConfiguredAutojoin: Bool {
		zncIgnoreConfiguredAutojoinStorage
	}

	@objc public var zncIgnorePlaybackNotifications: Bool {
		zncIgnorePlaybackNotificationsStorage
	}

	@objc public var zncIgnoreUserNotifications: Bool {
		zncIgnoreUserNotificationsStorage
	}

	@objc public var zncOnlyPlaybackLatest: Bool {
		zncOnlyPlaybackLatestStorage
	}

	@objc public var addressType: IRCConnectionAddressType {
		addressTypeStorage
	}

	@objc public var proxyType: IRCConnectionProxyType {
		proxyTypeStorage
	}

	@objc public var fallbackEncoding: UInt {
		fallbackEncodingStorage
	}

	@objc public var primaryEncoding: UInt {
		primaryEncodingStorage
	}

	@objc public var lastMessageServerTime: TimeInterval {
		lastMessageServerTimeStorage
	}

	@objc public var floodControlDelayTimerInterval: UInt {
		floodControlDelayTimerIntervalStorage
	}

	@objc public var floodControlMaximumMessages: UInt {
		floodControlMaximumMessagesStorage
	}

	@objc public var proxyPort: UInt16 {
		proxyPortStorage
	}

	@objc public var channelList: [ChannelConfig] {
		channelListStorage
	}

	@objc public var highlightList: [HighlightMatchCondition] {
		highlightListStorage
	}

	@objc public var ignoreList: [AddressBookEntry] {
		ignoreListStorage
	}

	@objc public var alternateNicknames: [String] {
		alternateNicknamesStorage
	}

	@objc public var loginCommands: [String] {
		loginCommandsStorage
	}

	@objc public var serverList: [Server] {
		serverListStorage
	}

	@objc public var connectionName: String {
		connectionNameStorage
	}

	@objc public var nickname: String {
		nicknameStorage
	}

	@objc public var normalLeavingComment: String {
		normalLeavingCommentStorage
	}

	@objc public var realName: String {
		realNameStorage
	}

	@objc public var sleepModeLeavingComment: String {
		sleepModeLeavingCommentStorage
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var username: String {
		usernameStorage
	}

	@objc public var identityClientSideCertificate: Data? {
		identityClientSideCertificateStorage
	}

	@objc public var awayNickname: String? {
		awayNicknameStorage
	}

	@objc public var saslMechanismPreference: String? {
		saslMechanismPreferenceStorage
	}

	@objc public var ctcpVersionReply: String? {
		ctcpVersionReplyStorage
	}

	@objc public var proxyAddress: String? {
		proxyAddressStorage
	}

	@objc public var proxyUsername: String? {
		proxyUsernameStorage
	}

	@objc public var cipherSuites: RCMCipherSuiteCollection {
		cipherSuitesStorage
	}

	@objc public var connectionPrefersIPv4: Bool {
		connectionPrefersIPv4Storage
	}

	@objc public var nicknamePassword: String? {
		if let nicknamePasswordStorage {
			return nicknamePasswordStorage
		}

		if nicknamePasswordKeychainCacheIsValid {
			return nicknamePasswordKeychainCache
		}

		let password = nicknamePasswordFromKeychain
		nicknamePasswordKeychainCache = password
		nicknamePasswordKeychainCacheIsValid = true
		return password
	}

	@objc public var nicknamePasswordFromKeychain: String? {
		XRKeychain.getPasswordFromKeychainItem(
			"Glasstual (NickServ)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.nickserv.\(uniqueIdentifierStorage)"
		)
	}

	@objc public var proxyPassword: String? {
		proxyPasswordStorage ?? proxyPasswordFromKeychain
	}

	@objc public var proxyPasswordFromKeychain: String? {
		XRKeychain.getPasswordFromKeychainItem(
			"Glasstual (Proxy Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.proxy-server.\(uniqueIdentifierStorage)"
		)
	}

	@objc public var showConnectionPrefersIPv4Warning: Bool {
		addressTypeStorage == .v4 && connectionPrefersIPv4Storage
	}

	override public init() {
		super.init()
		initialize(with: [:], ignorePrivateMessages: false)
	}

	@objc(initWithDictionary:)
	override public init(dictionary: [String: Any]) {
		super.init()
		initialize(with: dictionary, ignorePrivateMessages: false)
	}

	@objc(initWithDictionary:ignorePrivateMessages:)
	public init(dictionary: [String: Any], ignorePrivateMessages: Bool) {
		super.init()
		initialize(with: dictionary, ignorePrivateMessages: ignorePrivateMessages)
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	@objc(newConfigByMerging:with:)
	public class func newConfigByMerging(_ first: ClientConfig, with second: ClientConfig) -> Self {
		let merged = first.mutableCopy() as! MutableClientConfig
		merged.populateDictionaryValues(
			second.dictionaryValue,
			ignorePrivateMessages: false,
			applyDefaults: false,
			bypassCopyCheck: true
		)

		if isMutable {
			return unsafeDowncast(merged, to: Self.self)
		}

		return unsafeDowncast(merged.copy() as AnyObject, to: Self.self)
	}

	@objc(newConfigWithNetwork:)
	public class func newConfig(with network: IRCNetwork) -> Self {
		let config = MutableClientConfig()
		config.connectionName = network.networkName

		let server = MutableServer()
		server.serverAddress = network.serverAddress
		server.serverPort = network.serverPort
		server.prefersSecuredConnection = network.prefersSecuredConnection
		config.serverList = [server.copy() as! Server]

		if isMutable {
			return unsafeDowncast(config, to: Self.self)
		}

		return unsafeDowncast(config.copy() as AnyObject, to: Self.self)
	}

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if proxyPortStorage == 0 {
			proxyPortStorage = ClientConfigDefaults.proxyPort
		}

		if isMutable || initializedAsCopy {
			return
		}

		precondition(connectionNameStorage.isEmpty == false)
	}

	@objc(populateDefaultsPreflight)
	override public func populateDefaultsPreflight() {
		guard initializedAsCopy == false else {
			return
		}

		defaultsStorage = [
			"addressType": IRCConnectionAddressType.default.rawValue,
			"autoConnect": false,
			"autoReconnect": false,
			"autoSleepModeDisconnect": true,
			"autojoinWaitsForNickServ": false,
			"cachedLastServerTimeCapabilityReceivedAtTimestamp": 0,
			"cipherSuites": RCMCipherSuiteCollection.default.rawValue,
			"connectionName": LocalizedKey("BasicLanguage[vfu-c0]"),
			"fallbackEncoding": String.Encoding.isoLatin1.rawValue,
			"floodControlDelayTimerInterval": ClientConfigDefaults.floodDelay,
			"floodControlMaximumMessages": ClientConfigDefaults.floodMaximum,
			"hideAutojoinDelayedWarnings": false,
			"hideNetworkUnavailabilityNotices": false,
			"normalLeavingComment": LocalizedKey("BasicLanguage[1dd-0f]"),
			"performDisconnectOnPongTimer": false,
			"performDisconnectOnReachabilityChange": true,
			"performPongTimer": true,
			"prefersSecuredConnection": false,
			"primaryEncoding": String.Encoding.utf8.rawValue,
			"proxyPort": ClientConfigDefaults.proxyPort,
			"proxyType": IRCConnectionProxyType.automatic.rawValue,
			"saslAuthenticationDisableExternalMechanism": false,
			"sendAuthenticationRequestsToUserServ": false,
			"sendWhoCommandRequestsToChannels": true,
			"serverPort": ClientConfigDefaults.serverPort,
			"setInvisibleModeOnConnect": false,
			"runConnectCommandsSilently": true,
			"sidebarItemExpanded": true,
			"sleepModeLeavingComment": LocalizedKey("BasicLanguage[qi7-5y]"),
			"validateServerCertificateChain": true,
			"zncIgnoreConfiguredAutojoin": false,
			"zncIgnorePlaybackNotifications": true,
			"zncIgnoreUserNotifications": false,
			"zncOnlyPlaybackLatest": true,
		]
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		guard initializedAsCopy == false else {
			return
		}

		if uniqueIdentifierStorage.isEmpty {
			uniqueIdentifierStorage = NSString.withUUID()
		}
		if nicknameStorage.isEmpty {
			nicknameStorage = TPCPreferences.defaultNickname()
		}
		if awayNicknameStorage == nil {
			awayNicknameStorage = TPCPreferences.defaultAwayNickname()
		}
		if usernameStorage.isEmpty {
			usernameStorage = TPCPreferences.defaultUsername()
		}
		if realNameStorage.isEmpty {
			realNameStorage = TPCPreferences.defaultRealName()
		}
		modifyFloodControlDefaults()
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dictionary: [String: Any]) {
		populateDictionaryValues(
			dictionary,
			ignorePrivateMessages: false,
			applyDefaults: true,
			bypassCopyCheck: false
		)
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let object = object as? ClientConfig else {
			return false
		}

		if self === object {
			return true
		}

		return NSDictionary(dictionary: dictionaryValue).isEqual(to: object.dictionaryValue)
			&& nicknamePasswordStorage == object.nicknamePasswordStorage
			&& proxyPasswordStorage == object.proxyPasswordStorage
	}

	override public var hash: Int {
		uniqueIdentifierStorage.hashValue
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let config = super.copy(asMutable: mutableCopy, uniquing: false) as! ClientConfig
		config.nicknamePasswordStorage = nicknamePasswordStorage
		config.proxyPasswordStorage = proxyPasswordStorage
		config.defaultsStorage = defaultsStorage
		config.migratedServerPasswordPendingDestroy = migratedServerPasswordPendingDestroy

		if uniquing {
			config.channelListStorage = channelListStorage.map { $0.uniqueCopy() as! ChannelConfig }
			config.highlightListStorage = highlightListStorage.map { $0.uniqueCopy() as! HighlightMatchCondition }
			config.ignoreListStorage = ignoreListStorage.map { $0.uniqueCopy() as! AddressBookEntry }
			config.serverListStorage = serverListStorage.map { $0.uniqueCopy() as! Server }
			config.uniqueIdentifierStorage = NSString.withUUID()
		} else {
			config.channelListStorage = channelListStorage
			config.highlightListStorage = highlightListStorage
			config.ignoreListStorage = ignoreListStorage
			config.serverListStorage = serverListStorage
		}

		return config
	}

	override public var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableClientConfig.self, to: XRPortablePropertyDict.self)
	}

	override public func dictionaryValue(for target: XRPortablePropertyDictTarget) -> [String: Any] {
		let dictionary = NSMutableDictionary()
		dictionary.setUnsignedInteger(dictionaryVersionStorage, forKey: "dictionaryVersion")
		dictionary.maybeSetObject(alternateNicknamesStorage, forKey: "alternateNicknames")
		dictionary.maybeSetObject(awayNicknameStorage, forKey: "awayNickname")
		dictionary.maybeSetObject(saslMechanismPreferenceStorage, forKey: "saslMechanismPreference")
		dictionary.maybeSetObject(connectionNameStorage, forKey: "connectionName")
		dictionary.maybeSetObject(ctcpVersionReplyStorage, forKey: "ctcpVersionReply")
		dictionary.maybeSetObject(loginCommandsStorage, forKey: "onConnectCommands")
		dictionary.maybeSetObject(nicknameStorage, forKey: "nickname")
		dictionary.maybeSetObject(normalLeavingCommentStorage, forKey: "normalLeavingComment")
		dictionary.maybeSetObject(proxyAddressStorage, forKey: "proxyAddress")
		dictionary.maybeSetObject(proxyUsernameStorage, forKey: "proxyUsername")
		dictionary.maybeSetObject(realNameStorage, forKey: "realName")
		dictionary.maybeSetObject(sleepModeLeavingCommentStorage, forKey: "sleepModeLeavingComment")
		dictionary.maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dictionary.maybeSetObject(usernameStorage, forKey: "username")

		let boolValues: [String: Bool] = [
			"autoConnect": autoConnectStorage,
			"autoReconnect": autoReconnectStorage,
			"autoSleepModeDisconnect": autoSleepModeDisconnectStorage,
			"autojoinWaitsForNickServ": autojoinWaitsForNickServStorage,
			"hideAutojoinDelayedWarnings": hideAutojoinDelayedWarningsStorage,
			"hideNetworkUnavailabilityNotices": hideNetworkUnavailabilityNoticesStorage,
			"performDisconnectOnPongTimer": performDisconnectOnPongTimerStorage,
			"performDisconnectOnReachabilityChange": performDisconnectOnReachabilityChangeStorage,
			"performPongTimer": performPongTimerStorage,
			"saslAuthenticationDisableExternalMechanism": saslAuthenticationDisableExternalMechanismStorage,
			"sendAuthenticationRequestsToUserServ": sendAuthenticationRequestsToUserServStorage,
			"sendWhoCommandRequestsToChannels": sendWhoCommandRequestsToChannelsStorage,
			"setInvisibleModeOnConnect": setInvisibleModeOnConnectStorage,
			"runConnectCommandsSilently": runConnectCommandsSilentlyStorage,
			"validateServerCertificateChain": validateServerCertificateChainStorage,
			"zncIgnoreConfiguredAutojoin": zncIgnoreConfiguredAutojoinStorage,
			"zncIgnorePlaybackNotifications": zncIgnorePlaybackNotificationsStorage,
			"zncIgnoreUserNotifications": zncIgnoreUserNotificationsStorage,
			"zncOnlyPlaybackLatest": zncOnlyPlaybackLatestStorage,
		]
		for (key, value) in boolValues {
			dictionary.setBool(value, forKey: key)
		}

		dictionary.setUnsignedInteger(addressTypeStorage.rawValue, forKey: "addressType")
		dictionary.setUnsignedInteger(cipherSuitesStorage.rawValue, forKey: "cipherSuites")
		dictionary.setUnsignedInteger(fallbackEncodingStorage, forKey: "fallbackEncoding")
		dictionary.setUnsignedInteger(floodControlDelayTimerIntervalStorage, forKey: "floodControlDelayTimerInterval")
		dictionary.setUnsignedInteger(floodControlMaximumMessagesStorage, forKey: "floodControlMaximumMessages")
		dictionary.setUnsignedInteger(primaryEncodingStorage, forKey: "primaryEncoding")
		dictionary.setUnsignedInteger(proxyTypeStorage.rawValue, forKey: "proxyType")
		dictionary.setUnsignedShort(proxyPortStorage, forKey: "proxyPort")
		dictionary.maybeSetObject(identityClientSideCertificateStorage, forKey: "identityClientSideCertificate")
		dictionary.setBool(sidebarItemExpandedStorage, forKey: "sidebarItemExpanded")
		dictionary.setDouble(lastMessageServerTimeStorage, forKey: "cachedLastServerTimeCapabilityReceivedAtTimestamp")

		dictionary.setBool(connectionPrefersIPv4Storage, forKey: "connectionPrefersIPv4")
		dictionary.setBool(cipherSuitesStorage != .none, forKey: "connectionPrefersModernCiphers")
		dictionary.maybeSetObject(legacyServerAddress, forKey: "serverAddress")
		dictionary.setBool(legacyPrefersSecuredConnection, forKey: "prefersSecuredConnection")
		dictionary.setUnsignedShort(legacyServerPort, forKey: "serverPort")

		if target == .copy || target == .mutableCopy {
			return dictionary as! [String: Any]
		}

		setSerialized(channelListStorage, on: dictionary, key: "channelList")
		setSerialized(highlightListStorage, on: dictionary, key: "highlightList")
		setSerialized(ignoreListStorage, on: dictionary, key: "ignoreList")
		setSerialized(serverListStorage, on: dictionary, key: "serverList")

		return dictionary.removingDefaults(defaultsStorage, allowEmptyValues: true) as! [String: Any]
	}

	@objc open func writeNicknamePasswordToKeychain() {
		guard let nicknamePasswordStorage else { return }

		XRKeychain.modifyOrAddItem(
			"Glasstual (NickServ)",
			withItemKind: "application password",
			forUsername: nil,
			withNewPassword: nicknamePasswordStorage,
			serviceName: "glasstual.nickserv.\(uniqueIdentifierStorage)"
		)
		self.nicknamePasswordStorage = nil
		invalidateNicknamePasswordKeychainCache()
	}

	@objc open func writeProxyPasswordToKeychain() {
		guard let proxyPasswordStorage else { return }

		XRKeychain.modifyOrAddItem(
			"Glasstual (Proxy Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			withNewPassword: proxyPasswordStorage,
			serviceName: "glasstual.proxy-server.\(uniqueIdentifierStorage)"
		)
		self.proxyPasswordStorage = nil
	}

	@objc public func destroyNicknamePasswordKeychainItem() {
		XRKeychain.deleteItem(
			"Glasstual (NickServ)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.nickserv.\(uniqueIdentifierStorage)"
		)
		nicknamePasswordStorage = nil
		invalidateNicknamePasswordKeychainCache()
	}

	@objc public func destroyProxyPasswordKeychainItem() {
		XRKeychain.deleteItem(
			"Glasstual (Proxy Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.proxy-server.\(uniqueIdentifierStorage)"
		)
		proxyPasswordStorage = nil
	}

	@objc public func destroyServerPasswordKeychainItemAfterMigration() {
		guard migratedServerPasswordPendingDestroy else { return }
		migratedServerPasswordPendingDestroy = false
		XRKeychain.deleteItem(
			"Glasstual (Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.server.\(uniqueIdentifierStorage)"
		)
	}

	private var legacyServerAddress: String? {
		serverListStorage.first?.serverAddress ?? legacyServerAddressStorage
	}

	private var legacyServerPort: UInt16 {
		serverListStorage.first?.serverPort ?? legacyServerPortStorage
	}

	private var legacyPrefersSecuredConnection: Bool {
		serverListStorage.first?.prefersSecuredConnection ?? prefersSecuredConnectionStorage
	}

	private func initialize(with dictionary: [String: Any], ignorePrivateMessages: Bool) {
		populateDefaultsPreflight()
		populateDictionaryValues(
			dictionary,
			ignorePrivateMessages: ignorePrivateMessages,
			applyDefaults: true,
			bypassCopyCheck: false
		)
		populateDefaultsPostflight()
		initializedClassHealthCheck()
	}

	private func populateDictionaryValues(
		_ dictionary: [String: Any],
		ignorePrivateMessages: Bool,
		applyDefaults: Bool,
		bypassCopyCheck: Bool
	) {
		var values = applyDefaults ? defaultsStorage : [:]
		values.merge(dictionary) { _, replacement in replacement }

		dictionaryVersionStorage = uintValue(values["dictionaryVersion"])
		alternateNicknamesStorage = values["alternateNicknames"] as? [String] ?? alternateNicknamesStorage
		loginCommandsStorage = values["onConnectCommands"] as? [String] ?? loginCommandsStorage

		assignBoolValues(from: values)
		lastMessageServerTimeStorage = doubleValue(values["cachedLastServerTimeCapabilityReceivedAtTimestamp"])
		identityClientSideCertificateStorage = values["identityClientSideCertificate"] as? Data
		awayNicknameStorage = values["awayNickname"] as? String
		saslMechanismPreferenceStorage = values["saslMechanismPreference"] as? String
		connectionNameStorage = values["connectionName"] as? String ?? connectionNameStorage
		ctcpVersionReplyStorage = values["ctcpVersionReply"] as? String
		nicknameStorage = values["nickname"] as? String ?? nicknameStorage
		normalLeavingCommentStorage = values["normalLeavingComment"] as? String ?? normalLeavingCommentStorage
		proxyAddressStorage = values["proxyAddress"] as? String
		proxyUsernameStorage = values["proxyUsername"] as? String
		realNameStorage = values["realName"] as? String ?? realNameStorage
		legacyServerAddressStorage = values["serverAddress"] as? String
		sleepModeLeavingCommentStorage = values["sleepModeLeavingComment"] as? String ?? sleepModeLeavingCommentStorage
		uniqueIdentifierStorage = values["uniqueIdentifier"] as? String ?? uniqueIdentifierStorage
		usernameStorage = values["username"] as? String ?? usernameStorage

		addressTypeStorage = IRCConnectionAddressType(rawValue: uintValue(values["addressType"])) ?? addressTypeStorage
		cipherSuitesStorage = RCMCipherSuiteCollection(rawValue: uintValue(values["cipherSuites"])) ??
			cipherSuitesStorage
		fallbackEncodingStorage = uintValue(values["fallbackEncoding"], fallback: fallbackEncodingStorage)
		floodControlDelayTimerIntervalStorage = uintValue(
			values["floodControlDelayTimerInterval"],
			fallback: floodControlDelayTimerIntervalStorage
		)
		floodControlMaximumMessagesStorage = uintValue(
			values["floodControlMaximumMessages"],
			fallback: floodControlMaximumMessagesStorage
		)
		primaryEncodingStorage = uintValue(values["primaryEncoding"], fallback: primaryEncodingStorage)
		proxyTypeStorage = IRCConnectionProxyType(rawValue: uintValue(values["proxyType"])) ?? proxyTypeStorage
		proxyPortStorage = uint16Value(values["proxyPort"], fallback: proxyPortStorage)
		legacyServerPortStorage = uint16Value(values["serverPort"], fallback: legacyServerPortStorage)
		connectionPrefersIPv4Storage = boolValue(
			values["connectionPrefersIPv4"],
			fallback: connectionPrefersIPv4Storage
		)

		if initializedAsCopy, bypassCopyCheck == false {
			return
		}

		channelListStorage = dictionaries(values["channelList"]).compactMap { entry in
			let config = ChannelConfig(dictionary: entry)
			return ignorePrivateMessages && config.type == .privateMessage ? nil : config
		}
		ignoreListStorage = dictionaries(values["ignoreList"]).map(AddressBookEntry.init(dictionary:))
		highlightListStorage = dictionaries(values["highlightList"]).map(HighlightMatchCondition.init(dictionary:))
		serverListStorage = dictionaries(values["serverList"]).map(Server.init(dictionary:))

		guard dictionaryVersionStorage != ClientConfigDefaults.dictionaryVersion else {
			return
		}

		if connectionPrefersIPv4Storage {
			addressTypeStorage = .v4
		}

		if dictionaryVersionStorage == 0 {
			migrateLegacyDictionary(dictionary, values: values)
		}

		dictionaryVersionStorage = ClientConfigDefaults.dictionaryVersion
	}

	private func assignBoolValues(from values: [String: Any]) {
		autoConnectStorage = boolValue(values["autoConnect"], fallback: autoConnectStorage)
		autoReconnectStorage = boolValue(values["autoReconnect"], fallback: autoReconnectStorage)
		autoSleepModeDisconnectStorage = boolValue(
			values["autoSleepModeDisconnect"],
			fallback: autoSleepModeDisconnectStorage
		)
		autojoinWaitsForNickServStorage = boolValue(
			values["autojoinWaitsForNickServ"],
			fallback: autojoinWaitsForNickServStorage
		)
		hideAutojoinDelayedWarningsStorage = boolValue(
			values["hideAutojoinDelayedWarnings"],
			fallback: hideAutojoinDelayedWarningsStorage
		)
		hideNetworkUnavailabilityNoticesStorage = boolValue(
			values["hideNetworkUnavailabilityNotices"],
			fallback: hideNetworkUnavailabilityNoticesStorage
		)
		performDisconnectOnPongTimerStorage = boolValue(
			values["performDisconnectOnPongTimer"],
			fallback: performDisconnectOnPongTimerStorage
		)
		performDisconnectOnReachabilityChangeStorage = boolValue(
			values["performDisconnectOnReachabilityChange"],
			fallback: performDisconnectOnReachabilityChangeStorage
		)
		performPongTimerStorage = boolValue(values["performPongTimer"], fallback: performPongTimerStorage)
		prefersSecuredConnectionStorage = boolValue(
			values["prefersSecuredConnection"],
			fallback: prefersSecuredConnectionStorage
		)
		saslAuthenticationDisableExternalMechanismStorage = boolValue(
			values["saslAuthenticationDisableExternalMechanism"],
			fallback: saslAuthenticationDisableExternalMechanismStorage
		)
		sendAuthenticationRequestsToUserServStorage = boolValue(
			values["sendAuthenticationRequestsToUserServ"],
			fallback: sendAuthenticationRequestsToUserServStorage
		)
		sendWhoCommandRequestsToChannelsStorage = boolValue(
			values["sendWhoCommandRequestsToChannels"],
			fallback: sendWhoCommandRequestsToChannelsStorage
		)
		setInvisibleModeOnConnectStorage = boolValue(
			values["setInvisibleModeOnConnect"],
			fallback: setInvisibleModeOnConnectStorage
		)
		runConnectCommandsSilentlyStorage = boolValue(
			values["runConnectCommandsSilently"],
			fallback: runConnectCommandsSilentlyStorage
		)
		sidebarItemExpandedStorage = boolValue(values["sidebarItemExpanded"], fallback: sidebarItemExpandedStorage)
		validateServerCertificateChainStorage = boolValue(
			values["validateServerCertificateChain"],
			fallback: validateServerCertificateChainStorage
		)
		zncIgnoreConfiguredAutojoinStorage = boolValue(
			values["zncIgnoreConfiguredAutojoin"],
			fallback: zncIgnoreConfiguredAutojoinStorage
		)
		zncIgnorePlaybackNotificationsStorage = boolValue(
			values["zncIgnorePlaybackNotifications"],
			fallback: zncIgnorePlaybackNotificationsStorage
		)
		zncIgnoreUserNotificationsStorage = boolValue(
			values["zncIgnoreUserNotifications"],
			fallback: zncIgnoreUserNotificationsStorage
		)
		zncOnlyPlaybackLatestStorage = boolValue(
			values["zncOnlyPlaybackLatest"],
			fallback: zncOnlyPlaybackLatestStorage
		)
	}

	private func migrateLegacyDictionary(_ dictionary: [String: Any], values: [String: Any]) {
		alternateNicknamesStorage = values["identityAlternateNicknames"] as? [String] ?? alternateNicknamesStorage
		autoConnectStorage = boolValue(values["connectOnLaunch"], fallback: autoConnectStorage)
		autoReconnectStorage = boolValue(values["connectOnDisconnect"], fallback: autoReconnectStorage)
		autoSleepModeDisconnectStorage = boolValue(
			values["disconnectOnSleepMode"],
			fallback: autoSleepModeDisconnectStorage
		)
		autojoinWaitsForNickServStorage = boolValue(
			values["autojoinWaitsForNickServIdentification"],
			fallback: autojoinWaitsForNickServStorage
		)
		prefersSecuredConnectionStorage = boolValue(
			values["connectUsingSSL"],
			fallback: prefersSecuredConnectionStorage
		)
		setInvisibleModeOnConnectStorage = boolValue(
			values["setInvisibleOnConnect"],
			fallback: setInvisibleModeOnConnectStorage
		)
		sidebarItemExpandedStorage = boolValue(values["serverListItemIsExpanded"], fallback: sidebarItemExpandedStorage)
		validateServerCertificateChainStorage = boolValue(
			values["validateServerSideSSLCertificate"],
			fallback: validateServerCertificateChainStorage
		)
		identityClientSideCertificateStorage = values["IdentitySSLCertificate"] as? Data ??
			identityClientSideCertificateStorage
		awayNicknameStorage = values["identityAwayNickname"] as? String ?? awayNicknameStorage
		nicknameStorage = values["identityNickname"] as? String ?? nicknameStorage
		normalLeavingCommentStorage = values["connectionDisconnectDefaultMessage"] as? String ??
			normalLeavingCommentStorage
		proxyAddressStorage = values["proxyServerAddress"] as? String ?? proxyAddressStorage
		proxyUsernameStorage = values["proxyServerUsername"] as? String ?? proxyUsernameStorage
		realNameStorage = values["identityRealname"] as? String ?? realNameStorage
		sleepModeLeavingCommentStorage = values["connectionDisconnectSleepModeMessage"] as? String ??
			sleepModeLeavingCommentStorage
		usernameStorage = values["identityUsername"] as? String ?? usernameStorage
		primaryEncodingStorage = uintValue(values["characterEncodingDefault"], fallback: primaryEncodingStorage)
		fallbackEncodingStorage = uintValue(values["characterEncodingFallback"], fallback: fallbackEncodingStorage)
		proxyTypeStorage = IRCConnectionProxyType(rawValue: uintValue(values["proxyServerType"])) ?? proxyTypeStorage
		proxyPortStorage = uint16Value(values["proxyServerPort"], fallback: proxyPortStorage)
		lastMessageServerTimeStorage = doubleValue(
			values["cachedLastServerTimeCapacityReceivedAtTimestamp"],
			fallback: lastMessageServerTimeStorage
		)

		migrateLegacyFloodControl(values)

		if let proxyPassword = values["proxyServerPassword"] as? String {
			proxyPasswordStorage = proxyPassword
			writeProxyPasswordToKeychain()
		}

		if dictionary["cipherSuites"] == nil,
		   let modernCiphers = dictionary["connectionPrefersModernCiphers"] as? NSNumber,
		   modernCiphers.boolValue == false
		{
			cipherSuitesStorage = .none
		}

		migrateLegacyServer(values)
	}

	private func migrateLegacyFloodControl(_ values: [String: Any]) {
		var disabled = false
		if let floodControl = values["floodControl"] as? [String: Any] {
			if let serviceEnabled = floodControl["serviceEnabled"] as? NSNumber, serviceEnabled.boolValue == false {
				disabled = true
			}
			floodControlDelayTimerIntervalStorage = uintValue(
				floodControl["delayTimerInterval"],
				fallback: floodControlDelayTimerIntervalStorage
			)
			floodControlMaximumMessagesStorage = uintValue(
				floodControl["maximumMessageCount"],
				fallback: floodControlMaximumMessagesStorage
			)
		}

		if let enabled = values["isOutgoingFloodControlEnabled"] as? NSNumber, enabled.boolValue == false {
			disabled = true
		}

		if disabled {
			floodControlDelayTimerIntervalStorage = ClientConfigDefaults.minimumFloodDelay
			floodControlMaximumMessagesStorage = ClientConfigDefaults.maximumFloodMessages
		}
	}

	private func migrateLegacyServer(_ values: [String: Any]) {
		if boolValue(values["migratedToServerListV1Layout"]) || serverListStorage.isEmpty == false {
			return
		}

		guard let address = values["serverAddress"] as? String,
		      (address as NSString).isValidInternetAddress
		else {
			Logger(subsystem: "com.vakesz.glasstual", category: "Migration")
				.debug("Server-list migration cancelled because the stored address is invalid")
			return
		}

		let port = uint16Value(values["serverPort"])
		guard port > 0 else {
			Logger(subsystem: "com.vakesz.glasstual", category: "Migration")
				.debug("Server-list migration cancelled because the stored port is invalid")
			return
		}

		let password = XRKeychain.getPasswordFromKeychainItem(
			"Glasstual (Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: "glasstual.server.\(uniqueIdentifierStorage)"
		)
		let server = MutableServer()
		server.serverAddress = address
		server.serverPort = port
		server.serverPassword = password
		server.prefersSecuredConnection = boolValue(values["prefersSecuredConnection"])
		server.writeServerPasswordToKeychain()
		serverListStorage = [server.copy() as! Server]
		migratedServerPasswordPendingDestroy = true
	}

	private func modifyFloodControlDefaults() {
		guard floodControlDelayTimerIntervalStorage == ClientConfigDefaults.floodDelay,
		      floodControlMaximumMessagesStorage == ClientConfigDefaults.floodMaximum,
		      serverListStorage.contains(where: { $0.serverAddress.hasSuffix(".freenode.net") })
		else {
			return
		}

		defaultsStorage["floodControlDelayTimerInterval"] = ClientConfigDefaults.limitedFloodDelay
		defaultsStorage["floodControlMaximumMessages"] = ClientConfigDefaults.limitedFloodMaximum
		floodControlDelayTimerIntervalStorage = ClientConfigDefaults.limitedFloodDelay
		floodControlMaximumMessagesStorage = ClientConfigDefaults.limitedFloodMaximum
	}

	fileprivate func invalidateNicknamePasswordKeychainCache() {
		nicknamePasswordKeychainCache = nil
		nicknamePasswordKeychainCacheIsValid = false
	}

	private func setSerialized(
		_ values: [some XRPortablePropertyDict],
		on dictionary: NSMutableDictionary,
		key: String
	) {
		let serialized = values.map(\.dictionaryValue)
		if serialized.isEmpty == false {
			dictionary[key] = serialized
		}
	}

	private func dictionaries(_ value: Any?) -> [[String: Any]] {
		value as? [[String: Any]] ?? []
	}

	private func boolValue(_ value: Any?, fallback: Bool = false) -> Bool {
		(value as? NSNumber)?.boolValue ?? fallback
	}

	private func uintValue(_ value: Any?, fallback: UInt = 0) -> UInt {
		(value as? NSNumber)?.uintValue ?? fallback
	}

	private func uint16Value(_ value: Any?, fallback: UInt16 = 0) -> UInt16 {
		(value as? NSNumber)?.uint16Value ?? fallback
	}

	private func doubleValue(_ value: Any?, fallback: Double = 0) -> Double {
		(value as? NSNumber)?.doubleValue ?? fallback
	}
}

@objc(IRCClientConfigMutable)
public final class MutableClientConfig: ClientConfig {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(ClientConfig.self, to: XRPortablePropertyDict.self)
	}

	@objc override public var autoConnect: Bool {
		get { autoConnectStorage } set { autoConnectStorage = newValue }
	}

	@objc override public var autoReconnect: Bool {
		get { autoReconnectStorage } set { autoReconnectStorage = newValue }
	}

	@objc override public var autoSleepModeDisconnect: Bool {
		get { autoSleepModeDisconnectStorage } set { autoSleepModeDisconnectStorage = newValue }
	}

	@objc override public var autojoinWaitsForNickServ: Bool {
		get { autojoinWaitsForNickServStorage } set { autojoinWaitsForNickServStorage = newValue }
	}

	@objc override public var hideAutojoinDelayedWarnings: Bool {
		get { hideAutojoinDelayedWarningsStorage } set { hideAutojoinDelayedWarningsStorage = newValue }
	}

	@objc override public var hideNetworkUnavailabilityNotices: Bool {
		get { hideNetworkUnavailabilityNoticesStorage } set { hideNetworkUnavailabilityNoticesStorage = newValue }
	}

	@objc override public var performDisconnectOnPongTimer: Bool {
		get { performDisconnectOnPongTimerStorage } set { performDisconnectOnPongTimerStorage = newValue }
	}

	@objc override public var performDisconnectOnReachabilityChange: Bool {
		get { performDisconnectOnReachabilityChangeStorage } set {
			performDisconnectOnReachabilityChangeStorage = newValue
		}
	}

	@objc override public var performPongTimer: Bool {
		get { performPongTimerStorage } set { performPongTimerStorage = newValue }
	}

	@objc override public var saslAuthenticationDisableExternalMechanism: Bool {
		get { saslAuthenticationDisableExternalMechanismStorage } set {
			saslAuthenticationDisableExternalMechanismStorage = newValue
		}
	}

	@objc override public var sendAuthenticationRequestsToUserServ: Bool {
		get { sendAuthenticationRequestsToUserServStorage } set {
			sendAuthenticationRequestsToUserServStorage = newValue
		}
	}

	@objc override public var sendWhoCommandRequestsToChannels: Bool {
		get { sendWhoCommandRequestsToChannelsStorage } set { sendWhoCommandRequestsToChannelsStorage = newValue }
	}

	@objc override public var setInvisibleModeOnConnect: Bool {
		get { setInvisibleModeOnConnectStorage } set { setInvisibleModeOnConnectStorage = newValue }
	}

	@objc override public var runConnectCommandsSilently: Bool {
		get { runConnectCommandsSilentlyStorage } set { runConnectCommandsSilentlyStorage = newValue }
	}

	@objc override public var sidebarItemExpanded: Bool {
		get { sidebarItemExpandedStorage } set { sidebarItemExpandedStorage = newValue }
	}

	@objc override public var validateServerCertificateChain: Bool {
		get { validateServerCertificateChainStorage } set { validateServerCertificateChainStorage = newValue }
	}

	@objc override public var zncIgnoreConfiguredAutojoin: Bool {
		get { zncIgnoreConfiguredAutojoinStorage } set { zncIgnoreConfiguredAutojoinStorage = newValue }
	}

	@objc override public var zncIgnorePlaybackNotifications: Bool {
		get { zncIgnorePlaybackNotificationsStorage } set { zncIgnorePlaybackNotificationsStorage = newValue }
	}

	@objc override public var zncIgnoreUserNotifications: Bool {
		get { zncIgnoreUserNotificationsStorage } set { zncIgnoreUserNotificationsStorage = newValue }
	}

	@objc override public var zncOnlyPlaybackLatest: Bool {
		get { zncOnlyPlaybackLatestStorage } set { zncOnlyPlaybackLatestStorage = newValue }
	}

	@objc override public var addressType: IRCConnectionAddressType {
		get { addressTypeStorage } set { addressTypeStorage = newValue }
	}

	@objc override public var proxyType: IRCConnectionProxyType {
		get { proxyTypeStorage } set { proxyTypeStorage = newValue }
	}

	@objc override public var fallbackEncoding: UInt {
		get { fallbackEncodingStorage } set { fallbackEncodingStorage = newValue }
	}

	@objc override public var primaryEncoding: UInt {
		get { primaryEncodingStorage } set { primaryEncodingStorage = newValue }
	}

	@objc override public var lastMessageServerTime: TimeInterval {
		get { lastMessageServerTimeStorage } set { lastMessageServerTimeStorage = newValue }
	}

	@objc override public var floodControlDelayTimerInterval: UInt {
		get { floodControlDelayTimerIntervalStorage }
		set {
			precondition((ClientConfigDefaults.minimumFloodDelay ... ClientConfigDefaults.maximumFloodDelay)
				.contains(newValue)); floodControlDelayTimerIntervalStorage = newValue
		}
	}

	@objc override public var floodControlMaximumMessages: UInt {
		get { floodControlMaximumMessagesStorage }
		set {
			precondition((ClientConfigDefaults.minimumFloodMessages ... ClientConfigDefaults.maximumFloodMessages)
				.contains(newValue)); floodControlMaximumMessagesStorage = newValue
		}
	}

	@objc override public var proxyPort: UInt16 {
		get { proxyPortStorage } set { proxyPortStorage = newValue }
	}

	@objc override public var channelList: [ChannelConfig] {
		get { channelListStorage } set { channelListStorage = newValue }
	}

	@objc override public var highlightList: [HighlightMatchCondition] {
		get { highlightListStorage } set { highlightListStorage = newValue }
	}

	@objc override public var ignoreList: [AddressBookEntry] {
		get { ignoreListStorage } set { ignoreListStorage = newValue }
	}

	@objc override public var alternateNicknames: [String] {
		get { alternateNicknamesStorage } set { alternateNicknamesStorage = newValue }
	}

	@objc override public var loginCommands: [String] {
		get { loginCommandsStorage } set { loginCommandsStorage = newValue }
	}

	@objc override public var serverList: [Server] {
		get { serverListStorage } set { serverListStorage = newValue }
	}

	@objc override public var connectionName: String {
		get { connectionNameStorage } set { connectionNameStorage = newValue }
	}

	@objc override public var nickname: String {
		get { nicknameStorage } set { nicknameStorage = newValue }
	}

	@objc override public var normalLeavingComment: String {
		get { normalLeavingCommentStorage } set { normalLeavingCommentStorage = newValue }
	}

	@objc override public var realName: String {
		get { realNameStorage } set { realNameStorage = newValue }
	}

	@objc override public var sleepModeLeavingComment: String {
		get { sleepModeLeavingCommentStorage } set { sleepModeLeavingCommentStorage = newValue }
	}

	@objc override public var username: String {
		get { usernameStorage } set { usernameStorage = newValue }
	}

	@objc override public var identityClientSideCertificate: Data? {
		get { identityClientSideCertificateStorage } set { identityClientSideCertificateStorage = newValue }
	}

	@objc override public var awayNickname: String? {
		get { awayNicknameStorage } set { awayNicknameStorage = newValue }
	}

	@objc override public var saslMechanismPreference: String? {
		get { saslMechanismPreferenceStorage } set { saslMechanismPreferenceStorage = newValue }
	}

	@objc override public var ctcpVersionReply: String? {
		get { ctcpVersionReplyStorage } set { ctcpVersionReplyStorage = newValue }
	}

	@objc override public var proxyAddress: String? {
		get { proxyAddressStorage } set { proxyAddressStorage = newValue }
	}

	@objc override public var proxyUsername: String? {
		get { proxyUsernameStorage } set { proxyUsernameStorage = newValue }
	}

	@objc override public var cipherSuites: RCMCipherSuiteCollection {
		get { cipherSuitesStorage } set { cipherSuitesStorage = newValue }
	}

	@objc override public var nicknamePassword: String? {
		get { super.nicknamePassword }
		set { nicknamePasswordStorage = newValue; invalidateNicknamePasswordKeychainCache() }
	}

	@objc override public var proxyPassword: String? {
		get { super.proxyPassword } set { proxyPasswordStorage = newValue }
	}

	@objc override public var connectionPrefersIPv4: Bool {
		get { connectionPrefersIPv4Storage }
		set { connectionPrefersIPv4Storage = newValue }
	}
}

public typealias IRCClientConfig = ClientConfig
public typealias IRCClientConfigMutable = MutableClientConfig

/** Unmigrated Objective-C declarations still import IRCClientConfig as a Clang
 type. Both names resolve to the same Objective-C runtime class. Keep this
 bridge local to call sites until those declarations move to Swift. */
func bridgeClientConfigToObjectiveC<T: AnyObject>(_ config: ClientConfig) -> T {
	unsafeBitCast(config, to: T.self)
}
