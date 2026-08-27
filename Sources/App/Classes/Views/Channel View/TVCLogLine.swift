/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import CocoaExtensions
import Foundation

private enum LogLineArchiveKey {
	static let command = "command"
	static let deliveryState = "deliveryState"
	static let excludeKeywords = "excludeKeywords"
	static let highlightKeywords = "highlightKeywords"
	static let isEncrypted = "isEncrypted"
	static let isFirstForDay = "isFirstForDay"
	static let lineType = "lineType"
	static let memberType = "memberType"
	static let messageBody = "messageBody"
	static let messageIdentifier = "messageIdentifier"
	static let nickname = "nickname"
	static let reactions = "reactions"
	static let receivedAt = "receivedAt"
	static let rendererAttributes = "rendererAttributes"
	static let replyToMessageIdentifier = "replyToMessageIdentifier"
	static let sessionIdentifier = "sessionIdentifier"
	static let uniqueIdentifier = "uniqueIdentifier"
}

private enum LogLineFormat {
	static let actionNickname = "%@ "
	static let defaultCommand = "-100"
	static let loggerActionNickname = "\u{2022} %n:"
	static let loggerClock = "[%Y-%m-%dT%H:%M:%S%z]"
	static let loggerNoticeNickname = "-%n-"
	static let loggerUndefinedNickname = "<%@%n>"
	static let noticeNickname = "-%@-"
}

@objc(TVCLogLine)
open class LogLine: PortablePropertyObject {
	fileprivate var isEncryptedStorage = false
	fileprivate var isFirstForDayStorage = false
	fileprivate var nicknameColorStyleOverrideStorage = false
	fileprivate var excludeKeywordsStorage: [String]?
	fileprivate var highlightKeywordsStorage: [String]?
	fileprivate var rendererAttributesStorage: [String: Any]?
	fileprivate var receivedAtStorage = Date()
	fileprivate var commandStorage = LogLineFormat.defaultCommand
	fileprivate var messageBodyStorage = ""
	fileprivate var messageIdentifierStorage: String?
	fileprivate var replyToMessageIdentifierStorage: String?
	fileprivate var reactionsStorage: [String: [String]]?
	fileprivate var nicknameStorage: String?
	fileprivate var nicknameColorStyleStorage: String?
	fileprivate var memberTypeStorage: TVCLogLineMemberType = .normal
	fileprivate var deliveryStateStorage: TVCLogLineDeliveryState = .none
	fileprivate var lineTypeStorage: TVCLogLineType = .undefined
	fileprivate var sessionIdentifierStorage: UInt = 0
	fileprivate var uniqueIdentifierStorage: String?

	@objc public var isEncrypted: Bool {
		isEncryptedStorage
	}

	@objc public var isFirstForDay: Bool {
		isFirstForDayStorage
	}

	@objc public var receivedAt: Date {
		receivedAtStorage
	}

	@objc public var nicknameColorStyle: String {
		nicknameColorStyleStorage ?? ""
	}

	@objc public var nicknameColorStyleOverride: Bool {
		nicknameColorStyleOverrideStorage
	}

	@objc public var nickname: String? {
		nicknameStorage
	}

	@objc public var messageBody: String {
		messageBodyStorage
	}

	@objc public var command: String {
		commandStorage
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage ?? ""
	}

	@objc public var messageIdentifier: String? {
		messageIdentifierStorage
	}

	@objc public var replyToMessageIdentifier: String? {
		replyToMessageIdentifierStorage
	}

	@objc public var reactions: [String: [String]]? {
		reactionsStorage
	}

	@objc public var lineType: TVCLogLineType {
		lineTypeStorage
	}

	@objc public var memberType: TVCLogLineMemberType {
		memberTypeStorage
	}

	@objc public var deliveryState: TVCLogLineDeliveryState {
		deliveryStateStorage
	}

	@objc public var highlightKeywords: [String]? {
		highlightKeywordsStorage
	}

	@objc public var excludeKeywords: [String]? {
		excludeKeywordsStorage
	}

