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

@objc(IRCAddressBookEntry)
public class AddressBookEntry: XRPortablePropertyDict {
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
	override public required init(dictionary dic: [String: Any]) {
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
			uniqueIdentifierStorage = NSString.withUUID()
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
		dictionary.assignUnsignedInteger(to: &entryTypeValue, forKey: "entryType")
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

	override public func dictionaryValue(for target: XRPortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.maybeSetObject(hostmaskStorage, forKey: "hostmask")
		dic.maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")

		if entryTypeStorage == .ignore || entryTypeStorage == .mixed {
			dic.setBool(ignoreClientToClientProtocolStorage, forKey: "ignoreClientToClientProtocol")
			dic.setBool(ignoreFileTransferRequestsStorage, forKey: "ignoreFileTransferRequests")
			dic.setBool(ignoreGeneralEventMessagesStorage, forKey: "ignoreGeneralEventMessages")
			dic.setBool(ignoreInlineMediaStorage, forKey: "ignoreInlineMedia")
			dic.setBool(ignoreNoticeMessagesStorage, forKey: "ignoreNoticeMessages")
			dic.setBool(ignorePrivateMessageHighlightsStorage, forKey: "ignorePrivateMessageHighlights")
			dic.setBool(ignorePrivateMessagesStorage, forKey: "ignorePrivateMessages")
			dic.setBool(ignorePublicMessageHighlightsStorage, forKey: "ignorePublicMessageHighlights")
			dic.setBool(ignorePublicMessagesStorage, forKey: "ignorePublicMessages")
		}

		if entryTypeStorage == .userTracking || entryTypeStorage == .mixed {
			dic.setBool(trackUserActivityStorage, forKey: "trackUserActivity")
		}

		dic.setUnsignedInteger(UInt(entryTypeStorage.rawValue), forKey: "entryType")

		if target == .copy || target == .mutableCopy {
			return dic as! [String: Any]
		}

		return dic.removingDefaults(defaultsStorage) as! [String: Any]
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let config = super.copy(asMutable: mutableCopy, uniquing: false) as! AddressBookEntry

		config.defaultsStorage = defaultsStorage
		config.hostmaskRegularExpressionStorage = hostmaskRegularExpressionStorage
		config.matcherStorage = matcherStorage
		config.trackingNicknameStorage = trackingNicknameStorage
		config.parentEntriesStorage = parentEntriesStorage

		if uniquing {
			config.uniqueIdentifierStorage = NSString.withUUID()
		}

		return config
	}

	override public var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableAddressBookEntry.self, to: XRPortablePropertyDict.self)
	}

	private func assignBool(_ key: String, to storage: inout Bool, in dictionary: NSDictionary) {
		var value = ObjCBool(storage)
		dictionary.assignBool(to: &value, forKey: key)
		storage = value.boolValue
	}
}

@objc(IRCAddressBookEntryMutable)
public final class MutableAddressBookEntry: AddressBookEntry {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(AddressBookEntry.self, to: XRPortablePropertyDict.self)
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
