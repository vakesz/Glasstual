/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import Foundation

@objc(IRCServer)
public class Server: XRPortablePropertyDict {
	fileprivate var prefersSecuredConnectionStorage = false
	fileprivate var serverAddressStorage = ""
	fileprivate var serverPasswordStorage: String?
	fileprivate var serverPortStorage: UInt16 = 0
	fileprivate var uniqueIdentifierStorage = ""
	fileprivate var defaultsStorage: [String: Any] = [:]

	@objc public var destroyKeychainItemsDuringDealloc = false

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var serverAddress: String {
		serverAddressStorage
	}

	@objc public var serverPort: UInt16 {
		serverPortStorage
	}

	@objc public var prefersSecuredConnection: Bool {
		prefersSecuredConnectionStorage
	}

	@objc public var serverPassword: String? {
		serverPasswordStorage ?? serverPasswordFromKeychain
	}

	@objc public var serverPasswordFromKeychain: String? {
		let serviceName = "glasstual.server.\(uniqueIdentifierStorage)"

		return XRKeychain.getPasswordFromKeychainItem(
			"Glasstual (Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: serviceName
		)
	}

	override public init() {
		super.init(dictionary: [:])
	}

	@objc(initWithDictionary:)
	override public init(dictionary dic: [String: Any]) {
		super.init(dictionary: dic)
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	deinit {
		if destroyKeychainItemsDuringDealloc {
			destroyServerPasswordKeychainItem()
		}
	}

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		/* Health checks are disabled because Server Properties might
		 write an empty server address to the class then perform a
		 copy on the object which would throw an exception. */
	}

	@objc(populateDefaultsPreflight)
	override public func populateDefaultsPreflight() {
		if initializedAsCopy {
			return
		}

		defaultsStorage = ["serverPort": NSNumber(value: IRCConnectionDefaultServerPort)]
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		if initializedAsCopy {
			return
		}

		if uniqueIdentifierStorage.isEmpty {
			uniqueIdentifierStorage = NSString.withUUID()
		}
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let defaultsMutable = NSMutableDictionary(dictionary: defaultsStorage)
		defaultsMutable.addEntries(from: dic)

		var prefersSecured = ObjCBool(false)
		defaultsMutable.assignBool(to: &prefersSecured, forKey: "prefersSecuredConnection")
		prefersSecuredConnectionStorage = prefersSecured.boolValue

		if let address = defaultsMutable["serverAddress"] as? String {
			serverAddressStorage = address
		}

		if let identifier = defaultsMutable["uniqueIdentifier"] as? String {
			uniqueIdentifierStorage = identifier
		}

		var port: UInt16 = 0
		defaultsMutable.assignUnsignedShort(to: &port, forKey: "serverPort")
		serverPortStorage = port
	}

	override public func dictionaryValue(for _: XRPortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.setBool(prefersSecuredConnectionStorage, forKey: "prefersSecuredConnection")
		dic.maybeSetObject(serverAddressStorage, forKey: "serverAddress")
		dic.maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dic.setUnsignedShort(serverPortStorage, forKey: "serverPort")

		return dic as! [String: Any]
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let copy = super.copy(asMutable: mutableCopy, uniquing: false) as! Server

		copy.defaultsStorage = defaultsStorage
		copy.serverPasswordStorage = serverPasswordStorage
		copy.destroyKeychainItemsDuringDealloc = destroyKeychainItemsDuringDealloc

		if uniquing {
			copy.uniqueIdentifierStorage = NSString.withUUID()
		}

		return copy
	}

	override public var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableServer.self, to: XRPortablePropertyDict.self)
	}

	@objc
	public func writeServerPasswordToKeychain() {
		guard let serverPasswordStorage else {
			return
		}

		let serviceName = "glasstual.server.\(uniqueIdentifierStorage)"

		XRKeychain.modifyOrAddItem(
			"Glasstual (Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			withNewPassword: serverPasswordStorage,
			serviceName: serviceName
		)

		self.serverPasswordStorage = nil
	}

	@objc
	public func destroyServerPasswordKeychainItem() {
		let serviceName = "glasstual.server.\(uniqueIdentifierStorage)"

		XRKeychain.deleteItem(
			"Glasstual (Server Password)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: serviceName
		)

		serverPasswordStorage = nil
	}
}

@objc(IRCServerMutable)
public final class MutableServer: Server {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(Server.self, to: XRPortablePropertyDict.self)
	}

	@objc override public var prefersSecuredConnection: Bool {
		get { prefersSecuredConnectionStorage }
		set { prefersSecuredConnectionStorage = newValue }
	}

	@objc override public var serverAddress: String {
		get { serverAddressStorage }
		set { serverAddressStorage = newValue }
	}

	@objc override public var serverPassword: String? {
		get { serverPasswordStorage ?? serverPasswordFromKeychain }
		set { serverPasswordStorage = newValue }
	}

	@objc override public var serverPort: UInt16 {
		get { serverPortStorage }
		set { serverPortStorage = newValue }
	}
}