	@objc public var rendererAttributes: [String: Any]? {
		rendererAttributesStorage
	}

	@objc public var sessionIdentifier: UInt {
		sessionIdentifierStorage
	}

	override public init() {
		super.init()
		populateDefaultsPostflight()
	}

	@objc(initWithData:)
	public convenience init?(data: Data) {
		guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LogLine.self, from: data) else {
			return nil
		}

		self.init()
		copyStorage(from: decoded)
	}

	public required init?(coder: NSCoder) {
		super.init(coder: coder)
	}

	@objc(logLineWithData:)
	public class func logLine(with data: Data) -> LogLine? {
		LogLine(data: data)
	}

	@objc(logLineFromXPCObject:)
	class func logLine(from xpcObject: LogLineXPC) -> LogLine? {
		guard let object = try? NSKeyedUnarchiver.unarchivedObject(
			ofClass: LogLine.self,
			from: xpcObject.data
		) else {
			return nil
		}

		if object.uniqueIdentifierStorage == nil {
			object.uniqueIdentifierStorage = xpcObject.uniqueIdentifier
		}

		return object.copy() as? LogLine
	}

	override public func populate(with decoder: NSCoder) -> Bool {
		receivedAtStorage = decoder
			.decodeObject(of: NSDate.self, forKey: LogLineArchiveKey.receivedAt) as Date? ?? Date()

		let stringArrayClasses: [AnyClass] = [NSArray.self, NSString.self]
		excludeKeywordsStorage = decoder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.excludeKeywords
		) as? [String]
		highlightKeywordsStorage = decoder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.highlightKeywords
		) as? [String]

		rendererAttributesStorage = decoder.textual_decodeDictionary(
			forKey: LogLineArchiveKey.rendererAttributes
		) as? [String: Any]

		isEncryptedStorage = decoder.decodeBool(forKey: LogLineArchiveKey.isEncrypted)
		isFirstForDayStorage = decoder.decodeBool(forKey: LogLineArchiveKey.isFirstForDay)
		commandStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.command) as String? ?? LogLineFormat
			.defaultCommand
		messageBodyStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.messageBody) as String? ?? ""
		messageIdentifierStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.messageIdentifier) as String?
		replyToMessageIdentifierStorage = decoder.textual_decodeString(
			forKey: LogLineArchiveKey.replyToMessageIdentifier
		) as String?

		let reactionClasses: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self]
		reactionsStorage = decoder.decodeObject(
			of: reactionClasses,
			forKey: LogLineArchiveKey.reactions
		) as? [String: [String]]
		nicknameStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.nickname) as String?
		lineTypeStorage = TVCLogLineType(rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.lineType))) ??
			.undefined
		memberTypeStorage = TVCLogLineMemberType(
			rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.memberType))
		) ?? .normal

		let decodedDeliveryState = TVCLogLineDeliveryState(
			rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.deliveryState))
		) ?? .none
		deliveryStateStorage = decodedDeliveryState == .pending ? .none : decodedDeliveryState
		uniqueIdentifierStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.uniqueIdentifier) as String?
		sessionIdentifierStorage = UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.sessionIdentifier))
		computeNicknameColorStyle()

		return true
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		populateDefaultUniqueIdentifier()
		populateDefaultSessionIdentifier()

		switch lineTypeStorage {
		case .actionNoHighlight:
			lineTypeStorage = .action
			highlightKeywordsStorage = nil
		case .privateMessageNoHighlight:
			lineTypeStorage = .privateMessage
			highlightKeywordsStorage = nil
		default:
			break
		}
	}

	@objc(populateDefaultUniqueIdentifier)
	public func populateDefaultUniqueIdentifier() {
		if uniqueIdentifierStorage == nil {
			uniqueIdentifierStorage = Self.newUniqueIdentifier()
		}
	}

	@objc(populateDefaultSessionIdentifier)
	public func populateDefaultSessionIdentifier() {
		if sessionIdentifierStorage == 0 {
			sessionIdentifierStorage = Self.currentSessionIdentifier()
		}
	}

	override public func encode(with coder: NSCoder) {
		coder.encode(commandStorage as NSString, forKey: LogLineArchiveKey.command)
		coder.encode(messageBodyStorage as NSString, forKey: LogLineArchiveKey.messageBody)
		if let excludeKeywordsStorage {
			coder.encode(excludeKeywordsStorage, forKey: LogLineArchiveKey.excludeKeywords)
		}
		if let highlightKeywordsStorage {
			coder.encode(highlightKeywordsStorage, forKey: LogLineArchiveKey.highlightKeywords)
		}
		if let rendererAttributesStorage {
			coder.encode(rendererAttributesStorage, forKey: LogLineArchiveKey.rendererAttributes)
		}
		if let messageIdentifierStorage {
			coder.encode(messageIdentifierStorage as NSString, forKey: LogLineArchiveKey.messageIdentifier)
		}
		if let replyToMessageIdentifierStorage {
			coder.encode(
				replyToMessageIdentifierStorage as NSString,
				forKey: LogLineArchiveKey.replyToMessageIdentifier
			)
		}
		if let reactionsStorage {
			coder.encode(reactionsStorage, forKey: LogLineArchiveKey.reactions)
		}
		if let nicknameStorage {
			coder.encode(nicknameStorage as NSString, forKey: LogLineArchiveKey.nickname)
		}
		coder.encode(isEncryptedStorage, forKey: LogLineArchiveKey.isEncrypted)
		coder.encode(isFirstForDayStorage, forKey: LogLineArchiveKey.isFirstForDay)
		coder.encode(receivedAtStorage, forKey: LogLineArchiveKey.receivedAt)
		coder.encode(Int(lineTypeStorage.rawValue), forKey: LogLineArchiveKey.lineType)
		coder.encode(Int(memberTypeStorage.rawValue), forKey: LogLineArchiveKey.memberType)

		if deliveryStateStorage != .none {
			coder.encode(Int(deliveryStateStorage.rawValue), forKey: LogLineArchiveKey.deliveryState)
		}

		if let uniqueIdentifierStorage {
			coder.encode(uniqueIdentifierStorage as NSString, forKey: LogLineArchiveKey.uniqueIdentifier)
		}
		coder.encode(Int(sessionIdentifierStorage), forKey: LogLineArchiveKey.sessionIdentifier)
	}

	override public class var supportsSecureCoding: Bool {
		true
	}

	@objc(xpcObjectForTreeItem:)
	func xpcObject(for treeItem: IRCTreeItem) -> LogLineXPC {
		guard let data = try? NSKeyedArchiver.archivedData(
			withRootObject: self,
			requiringSecureCoding: true
		) else {
			preconditionFailure("A log line must remain securely archivable")
		}

		return LogLineXPC(
			logLineData: data,
			uniqueIdentifier: uniqueIdentifier,
			viewIdentifier: treeItem.uniqueIdentifier,
			sessionIdentifier: sessionIdentifier
		)
	}

	@objc(newUniqueIdentifier)
	public class func newUniqueIdentifier() -> String {
		String(UUID().uuidString.dropFirst(19))
	}

	@objc(currentSessionIdentifier)
	public class func currentSessionIdentifier() -> UInt {
		Session.identifier
	}

	@objc public var fromCurrentSession: Bool {
		sessionIdentifierStorage == Self.currentSessionIdentifier()
	}

	@objc(stringForLineType:)
	public class func string(for type: TVCLogLineType) -> String? {
		switch type {
		case .action, .actionNoHighlight:
			"action"
		case .ctcp, .ctcpQuery, .ctcpReply:
			"ctcp"
		case .dccFileTransfer:
			"dcc-file-transfer"
		case .debug:
			"debug"
		case .invite:
			"invite"
		case .join:
			"join"
		case .kick:
			"kick"
		case .kill:
			"kill"
		case .mode:
			"mode"
		case .nick:
			"nick"
		case .notice:
			"notice"
		case .offTheRecordEncryptionStatus:
			"off-the-record-encryption-status"
		case .part:
			"part"
		case .privateMessage, .privateMessageNoHighlight:
			"privmsg"
		case .quit:
			"quit"
		case .topic:
			"topic"
		case .website:
			"website"
		default:
			nil
		}
	}

	@objc(stringForMemberType:)
	public class func string(for type: TVCLogLineMemberType) -> String {
		type == .localUser ? "myself" : "normal"
	}

	@objc public var lineTypeString: String? {
		Self.string(for: lineTypeStorage)
	}

	@objc public var memberTypeString: String {
		Self.string(for: memberTypeStorage)
	}

	@objc(stringForDeliveryState:)
	public class func string(for state: TVCLogLineDeliveryState) -> String? {
		switch state {
		case .pending:
			"pending"
		case .delivered:
			"delivered"
		case .failed:
			"failed"
		default:
			nil
		}
	}

	@objc public var deliveryStateString: String? {
		Self.string(for: deliveryStateStorage)
	}

	@objc public var formattedTimestamp: String {
		formattedTimestamp(with: nil)
	}

	@objc(formattedTimestampWithFormat:)
	public func formattedTimestamp(with format: String?) -> String {
		let themeFormat = SharedApplication.sharedThemeController().settings.themeTimestampFormat
		let selectedFormat = [
			format,
			themeFormat,
			TextualPreferences.themeTimestampFormat(),
			TextualPreferences.themeTimestampFormatDefault(),
		]
		.compactMap(\.self)
		.first { !$0.isEmpty } ?? ""

		return Glasstual.formattedTimestamp(receivedAtStorage as NSDate, selectedFormat as NSString) as String? ?? ""
	}

	@objc public var formattedNickname: String {
		formattedNickname(in: nil) ?? ""
	}

	@objc(formattedNicknameInChannel:)
	public func formattedNickname(in channel: IRCChannel?) -> String? {
		formattedNickname(in: channel, with: nil)
	}

	@objc(formattedNicknameInChannel:withFormat:)
	public func formattedNickname(in channel: IRCChannel?, with format: String?) -> String? {
		guard let nicknameStorage else {
			return nil
		}

		if format == nil {
			switch lineTypeStorage {
			case .action:
				return String(format: LogLineFormat.actionNickname, nicknameStorage)
			case .notice:
				return String(format: LogLineFormat.noticeNickname, nicknameStorage)
			default:
				break
			}
		}

		return channel?.associatedClient?.formatNickname(nicknameStorage, in: channel, withFormat: format)
	}

	@objc public var renderedBodyForTranscriptLog: String {
		renderedBodyForTranscriptLog(in: nil)
	}

	@objc(renderedBodyForTranscriptLogInChannel:)
	public func renderedBodyForTranscriptLog(in channel: IRCChannel?) -> String {
		var components = [formattedTimestamp(with: LogLineFormat.loggerClock)]

		let nicknameFormat = switch lineTypeStorage {
		case .action: LogLineFormat.loggerActionNickname
		case .notice: LogLineFormat.loggerNoticeNickname
		default: LogLineFormat.loggerUndefinedNickname
		}

		if let formattedNickname = formattedNickname(in: channel, with: nicknameFormat) {
			components.append(formattedNickname)
		}

		components.append(messageBodyStorage)

		return (components.joined(separator: " ") as NSString).stripIRCEffects
	}

	@objc(computeNicknameColorStyle)
	public func computeNicknameColorStyle() {
		guard let nicknameStorage, lineTypeStorage.hasNicknameColor else {
			nicknameColorStyleStorage = nil
			nicknameColorStyleOverrideStorage = false
			return
		}

		var isOverride = ObjCBool(false)
		nicknameColorStyleStorage = UserNicknameColorStyleGenerator.nicknameColorStyle(
			for: nicknameStorage,
			isOverride: &isOverride
		)
		nicknameColorStyleOverrideStorage = isOverride.boolValue
	}

	@objc(populateDuringCopy:mutableCopy:)
	override public func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		guard let object = newObject as? LogLine else {
			return
		}

		object.copyStorage(from: self)
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(MutableLogLine.self, to: PortablePropertyObject.self)
	}

	private func copyStorage(from source: LogLine) {
		uniqueIdentifierStorage = source.uniqueIdentifierStorage
		isEncryptedStorage = source.isEncryptedStorage
		isFirstForDayStorage = source.isFirstForDayStorage
		excludeKeywordsStorage = source.excludeKeywordsStorage
		highlightKeywordsStorage = source.highlightKeywordsStorage
		rendererAttributesStorage = source.rendererAttributesStorage
		receivedAtStorage = source.receivedAtStorage
		commandStorage = source.commandStorage
		messageBodyStorage = source.messageBodyStorage
		messageIdentifierStorage = source.messageIdentifierStorage
		replyToMessageIdentifierStorage = source.replyToMessageIdentifierStorage
		reactionsStorage = source.reactionsStorage
		nicknameStorage = source.nicknameStorage
		nicknameColorStyleStorage = source.nicknameColorStyleStorage
		nicknameColorStyleOverrideStorage = source.nicknameColorStyleOverrideStorage
		lineTypeStorage = source.lineTypeStorage
		memberTypeStorage = source.memberTypeStorage
		deliveryStateStorage = source.deliveryStateStorage
		sessionIdentifierStorage = source.sessionIdentifierStorage
	}

	private enum Session {
		static let identifier = UInt(UInt32.random(in: 0 ..< 999_999))
	}
}

