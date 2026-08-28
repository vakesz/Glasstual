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

private nonisolated enum LogLineArchiveKey {
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

private nonisolated enum LogLineFormat {
	static let actionNickname = "%@ "
	static let defaultCommand = "-100"
	static let loggerActionNickname = "\u{2022} %n:"
	static let loggerClock = "[%Y-%m-%dT%H:%M:%S%z]"
	static let loggerNoticeNickname = "-%n-"
	static let loggerUndefinedNickname = "<%@%n>"
	static let noticeNickname = "-%@-"
}

/** One printed line: what the renderer draws and what the historic log stores.

 Still a class, and still `NSSecureCoding`, because the archive on disk records
 `TVCLogLine` as its root object and has to keep decoding. The setters are
 `internal` so that only the module that builds a line can edit it; a printed
 line is handed to `TVCLogController` as a snapshot. */
@objc(TVCLogLine)
public final nonisolated class LogLine: NSObject, NSSecureCoding {
	@objc public internal(set) var isEncrypted = false
	@objc public internal(set) var isFirstForDay = false
	@objc public internal(set) var receivedAt = Date()
	@objc public internal(set) var messageBody = ""
	@objc public internal(set) var command = LogLineFormat.defaultCommand
	@objc public internal(set) var messageIdentifier: String?
	@objc public internal(set) var replyToMessageIdentifier: String?
	@objc public internal(set) var reactions: [String: [String]]?
	@objc public internal(set) var lineType: TVCLogLineType = .undefined
	@objc public internal(set) var memberType: TVCLogLineMemberType = .normal
	@objc public internal(set) var deliveryState: TVCLogLineDeliveryState = .none
	@objc public internal(set) var highlightKeywords: [String]?
	@objc public internal(set) var excludeKeywords: [String]?
	@objc public internal(set) var rendererAttributes: [String: Any]?

	/// Setting a nickname recomputes the colour style, which is derived from it.
	@objc public internal(set) var nickname: String? {
		didSet { computeNicknameColorStyle() }
	}

	private var nicknameColorStyleStorage: String?
	private var uniqueIdentifierStorage: String?

	@objc public private(set) var nicknameColorStyleOverride = false
	@objc public private(set) var sessionIdentifier: UInt = 0

	@objc public var nicknameColorStyle: String {
		nicknameColorStyleStorage ?? ""
	}

	@objc public var uniqueIdentifier: String {
		uniqueIdentifierStorage ?? ""
	}

	override public init() {
		super.init()

		populateDefaultsPostflight()
	}

	public convenience init?(data: Data) {
		guard let decoded = try? NSKeyedUnarchiver.unarchivedObject(ofClass: LogLine.self, from: data) else {
			return nil
		}

		self.init(copying: decoded)
	}

	public required init?(coder: NSCoder) {
		super.init()

		populate(with: coder)
		populateDefaultsPostflight()
	}

	private init(copying source: LogLine) {
		uniqueIdentifierStorage = source.uniqueIdentifierStorage
		isEncrypted = source.isEncrypted
		isFirstForDay = source.isFirstForDay
		excludeKeywords = source.excludeKeywords
		highlightKeywords = source.highlightKeywords
		rendererAttributes = source.rendererAttributes
		receivedAt = source.receivedAt
		command = source.command
		messageBody = source.messageBody
		messageIdentifier = source.messageIdentifier
		replyToMessageIdentifier = source.replyToMessageIdentifier
		reactions = source.reactions
		nickname = source.nickname
		nicknameColorStyleStorage = source.nicknameColorStyleStorage
		nicknameColorStyleOverride = source.nicknameColorStyleOverride
		lineType = source.lineType
		memberType = source.memberType
		deliveryState = source.deliveryState
		sessionIdentifier = source.sessionIdentifier

		super.init()
	}

	/// An independent copy. `TVCLogController` takes one so that a line it has
	/// already queued for rendering cannot change underneath it.
	public func duplicate() -> LogLine {
		LogLine(copying: self)
	}

	@objc(logLineWithData:)
	public static func logLine(with data: Data) -> LogLine? {
		LogLine(data: data)
	}

	static func logLine(from xpcObject: LogLineXPC) -> LogLine? {
		guard let object = try? NSKeyedUnarchiver.unarchivedObject(
			ofClass: LogLine.self,
			from: xpcObject.data
		) else {
			return nil
		}

		if object.uniqueIdentifierStorage == nil {
			object.uniqueIdentifierStorage = xpcObject.uniqueIdentifier
		}

		return object
	}

	private func populate(with decoder: NSCoder) {
		receivedAt = decoder
			.decodeObject(of: NSDate.self, forKey: LogLineArchiveKey.receivedAt) as Date? ?? Date()

		let stringArrayClasses: [AnyClass] = [NSArray.self, NSString.self]
		excludeKeywords = decoder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.excludeKeywords
		) as? [String]
		highlightKeywords = decoder.decodeObject(
			of: stringArrayClasses,
			forKey: LogLineArchiveKey.highlightKeywords
		) as? [String]

		rendererAttributes = decoder.textual_decodeDictionary(
			forKey: LogLineArchiveKey.rendererAttributes
		) as? [String: Any]

		isEncrypted = decoder.decodeBool(forKey: LogLineArchiveKey.isEncrypted)
		isFirstForDay = decoder.decodeBool(forKey: LogLineArchiveKey.isFirstForDay)
		command = decoder.textual_decodeString(forKey: LogLineArchiveKey.command) as String? ?? LogLineFormat
			.defaultCommand
		messageBody = decoder.textual_decodeString(forKey: LogLineArchiveKey.messageBody) as String? ?? ""
		messageIdentifier = decoder.textual_decodeString(forKey: LogLineArchiveKey.messageIdentifier) as String?
		replyToMessageIdentifier = decoder.textual_decodeString(
			forKey: LogLineArchiveKey.replyToMessageIdentifier
		) as String?

		let reactionClasses: [AnyClass] = [NSDictionary.self, NSArray.self, NSString.self]
		reactions = decoder.decodeObject(
			of: reactionClasses,
			forKey: LogLineArchiveKey.reactions
		) as? [String: [String]]
		nickname = decoder.textual_decodeString(forKey: LogLineArchiveKey.nickname) as String?
		lineType = TVCLogLineType(rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.lineType))) ??
			.undefined
		memberType = TVCLogLineMemberType(
			rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.memberType))
		) ?? .normal

		let decodedDeliveryState = TVCLogLineDeliveryState(
			rawValue: UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.deliveryState))
		) ?? .none
		deliveryState = decodedDeliveryState == .pending ? .none : decodedDeliveryState
		uniqueIdentifierStorage = decoder.textual_decodeString(forKey: LogLineArchiveKey.uniqueIdentifier) as String?
		sessionIdentifier = UInt(decoder.decodeInteger(forKey: LogLineArchiveKey.sessionIdentifier))
		computeNicknameColorStyle()
	}

	private func populateDefaultsPostflight() {
		populateDefaultUniqueIdentifier()
		populateDefaultSessionIdentifier()

		switch lineType {
		case .actionNoHighlight:
			lineType = .action
			highlightKeywords = nil
		case .privateMessageNoHighlight:
			lineType = .privateMessage
			highlightKeywords = nil
		default:
			break
		}
	}

	public func populateDefaultUniqueIdentifier() {
		if uniqueIdentifierStorage == nil {
			uniqueIdentifierStorage = Self.newUniqueIdentifier()
		}
	}

	public func populateDefaultSessionIdentifier() {
		if sessionIdentifier == 0 {
			sessionIdentifier = Self.currentSessionIdentifier()
		}
	}

	public func encode(with coder: NSCoder) {
		coder.encode(command as NSString, forKey: LogLineArchiveKey.command)
		coder.encode(messageBody as NSString, forKey: LogLineArchiveKey.messageBody)
		if let excludeKeywords {
			coder.encode(excludeKeywords, forKey: LogLineArchiveKey.excludeKeywords)
		}
		if let highlightKeywords {
			coder.encode(highlightKeywords, forKey: LogLineArchiveKey.highlightKeywords)
		}
		if let rendererAttributes {
			coder.encode(rendererAttributes, forKey: LogLineArchiveKey.rendererAttributes)
		}
		if let messageIdentifier {
			coder.encode(messageIdentifier as NSString, forKey: LogLineArchiveKey.messageIdentifier)
		}
		if let replyToMessageIdentifier {
			coder.encode(
				replyToMessageIdentifier as NSString,
				forKey: LogLineArchiveKey.replyToMessageIdentifier
			)
		}
		if let reactions {
			coder.encode(reactions, forKey: LogLineArchiveKey.reactions)
		}
		if let nickname {
			coder.encode(nickname as NSString, forKey: LogLineArchiveKey.nickname)
		}
		coder.encode(isEncrypted, forKey: LogLineArchiveKey.isEncrypted)
		coder.encode(isFirstForDay, forKey: LogLineArchiveKey.isFirstForDay)
		coder.encode(receivedAt, forKey: LogLineArchiveKey.receivedAt)
		coder.encode(Int(lineType.rawValue), forKey: LogLineArchiveKey.lineType)
		coder.encode(Int(memberType.rawValue), forKey: LogLineArchiveKey.memberType)

		if deliveryState != .none {
			coder.encode(Int(deliveryState.rawValue), forKey: LogLineArchiveKey.deliveryState)
		}

		if let uniqueIdentifierStorage {
			coder.encode(uniqueIdentifierStorage as NSString, forKey: LogLineArchiveKey.uniqueIdentifier)
		}
		coder.encode(Int(sessionIdentifier), forKey: LogLineArchiveKey.sessionIdentifier)
	}

	public static var supportsSecureCoding: Bool {
		true
	}

	@MainActor
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
			sessionIdentifier: sessionIdentifier,
			creationDate: receivedAt.timeIntervalSince1970
		)
	}

	public static func newUniqueIdentifier() -> String {
		String(UUID().uuidString.dropFirst(19))
	}

	public static func currentSessionIdentifier() -> UInt {
		Session.identifier
	}

	@objc public var fromCurrentSession: Bool {
		sessionIdentifier == Self.currentSessionIdentifier()
	}

	public static func string(for type: TVCLogLineType) -> String? {
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

	public static func string(for type: TVCLogLineMemberType) -> String {
		type == .localUser ? "myself" : "normal"
	}

	@objc public var lineTypeString: String? {
		Self.string(for: lineType)
	}

	@objc public var memberTypeString: String {
		Self.string(for: memberType)
	}

	public static func string(for state: TVCLogLineDeliveryState) -> String? {
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
		Self.string(for: deliveryState)
	}

	@objc public var formattedTimestamp: String {
		formattedTimestamp(with: nil)
	}

	public func formattedTimestamp(with format: String?) -> String {
		let themeFormat = ThemeController.activeSnapshot?.timestampFormat
		let selectedFormat = [
			format,
			themeFormat,
			TextualPreferences.themeTimestampFormat(),
			TextualPreferences.themeTimestampFormatDefault(),
		]
		.compactMap(\.self)
		.first { !$0.isEmpty } ?? ""

		return Glasstual.formattedTimestamp(receivedAt as NSDate, selectedFormat as NSString) as String? ?? ""
	}

	@objc @MainActor public var formattedNickname: String {
		formattedNickname(in: nil) ?? ""
	}

	@MainActor
	public func formattedNickname(in channel: IRCChannel?) -> String? {
		formattedNickname(in: channel, with: nil)
	}

	@MainActor
	public func formattedNickname(in channel: IRCChannel?, with format: String?) -> String? {
		guard let nickname else {
			return nil
		}

		if format == nil, let decorated = decoratedNicknameForLineType(nickname) {
			return decorated
		}

		return channel?.associatedClient?.formatNickname(nickname, in: channel, withFormat: format)
	}

	/** The same text as `formattedNickname(in:with:)` but from values the caller
	 already resolved, so that rendering can format the sender off the main actor.
	 `modeSymbol` is the sender's mark in the channel, empty outside one. */
	public func formattedNickname(modeSymbol: String, format: String) -> String? {
		guard let nickname else {
			return nil
		}

		if let decorated = decoratedNicknameForLineType(nickname) {
			return decorated
		}

		return ClientWireUtilities.formatNickname(nickname, modeSymbol: modeSymbol, format: format)
	}

	/// Actions and notices carry their own decoration instead of the theme format.
	private func decoratedNicknameForLineType(_ nickname: String) -> String? {
		switch lineType {
		case .action:
			String(format: LogLineFormat.actionNickname, nickname)
		case .notice:
			String(format: LogLineFormat.noticeNickname, nickname)
		default:
			nil
		}
	}

	@objc @MainActor public var renderedBodyForTranscriptLog: String {
		renderedBodyForTranscriptLog(in: nil)
	}

	@MainActor
	public func renderedBodyForTranscriptLog(in channel: IRCChannel?) -> String {
		var components = [formattedTimestamp(with: LogLineFormat.loggerClock)]

		let nicknameFormat = switch lineType {
		case .action: LogLineFormat.loggerActionNickname
		case .notice: LogLineFormat.loggerNoticeNickname
		default: LogLineFormat.loggerUndefinedNickname
		}

		if let formattedNickname = formattedNickname(in: channel, with: nicknameFormat) {
			components.append(formattedNickname)
		}

		components.append(messageBody)

		return (components.joined(separator: " ") as NSString).stripIRCEffects
	}

	public func computeNicknameColorStyle() {
		guard let nickname, lineType.hasNicknameColor else {
			nicknameColorStyleStorage = nil
			nicknameColorStyleOverride = false
			return
		}

		let colorStyle = UserNicknameColorStyleGenerator.colorStyle(for: nickname)
		nicknameColorStyleStorage = colorStyle.style
		nicknameColorStyleOverride = colorStyle.isOverride
	}

	private enum Session {
		static let identifier = UInt(UInt32.random(in: 0 ..< 999_999))
	}
}

private nonisolated extension TVCLogLineType {
	var hasNicknameColor: Bool {
		switch self {
		case .privateMessage, .privateMessageNoHighlight, .action, .actionNoHighlight:
			true
		default:
			false
		}
	}
}
