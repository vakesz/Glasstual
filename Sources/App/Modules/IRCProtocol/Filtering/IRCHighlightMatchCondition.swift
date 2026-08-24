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

@objc(IRCHighlightMatchCondition)
public class HighlightMatchCondition: XRPortablePropertyDict {
	fileprivate var matchIsExcludedStorage = false
	fileprivate var matchChannelIdStorage: String?
	fileprivate var matchKeywordStorage = ""
	fileprivate var uniqueIdentifierStorage = ""

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var matchKeyword: String {
		matchKeywordStorage
	}

	@objc public var matchChannelId: String? {
		matchChannelIdStorage
	}

	@objc public var matchIsExcluded: Bool {
		matchIsExcludedStorage
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

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if isMutable || initializedAsCopy {
			return
		}

		precondition(!matchKeywordStorage.isEmpty)
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let dictionary = dic as NSDictionary

		var excluded = ObjCBool(false)
		dictionary.assignBool(to: &excluded, forKey: "matchIsExcluded")
		matchIsExcludedStorage = excluded.boolValue

		if let channelId = dictionary["matchChannelID"] as? String {
			matchChannelIdStorage = channelId
		}

		if let keyword = dictionary["matchKeyword"] as? String {
			matchKeywordStorage = keyword
		}

		if let identifier = dictionary["uniqueIdentifier"] as? String {
			uniqueIdentifierStorage = identifier
		}
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		if uniqueIdentifierStorage.isEmpty {
			uniqueIdentifierStorage = NSString.withUUID()
		}
	}

	override public func dictionaryValue(for _: XRPortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.maybeSetObject(matchChannelIdStorage, forKey: "matchChannelID")
		dic.maybeSetObject(matchKeywordStorage, forKey: "matchKeyword")
		dic.maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dic.setBool(matchIsExcludedStorage, forKey: "matchIsExcluded")

		return dic as! [String: Any]
	}

	override public func uniqueCopy(asMutable mutableCopy: Bool) -> Any {
		let object = super.uniqueCopy(asMutable: mutableCopy) as! HighlightMatchCondition

		object.uniqueIdentifierStorage = NSString.withUUID()

		return object
	}

	override public var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableHighlightMatchCondition.self, to: XRPortablePropertyDict.self)
	}
}

@objc(IRCHighlightMatchConditionMutable)
public final class MutableHighlightMatchCondition: HighlightMatchCondition {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(HighlightMatchCondition.self, to: XRPortablePropertyDict.self)
	}

	@objc override public var matchIsExcluded: Bool {
		get { matchIsExcludedStorage }
		set { matchIsExcludedStorage = newValue }
	}

	@objc override public var matchChannelId: String? {
		get { matchChannelIdStorage }
		set { matchChannelIdStorage = newValue }
	}

	@objc override public var matchKeyword: String {
		get { matchKeywordStorage }
		set { matchKeywordStorage = newValue }
	}
}
