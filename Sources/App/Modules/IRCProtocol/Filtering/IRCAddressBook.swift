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

@objc public enum IRCAddressBookEntryType: UInt, Sendable {
	case ignore = 0
	case userTracking = 1
	case mixed = 2
}

@objc public enum IRCAddressBookUserTrackingStatus: UInt, Sendable {
	case unknown = 0
	case signedOff = 1
	case signedOn = 2
	case available = 3
	case notAvailable = 4
	case away = 5
	case notAway = 6
}

@objc(IRCAddressBookEntry)
public class AddressBookEntry: PortablePropertyDict {
	fileprivate var ignoreClientToClientProtocolStorage = false
	fileprivate var ignoreFileTransferRequestsStorage = false
	fileprivate var ignoreGeneralEventMessagesStorage = false
	fileprivate var ignoreInlineMediaStorage = false
	fileprivate var ignoreNoticeMessagesStorage = false
	fileprivate var ignorePrivateMessageHighlightsStorage = false
	fileprivate var ignorePrivateMessagesStorage = false
	fileprivate var ignorePublicMessageHighlightsStorage = false
	fileprivate var ignorePublicMessagesStorage = false
	fileprivate var trackUserActivityStorage = false
	fileprivate var entryTypeStorage: IRCAddressBookEntryType = .ignore
	fileprivate var hostmaskStorage = ""
	fileprivate var hostmaskRegularExpressionStorage = ""
	fileprivate var matcherStorage: AddressBookEntryMatcher?
	fileprivate var trackingNicknameStorage: String?
	fileprivate var parentEntriesStorage: [AddressBookEntry]?
	fileprivate var uniqueIdentifierStorage = ""
	fileprivate var defaultsStorage: [String: Any] = [:]

