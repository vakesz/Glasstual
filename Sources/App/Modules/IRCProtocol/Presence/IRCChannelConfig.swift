/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
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

import AppKit

@objc(IRCChannelConfig)
public class ChannelConfig: XRPortablePropertyDict {
	fileprivate var autoJoinStorage = true
	fileprivate var ignoreGeneralEventMessagesStorage = false
	fileprivate var ignoreHighlightsStorage = false
	fileprivate var inlineMediaDisabledStorage = false
	fileprivate var inlineMediaEnabledStorage = false
	fileprivate var pushNotificationsStorage = true
	fileprivate var showTreeBadgeCountStorage = true
	fileprivate var typeStorage = IRCChannelType.channel
	fileprivate var channelNameStorage = ""
	fileprivate var labelStorage: String?
	fileprivate var defaultModesStorage: String?
	fileprivate var defaultTopicStorage: String?
	fileprivate var secretKeyStorage: String?
	fileprivate var uniqueIdentifierStorage = ""
	fileprivate var defaultsStorage: [String: Any] = [:]

	private let notificationsLock = NSLock()
	private var notificationsStorage: [String: Any] = [:]

	@objc public var autoJoin: Bool {
		autoJoinStorage
	}

	@objc public var ignoreGeneralEventMessages: Bool {
		ignoreGeneralEventMessagesStorage
	}

	@objc public var ignoreHighlights: Bool {
		ignoreHighlightsStorage
	}

	@objc public var inlineMediaDisabled: Bool {
		inlineMediaDisabledStorage
	}

	@objc public var inlineMediaEnabled: Bool {
		inlineMediaEnabledStorage
	}

	@objc public var pushNotifications: Bool {
		pushNotificationsStorage
	}

	@objc public var showTreeBadgeCount: Bool {
		showTreeBadgeCountStorage
	}

	@objc public var type: IRCChannelType {
		typeStorage
	}

	@objc public var channelName: String {
		channelNameStorage
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage
	}

	@objc public var label: String? {
		labelStorage
	}

	@objc public var defaultModes: String? {
		defaultModesStorage
	}

	@objc public var defaultTopic: String? {
		defaultTopicStorage
	}

	@objc public var secretKey: String? {
		secretKeyStorage ?? secretKeyFromKeychain
	}

	@objc public var secretKeyFromKeychain: String? {
		XRKeychain.getPasswordFromKeychainItem(
			"Glasstual (Channel JOIN Key)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: secretKeyServiceName
		)
	}

	private var notifications: [String: Any] {
		notificationsLock.withLock { notificationsStorage }
	}

