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

@objc(IRCServer)
public nonisolated class Server: PortablePropertyDict {
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
		serverPasswordKeychainItem.password
	}

	private var serverPasswordKeychainItem: KeychainItem {
		.serverPassword(uniqueIdentifierStorage)
	}

	override public init() {
		super.init(dictionary: [:])
	}

	@objc(initWithDictionary:)
	public required init(dictionary dic: [String: Any]) {
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

		defaultsStorage = ["serverPort": NSNumber(value: IRCConnectionDefaults.serverPort)]
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		if initializedAsCopy {
			return
		}

		if uniqueIdentifierStorage.isEmpty {
			uniqueIdentifierStorage = UUID().uuidString
		}
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let defaultsMutable = NSMutableDictionary(dictionary: defaultsStorage)
		defaultsMutable.addEntries(from: dic)

		var prefersSecured = false
		defaultsMutable.ce_assignBool(to: &prefersSecured, forKey: "prefersSecuredConnection")
		prefersSecuredConnectionStorage = prefersSecured

		if let address = defaultsMutable["serverAddress"] as? String {
			serverAddressStorage = address
		}

		if let identifier = defaultsMutable["uniqueIdentifier"] as? String {
			uniqueIdentifierStorage = identifier
		}

		var port: UInt16 = 0
		defaultsMutable.ce_assignUnsignedShort(to: &port, forKey: "serverPort")
		serverPortStorage = port
	}

	override public func dictionaryValue(for _: PortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.ce_setBool(prefersSecuredConnectionStorage, forKey: "prefersSecuredConnection")
		dic.ce_maybeSetObject(serverAddressStorage, forKey: "serverAddress")
		dic.ce_maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dic.ce_setUnsignedShort(serverPortStorage, forKey: "serverPort")

		guard let values = dic as? [String: Any] else {
			preconditionFailure("Server dictionaries must use String keys")
		}

		return values
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		guard let copy = super.copy(asMutable: mutableCopy, uniquing: false) as? Server else {
			preconditionFailure("Server copies must preserve their model type")
		}

		copy.defaultsStorage = defaultsStorage
		copy.serverPasswordStorage = serverPasswordStorage
		/* destroyKeychainItemsDuringDealloc is deliberately not copied: a copy
		 shares the original's uniqueIdentifier, so propagating the flag makes
		 the deallocation of any transient copy delete the live keychain item. */

		if uniquing {
			copy.uniqueIdentifierStorage = UUID().uuidString
		}

		return copy
	}

	override public var mutableClass: PortablePropertyDict {
		unsafeBitCast(MutableServer.self, to: PortablePropertyDict.self)
	}

	@objc
	public func writeServerPasswordToKeychain() {
		guard let serverPasswordStorage else {
			return
		}

		serverPasswordKeychainItem.write(serverPasswordStorage)

		self.serverPasswordStorage = nil
	}

	@objc
	public func destroyServerPasswordKeychainItem() {
		serverPasswordKeychainItem.delete()

		serverPasswordStorage = nil
	}
}

@objc(IRCServerMutable)
public final nonisolated class MutableServer: Server {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyDict {
		unsafeBitCast(Server.self, to: PortablePropertyDict.self)
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