	@objc public var entryType: IRCAddressBookEntryType {
		entryTypeStorage
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var hostmask: String {
		hostmaskStorage
	}

	@objc public var hostmaskRegularExpression: String {
		hostmaskRegularExpressionStorage
	}

	@objc public var trackingNickname: String? {
		trackingNicknameStorage
	}

	@objc public var ignoreClientToClientProtocol: Bool {
		ignoreClientToClientProtocolStorage
	}

	@objc public var ignoreGeneralEventMessages: Bool {
		ignoreGeneralEventMessagesStorage
	}

	@objc public var ignoreNoticeMessages: Bool {
		ignoreNoticeMessagesStorage
	}

	@objc public var ignorePrivateMessageHighlights: Bool {
		ignorePrivateMessageHighlightsStorage
	}

	@objc public var ignorePrivateMessages: Bool {
		ignorePrivateMessagesStorage
	}

	@objc public var ignorePublicMessageHighlights: Bool {
		ignorePublicMessageHighlightsStorage
	}

	@objc public var ignorePublicMessages: Bool {
		ignorePublicMessagesStorage
	}

	@objc public var ignoreFileTransferRequests: Bool {
		ignoreFileTransferRequestsStorage
	}

	@objc public var ignoreInlineMedia: Bool {
		ignoreInlineMediaStorage
	}

	@objc public var ignoreMessagesContainingMatch: Bool {
		false
	}

	@objc public var trackUserActivity: Bool {
		trackUserActivityStorage
	}

	@objc public var parentEntries: [AddressBookEntry]? {
		parentEntriesStorage
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

	@objc public class func newIgnoreEntry() -> Self {
		newIgnoreEntry(forHostmask: nil)
	}

	@objc(newIgnoreEntryForHostmask:)
	public class func newIgnoreEntry(forHostmask hostmask: String?) -> Self {
		let dic: [String: Any] = [
			"hostmask": hostmask ?? "",
			"entryType": NSNumber(value: IRCAddressBookEntryType.ignore.rawValue),
			"ignoreClientToClientProtocol": true,
			"ignoreFileTransferRequests": true,
			"ignoreGeneralEventMessages": true,
			"ignoreInlineMedia": true,
			"ignoreNoticeMessages": true,
			"ignorePrivateMessageHighlights": true,
			"ignorePrivateMessages": true,
			"ignorePublicMessageHighlights": true,
			"ignorePublicMessages": true,
		]

		return self.init(dictionary: dic)
	}

	@objc public class func newUserTrackingEntry() -> Self {
		let dic: [String: Any] = [
			"entryType": NSNumber(value: IRCAddressBookEntryType.userTracking.rawValue),
			"trackUserActivity": true,
		]

		return self.init(dictionary: dic)
	}

	@objc(populateDefaultsPreflight)
	override public func populateDefaultsPreflight() {
		if initializedAsCopy {
			return
		}

		defaultsStorage = [
			"entryType": NSNumber(value: IRCAddressBookEntryType.ignore.rawValue),
			"ignoreClientToClientProtocol": false,
			"ignoreFileTransferRequests": false,
			"ignoreGeneralEventMessages": false,
			"ignoreInlineMedia": false,
			"ignoreNoticeMessages": false,
			"ignorePrivateMessageHighlights": false,
			"ignorePrivateMessages": false,
			"ignorePublicMessageHighlights": false,
			"ignorePublicMessages": false,
			"trackUserActivity": false,
		]
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

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if initializedAsCopy {
			return
		}

		rebuildCache()
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let dictionary = dic as NSDictionary

		var entryTypeValue: UInt = 0
		dictionary.ce_assignUnsignedInteger(to: &entryTypeValue, forKey: "entryType")
		entryTypeStorage = IRCAddressBookEntryType(rawValue: entryTypeValue) ?? .ignore

		if entryTypeStorage == .ignore || entryTypeStorage == .mixed {
			assignBool("ignoreClientToClientProtocol", to: &ignoreClientToClientProtocolStorage, in: dictionary)
			assignBool("ignoreFileTransferRequests", to: &ignoreFileTransferRequestsStorage, in: dictionary)
			assignBool("ignoreGeneralEventMessages", to: &ignoreGeneralEventMessagesStorage, in: dictionary)
			assignBool("ignoreInlineMedia", to: &ignoreInlineMediaStorage, in: dictionary)
			assignBool("ignoreNoticeMessages", to: &ignoreNoticeMessagesStorage, in: dictionary)
			assignBool("ignorePrivateMessageHighlights", to: &ignorePrivateMessageHighlightsStorage, in: dictionary)
			assignBool("ignorePrivateMessages", to: &ignorePrivateMessagesStorage, in: dictionary)
			assignBool("ignorePublicMessageHighlights", to: &ignorePublicMessageHighlightsStorage, in: dictionary)
			assignBool("ignorePublicMessages", to: &ignorePublicMessagesStorage, in: dictionary)

			assignBool("ignoreCTCP", to: &ignoreClientToClientProtocolStorage, in: dictionary)
			assignBool("ignoreJPQE", to: &ignoreGeneralEventMessagesStorage, in: dictionary)
			assignBool("ignoreNotices", to: &ignoreNoticeMessagesStorage, in: dictionary)
			assignBool("ignorePMHighlights", to: &ignorePrivateMessageHighlightsStorage, in: dictionary)
			assignBool("ignorePrivateMsg", to: &ignorePrivateMessagesStorage, in: dictionary)
			assignBool("ignoreHighlights", to: &ignorePublicMessageHighlightsStorage, in: dictionary)
			assignBool("ignorePublicMsg", to: &ignorePublicMessagesStorage, in: dictionary)
		}

		if entryTypeStorage == .userTracking || entryTypeStorage == .mixed {
			assignBool("trackUserActivity", to: &trackUserActivityStorage, in: dictionary)
			assignBool("notifyJoins", to: &trackUserActivityStorage, in: dictionary)
		}

		if let hostmask = dictionary["hostmask"] as? String {
			hostmaskStorage = hostmask
		}

		if let identifier = dictionary["uniqueIdentifier"] as? String {
			uniqueIdentifierStorage = identifier
		}
	}

	@objc public func rebuildCache() {
		rebuildHostmaskRegularExpression()
		rebuildTrackingNickname()
	}

	@objc public func rebuildHostmaskRegularExpression() {
		let matcher = AddressBookEntryMatcher(entryType: entryTypeStorage, hostmask: hostmaskStorage)
		matcherStorage = matcher
		hostmaskRegularExpressionStorage = matcher.regularExpressionPattern
	}

	@objc public func rebuildTrackingNickname() {
		trackingNicknameStorage = matcherStorage?.trackingNickname
	}

	@objc(checkMatch:)
	public func checkMatch(_ hostmask: String) -> Bool {
		matcherStorage?.matches(hostmask: hostmask) ?? false
	}

	override public func dictionaryValue(for target: PortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.ce_maybeSetObject(hostmaskStorage, forKey: "hostmask")
		dic.ce_maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")

		if entryTypeStorage == .ignore || entryTypeStorage == .mixed {
			dic.ce_setBool(ignoreClientToClientProtocolStorage, forKey: "ignoreClientToClientProtocol")
			dic.ce_setBool(ignoreFileTransferRequestsStorage, forKey: "ignoreFileTransferRequests")
			dic.ce_setBool(ignoreGeneralEventMessagesStorage, forKey: "ignoreGeneralEventMessages")
			dic.ce_setBool(ignoreInlineMediaStorage, forKey: "ignoreInlineMedia")
			dic.ce_setBool(ignoreNoticeMessagesStorage, forKey: "ignoreNoticeMessages")
			dic.ce_setBool(ignorePrivateMessageHighlightsStorage, forKey: "ignorePrivateMessageHighlights")
			dic.ce_setBool(ignorePrivateMessagesStorage, forKey: "ignorePrivateMessages")
			dic.ce_setBool(ignorePublicMessageHighlightsStorage, forKey: "ignorePublicMessageHighlights")
			dic.ce_setBool(ignorePublicMessagesStorage, forKey: "ignorePublicMessages")
		}

		if entryTypeStorage == .userTracking || entryTypeStorage == .mixed {
			dic.ce_setBool(trackUserActivityStorage, forKey: "trackUserActivity")
		}

		dic.ce_setUnsignedInteger(UInt(entryTypeStorage.rawValue), forKey: "entryType")

		if target == .copy || target == .mutableCopy {
			guard let values = dic as? [String: Any] else {
				preconditionFailure("Address book dictionaries must use String keys")
			}

			return values
		}

		let compacted = dic.ce_dictionaryByRemovingDefaults(defaultsStorage as NSDictionary)
		guard let values = compacted as? [String: Any] else {
			preconditionFailure("Address book dictionaries must use String keys")
		}

		return values
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		guard let config = super.copy(asMutable: mutableCopy, uniquing: false) as? AddressBookEntry else {
			preconditionFailure("AddressBookEntry copies must preserve their model type")
		}

		config.defaultsStorage = defaultsStorage
		config.hostmaskRegularExpressionStorage = hostmaskRegularExpressionStorage
		config.matcherStorage = matcherStorage
		config.trackingNicknameStorage = trackingNicknameStorage
		config.parentEntriesStorage = parentEntriesStorage

		if uniquing {
			config.uniqueIdentifierStorage = UUID().uuidString
		}

		return config
	}

	override public var mutableClass: PortablePropertyDict {
		unsafeBitCast(MutableAddressBookEntry.self, to: PortablePropertyDict.self)
	}

	private func assignBool(_ key: String, to storage: inout Bool, in dictionary: NSDictionary) {
		var value = storage
		dictionary.ce_assignBool(to: &value, forKey: key)
		storage = value
	}
}

@objc(IRCAddressBookEntryMutable)
public final class MutableAddressBookEntry: AddressBookEntry {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyDict {
		unsafeBitCast(AddressBookEntry.self, to: PortablePropertyDict.self)
	}

	@objc override public var entryType: IRCAddressBookEntryType {
		get { entryTypeStorage }
		set {
			if entryTypeStorage != newValue {
				entryTypeStorage = newValue
				rebuildCache()
			}
		}
	}

	@objc override public var hostmask: String {
		get { hostmaskStorage }
		set {
			if hostmaskStorage != newValue {
				hostmaskStorage = newValue
				rebuildCache()
			}
		}
	}

	@objc override public var ignoreClientToClientProtocol: Bool {
		get { ignoreClientToClientProtocolStorage }
		set { ignoreClientToClientProtocolStorage = newValue }
	}

	@objc override public var ignoreFileTransferRequests: Bool {
		get { ignoreFileTransferRequestsStorage }
		set { ignoreFileTransferRequestsStorage = newValue }
	}

	@objc override public var ignoreGeneralEventMessages: Bool {
		get { ignoreGeneralEventMessagesStorage }
		set { ignoreGeneralEventMessagesStorage = newValue }
	}

	@objc override public var ignoreInlineMedia: Bool {
		get { ignoreInlineMediaStorage }
		set { ignoreInlineMediaStorage = newValue }
	}

	@objc override public var ignoreNoticeMessages: Bool {
		get { ignoreNoticeMessagesStorage }
		set { ignoreNoticeMessagesStorage = newValue }
	}

	@objc override public var ignorePrivateMessageHighlights: Bool {
		get { ignorePrivateMessageHighlightsStorage }
		set { ignorePrivateMessageHighlightsStorage = newValue }
	}

	@objc override public var ignorePrivateMessages: Bool {
		get { ignorePrivateMessagesStorage }
		set { ignorePrivateMessagesStorage = newValue }
	}

	@objc override public var ignorePublicMessageHighlights: Bool {
		get { ignorePublicMessageHighlightsStorage }
		set { ignorePublicMessageHighlightsStorage = newValue }
	}

	@objc override public var ignorePublicMessages: Bool {
		get { ignorePublicMessagesStorage }
		set { ignorePublicMessagesStorage = newValue }
	}

	@objc override public var trackUserActivity: Bool {
		get { trackUserActivityStorage }
		set { trackUserActivityStorage = newValue }
	}

	@objc override public var parentEntries: [AddressBookEntry]? {
		get { parentEntriesStorage }
		set { parentEntriesStorage = newValue }
	}
}