	private var secretKeyServiceName: String {
		"glasstual.cjoinkey.\(uniqueIdentifierStorage)"
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

	@objc(seedWithName:)
	public class func seed(withName channelName: String) -> ChannelConfig {
		ChannelConfig(dictionary: ["channelName": channelName])
	}

	@objc(initializedClassHealthCheck)
	override public func initializedClassHealthCheck() {
		if isMutable || initializedAsCopy {
			return
		}

		precondition(channelNameStorage.isEmpty == false)
	}

	@objc(populateDefaultsPreflight)
	override public func populateDefaultsPreflight() {
		if initializedAsCopy {
			return
		}

		defaultsStorage = [
			"autoJoin": true,
			"channelType": IRCChannelType.channel.rawValue,
			"ignoreGeneralEventMessages": false,
			"ignoreHighlights": false,
			"inlineMediaEnabled": false,
			"inlineMediaDisabled": false,
			"pushNotifications": true,
			"showTreeBadgeCount": true,
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

	@objc(populateDefaultsByAppendingDictionary:)
	public func populateDefaults(byAppending defaultsToAppend: [String: Any]) {
		defaultsStorage.merge(defaultsToAppend) { _, replacement in replacement }
	}

	@objc(populateDictionaryValues:)
	override public func populateDictionaryValues(_ dic: [String: Any]) {
		let values = NSMutableDictionary(dictionary: defaultsStorage)
		values.addEntries(from: dic)

		assignBool("pushNotifications", to: &pushNotificationsStorage, in: values)
		assignBool("showTreeBadgeCount", to: &showTreeBadgeCountStorage, in: values)

		if let channelName = values["channelName"] as? String {
			channelNameStorage = channelName
		}

		if let uniqueIdentifier = values["uniqueIdentifier"] as? String {
			uniqueIdentifierStorage = uniqueIdentifier
		}

		if let typeValue = values["channelType"] as? NSNumber,
		   let type = IRCChannelType(rawValue: typeValue.uintValue)
		{
			typeStorage = type
		}

		guard typeStorage == .channel else {
			return
		}

		assignBool("autoJoin", to: &autoJoinStorage, in: values)
		assignBool("ignoreGeneralEventMessages", to: &ignoreGeneralEventMessagesStorage, in: values)
		assignBool("ignoreHighlights", to: &ignoreHighlightsStorage, in: values)
		assignBool("inlineMediaDisabled", to: &inlineMediaDisabledStorage, in: values)
		assignBool("inlineMediaEnabled", to: &inlineMediaEnabledStorage, in: values)

		labelStorage = values["label"] as? String
		defaultModesStorage = values["defaultMode"] as? String
		defaultTopicStorage = values["defaultTopic"] as? String

		if let notifications = values["notifications"] as? [String: Any] {
			notificationsLock.withLock {
				notificationsStorage = notifications
			}
		}

		guard initializedAsCopy == false else {
			return
		}

		assignBool("joinOnConnect", to: &autoJoinStorage, in: values)
		assignBool("ignoreJPQActivity", to: &ignoreGeneralEventMessagesStorage, in: values)
		assignBool("enableNotifications", to: &pushNotificationsStorage, in: values)
		assignBool("enableTreeBadgeCountDrawing", to: &showTreeBadgeCountStorage, in: values)

		migrateInlineMediaSettings(from: dic)
	}

	override public func dictionaryValue(for target: XRPortablePropertyDictTarget) -> [String: Any] {
		let dic = NSMutableDictionary()

		dic.setBool(pushNotificationsStorage, forKey: "pushNotifications")
		dic.setBool(showTreeBadgeCountStorage, forKey: "showTreeBadgeCount")

		if typeStorage == .channel {
			dic.maybeSetObject(labelStorage, forKey: "label")
			dic.maybeSetObject(defaultModesStorage, forKey: "defaultMode")
			dic.maybeSetObject(defaultTopicStorage, forKey: "defaultTopic")
			dic.maybeSetObject(notifications, forKey: "notifications")
			dic.setBool(autoJoinStorage, forKey: "autoJoin")
			dic.setBool(ignoreGeneralEventMessagesStorage, forKey: "ignoreGeneralEventMessages")
			dic.setBool(ignoreHighlightsStorage, forKey: "ignoreHighlights")
			dic.setBool(inlineMediaDisabledStorage, forKey: "inlineMediaDisabled")
			dic.setBool(inlineMediaEnabledStorage, forKey: "inlineMediaEnabled")
		}

		dic.maybeSetObject(channelNameStorage, forKey: "channelName")
		dic.maybeSetObject(uniqueIdentifierStorage, forKey: "uniqueIdentifier")
		dic.setUnsignedInteger(UInt(typeStorage.rawValue), forKey: "channelType")

		if target == .copy || target == .mutableCopy {
			return dic as! [String: Any]
		}

		return dic.removingDefaults(defaultsStorage, allowEmptyValues: true) as! [String: Any]
	}

	override public func isEqual(_ object: Any?) -> Bool {
		guard let object = object as? ChannelConfig else {
			return false
		}

		if self === object {
			return true
		}

		return NSDictionary(dictionary: dictionaryValue).isEqual(to: object.dictionaryValue)
			&& secretKeyStorage == object.secretKeyStorage
	}

	override public var hash: Int {
		uniqueIdentifierStorage.hashValue
	}

	override public func copy(asMutable mutableCopy: Bool, uniquing: Bool) -> Any {
		let config = super.copy(asMutable: mutableCopy, uniquing: false) as! ChannelConfig

		config.defaultsStorage = defaultsStorage
		config.secretKeyStorage = secretKeyStorage

		if uniquing {
			config.uniqueIdentifierStorage = NSString.withUUID()
		}

		return config
	}

	override public var mutableClass: XRPortablePropertyDict {
		unsafeBitCast(MutableChannelConfig.self, to: XRPortablePropertyDict.self)
	}

	@objc public func writeSecretKeyToKeychain() {
		guard let secretKeyStorage else {
			return
		}

		XRKeychain.modifyOrAddItem(
			"Glasstual (Channel JOIN Key)",
			withItemKind: "application password",
			forUsername: nil,
			withNewPassword: secretKeyStorage,
			serviceName: secretKeyServiceName
		)

		self.secretKeyStorage = nil
	}

	@objc public func destroySecretKeyKeychainItem() {
		XRKeychain.deleteItem(
			"Glasstual (Channel JOIN Key)",
			withItemKind: "application password",
			forUsername: nil,
			serviceName: secretKeyServiceName
		)

		secretKeyStorage = nil
	}

	@objc(soundForEvent:)
	public func sound(forEvent event: TXNotificationType) -> String? {
		guard let key = TPCPreferences.key(forEvent: event, category: "Sound") else {
			return nil
		}

		return notificationsLock.withLock { notificationsStorage[key] as? String }
	}

	@objc(notificationEnabledForEvent:)
	public func notificationEnabled(forEvent event: TXNotificationType) -> NSControl.StateValue {
		state(for: event, category: "Enabled")
	}

	@objc(disabledWhileAwayForEvent:)
	public func disabledWhileAway(forEvent event: TXNotificationType) -> NSControl.StateValue {
		state(for: event, category: "Disable While Away")
	}

	@objc(bounceDockIconForEvent:)
	public func bounceDockIcon(forEvent event: TXNotificationType) -> NSControl.StateValue {
		state(for: event, category: "Bounce Dock Icon")
	}

	@objc(bounceDockIconRepeatedlyForEvent:)
	public func bounceDockIconRepeatedly(forEvent event: TXNotificationType) -> NSControl.StateValue {
		state(for: event, category: "Bounce Dock Icon Repeatedly")
	}

	@objc(speakEvent:)
	public func speakEvent(_ event: TXNotificationType) -> NSControl.StateValue {
		state(for: event, category: "Speak")
	}

	fileprivate func setSoundStorage(_ value: String?, forEvent event: TXNotificationType) {
		guard let key = TPCPreferences.key(forEvent: event, category: "Sound") else {
			return
		}

		notificationsLock.withLock {
			notificationsStorage[key] = value
		}
	}

	fileprivate func setState(_ value: NSControl.StateValue, forEvent event: TXNotificationType, category: String) {
		guard let key = TPCPreferences.key(forEvent: event, category: category) else {
			return
		}

		notificationsLock.withLock {
			switch value {
			case .on:
				notificationsStorage[key] = true
			case .off:
				notificationsStorage[key] = false
			case .mixed:
				_ = notificationsStorage.removeValue(forKey: key)
			default:
				assertionFailure("Bad notification state")
			}
		}
	}

	private func state(for event: TXNotificationType, category: String) -> NSControl.StateValue {
		guard let key = TPCPreferences.key(forEvent: event, category: category) else {
			return .off
		}

		return notificationsLock.withLock {
			guard let value = notificationsStorage[key] as? NSNumber else {
				return .mixed
			}

			return value.boolValue ? .on : .off
		}
	}

	private func assignBool(_ key: String, to storage: inout Bool, in dictionary: NSDictionary) {
		var value = ObjCBool(storage)
		dictionary.assignBool(to: &value, forKey: key)
		storage = value.boolValue
	}

	private func migrateInlineMediaSettings(from dictionary: [String: Any]) {
		if dictionary["inlineMediaEnabled"] != nil, dictionary["inlineMediaDisabled"] != nil {
			return
		}

		guard let ignoreInlineMedia = dictionary["ignoreInlineMedia"] as? NSNumber,
		      ignoreInlineMedia.boolValue
		else {
			return
		}

		inlineMediaDisabledStorage = TPCPreferences.showInlineMedia()
		inlineMediaEnabledStorage = !inlineMediaDisabledStorage
	}
}

@objc(IRCChannelConfigMutable)
public final class MutableChannelConfig: ChannelConfig {
	override public class var isMutable: Bool {
		true
	}

	override public var immutableClass: XRPortablePropertyDict {
		unsafeBitCast(ChannelConfig.self, to: XRPortablePropertyDict.self)
	}

	@objc override public var type: IRCChannelType {
		get { typeStorage }
		set { typeStorage = newValue }
	}

	@objc override public var autoJoin: Bool {
		get { autoJoinStorage }
		set { autoJoinStorage = newValue }
	}

	@objc override public var ignoreGeneralEventMessages: Bool {
		get { ignoreGeneralEventMessagesStorage }
		set { ignoreGeneralEventMessagesStorage = newValue }
	}

	@objc override public var ignoreHighlights: Bool {
		get { ignoreHighlightsStorage }
		set { ignoreHighlightsStorage = newValue }
	}

	@objc override public var inlineMediaDisabled: Bool {
		get { inlineMediaDisabledStorage }
		set { inlineMediaDisabledStorage = newValue }
	}

	@objc override public var inlineMediaEnabled: Bool {
		get { inlineMediaEnabledStorage }
		set { inlineMediaEnabledStorage = newValue }
	}

	@objc override public var pushNotifications: Bool {
		get { pushNotificationsStorage }
		set { pushNotificationsStorage = newValue }
	}

	@objc override public var showTreeBadgeCount: Bool {
		get { showTreeBadgeCountStorage }
		set { showTreeBadgeCountStorage = newValue }
	}

	@objc override public var channelName: String {
		get { channelNameStorage }
		set { channelNameStorage = newValue }
	}

	@objc override public var label: String? {
		get { labelStorage }
		set { labelStorage = newValue }
	}

	@objc override public var defaultModes: String? {
		get { defaultModesStorage }
		set { defaultModesStorage = newValue }
	}

	@objc override public var defaultTopic: String? {
		get { defaultTopicStorage }
		set { defaultTopicStorage = newValue }
	}

	@objc override public var secretKey: String? {
		get { secretKeyStorage ?? secretKeyFromKeychain }
		set { secretKeyStorage = newValue }
	}

	@objc(setSound:forEvent:)
	public func setSound(_ value: String?, forEvent event: TXNotificationType) {
		setSoundStorage(value, forEvent: event)
	}

	@objc(setNotificationEnabled:forEvent:)
	public func setNotificationEnabled(_ value: NSControl.StateValue, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, category: "Enabled")
	}

	@objc(setDisabledWhileAway:forEvent:)
	public func setDisabledWhileAway(_ value: NSControl.StateValue, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, category: "Disable While Away")
	}

	@objc(setBounceDockIcon:forEvent:)
	public func setBounceDockIcon(_ value: NSControl.StateValue, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, category: "Bounce Dock Icon")
	}

	@objc(setBounceDockIconRepeatedly:forEvent:)
	public func setBounceDockIconRepeatedly(_ value: NSControl.StateValue, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, category: "Bounce Dock Icon Repeatedly")
	}

	@objc(setEventIsSpoken:forEvent:)
	public func setEventIsSpoken(_ value: NSControl.StateValue, forEvent event: TXNotificationType) {
		setState(value, forEvent: event, category: "Speak")
	}
}