@objc(TVCLogLineMutable)
public final class MutableLogLine: LogLine {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(LogLine.self, to: PortablePropertyObject.self)
	}

	@objc override public var isEncrypted: Bool {
		get { isEncryptedStorage }
		set { isEncryptedStorage = newValue }
	}

	@objc override public var isFirstForDay: Bool {
		get { isFirstForDayStorage }
		set { isFirstForDayStorage = newValue }
	}

	@objc override public var receivedAt: Date {
		get { receivedAtStorage }
		set { receivedAtStorage = newValue }
	}

	@objc override public var nickname: String? {
		get { nicknameStorage }
		set {
			nicknameStorage = newValue
			computeNicknameColorStyle()
		}
	}

	@objc override public var messageBody: String {
		get { messageBodyStorage }
		set { messageBodyStorage = newValue }
	}

	@objc override public var command: String {
		get { commandStorage }
		set { commandStorage = newValue }
	}

	@objc override public var messageIdentifier: String? {
		get { messageIdentifierStorage }
		set { messageIdentifierStorage = newValue }
	}

	@objc override public var replyToMessageIdentifier: String? {
		get { replyToMessageIdentifierStorage }
		set { replyToMessageIdentifierStorage = newValue }
	}

	@objc override public var reactions: [String: [String]]? {
		get { reactionsStorage }
		set { reactionsStorage = newValue }
	}

	@objc override public var lineType: TVCLogLineType {
		get { lineTypeStorage }
		set { lineTypeStorage = newValue }
	}

	@objc override public var memberType: TVCLogLineMemberType {
		get { memberTypeStorage }
		set { memberTypeStorage = newValue }
	}

	@objc override public var deliveryState: TVCLogLineDeliveryState {
		get { deliveryStateStorage }
		set { deliveryStateStorage = newValue }
	}

	@objc override public var highlightKeywords: [String]? {
		get { highlightKeywordsStorage }
		set { highlightKeywordsStorage = newValue }
	}

	@objc override public var excludeKeywords: [String]? {
		get { excludeKeywordsStorage }
		set { excludeKeywordsStorage = newValue }
	}

	@objc override public var rendererAttributes: [String: Any]? {
		get { rendererAttributesStorage }
		set { rendererAttributesStorage = newValue }
	}
}

private extension TVCLogLineType {
	var hasNicknameColor: Bool {
		switch self {
		case .privateMessage, .privateMessageNoHighlight, .action, .actionNoHighlight:
			true
		default:
			false
		}
	}
}
