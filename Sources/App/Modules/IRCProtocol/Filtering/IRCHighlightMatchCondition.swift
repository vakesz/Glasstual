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
import os

private let highlightConditionLogger = Logger(
	subsystem: Bundle.main.bundleIdentifier ?? "Glasstual",
	category: "IRCHighlightMatchCondition"
)

@objc(IRCHighlightMatchCondition)
public class HighlightMatchCondition: PortablePropertyDict {
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
	public required init(dictionary dic: [String: Any]) {
		super.init(dictionary: dic)
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	/// `true` when the persisted dictionary carried everything the entry
	/// needs. A hand-edited or truncated plist must be skipped on load, not
	/// abort the process.
	@objc public var isWellFormed: Bool {
		matchKeywordStorage.isEmpty == false
	}

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if isMutable || initializedAsCopy {
			return
		}

		// The Objective-C original used NSParameterAssert, which compiles out
		// in release; a `precondition` here turned a malformed plist into an
		// abort with no recovery path. Callers check `isWellFormed` instead.
		if isWellFormed == false {
			highlightConditionLogger.error("Loaded a highlight condition with no match keyword")
		}
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let dictionary = dic as NSDictionary

		var excluded = false
		dictionary.ce_assignBool(to: &excluded, forKey: "matchIsExcluded")
		matchIsExcludedStorage = excluded

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
			uniqueIdentifierStorage = UUID().uuidString
		}
	}

	override public func dictionaryValue(for _: PortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.ce_maybeSetObject(matchChannelIdStorage, forKey: "matchChannelID")
		dic.ce_maybeSetObject(matchKeywordStorage, forKey: "matchKeyword")
		dic.ce_maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dic.ce_setBool(matchIsExcludedStorage, forKey: "matchIsExcluded")

		guard let values = dic as? [String: Any] else {
			preconditionFailure("Highlight condition dictionaries must use String keys")
		}

		return values
	}

	override public func uniqueCopy(asMutable mutableCopy: Bool) -> Any {
		guard let object = super.uniqueCopy(asMutable: mutableCopy) as? HighlightMatchCondition else {
			preconditionFailure("HighlightMatchCondition copies must preserve their model type")
		}

		object.uniqueIdentifierStorage = UUID().uuidString

		return object
	}

	override public var mutableClass: PortablePropertyDict {
		unsafeBitCast(MutableHighlightMatchCondition.self, to: PortablePropertyDict.self)
	}
}

@objc(IRCHighlightMatchConditionMutable)
public final class MutableHighlightMatchCondition: HighlightMatchCondition {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyDict {
		unsafeBitCast(HighlightMatchCondition.self, to: PortablePropertyDict.self)
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
