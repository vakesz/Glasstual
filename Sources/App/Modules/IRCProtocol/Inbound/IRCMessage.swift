/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \\ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\\___/_/\_\\__|\\__,_|\\__,_|_|
 *
 * Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
 * Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

@objc(IRCMessage)
open nonisolated class Message: PortablePropertyObject {
	fileprivate var isHistoricStorage = false
	fileprivate var isEventOnlyMessageStorage = false
	fileprivate var isPrintOnlyMessageStorage = false
	fileprivate var senderStorage: Prefix = .init()
	fileprivate var paramsStorage: [String] = []
	fileprivate var receivedAtStorage = Date()
	fileprivate var messageTagsStorage: [String: String] = [:]
	fileprivate var batchTokenStorage: String?
	fileprivate var commandStorage = ""
	fileprivate var messageIdentifierStorage: String?
	fileprivate var senderAccountStorage: String?
	fileprivate var commandNumericStorage: UInt = 0
	fileprivate var parentBatchMessageStorage: MessageBatch?

	@objc public var sender: Prefix {
		senderStorage
	}

	@objc public var command: String {
		commandStorage
	}

	@objc public var commandNumeric: UInt {
		commandNumericStorage
	}

	@objc public var params: [String] {
		paramsStorage
	}

	@objc public var receivedAt: Date {
		receivedAtStorage
	}

	@objc public var isHistoric: Bool {
		isHistoricStorage
	}

	@objc public var isEventOnlyMessage: Bool {
		isEventOnlyMessageStorage
	}

	@objc public var isPrintOnlyMessage: Bool {
		isPrintOnlyMessageStorage
	}

	@objc public var batchToken: String? {
		batchTokenStorage
	}

	@objc public var messageTags: [String: String]? {
		messageTagsStorage
	}

	@objc public var messageIdentifier: String? {
		messageIdentifierStorage
	}

	@objc public var senderAccount: String? {
		senderAccountStorage
	}

	@objc public var parentBatchMessage: MessageBatch? {
		parentBatchMessageStorage
	}

	@objc public var paramsCount: UInt {
		UInt(paramsStorage.count)
	}

	@objc public var senderNickname: String? {
		senderStorage.nickname
	}

	@objc public var senderUsername: String? {
		senderStorage.username
	}

	@objc public var senderAddress: String? {
		senderStorage.address
	}

	@objc public var senderHostmask: String? {
		senderStorage.hostmask
	}

	@objc public var senderIsServer: Bool {
		senderStorage.isServer
	}

	@objc public var sequence: String {
		if paramsStorage.count < 2 {
			return sequence(0)
		}

		return sequence(1)
	}

	override public init() {
		super.init()
		populateDefaultsPostflight()
	}

	@objc(initWithLine:)
	@MainActor
	public convenience init?(line: String) {
		self.init(line: line, on: nil)
	}

	@objc(initWithLine:onClient:)
	@MainActor
	public init?(line: String, on client: IRCClient?) {
		super.init()

		guard parseLine(line, for: client) else {
			return nil
		}

		populateDefaultsPostflight()
	}

	public required init?(coder _: NSCoder) {
		nil
	}

	@objc(populateDefaultsPostflight)
	override public func populateDefaultsPostflight() {
		if commandStorage.isEmpty {
			commandStorage = ""
		}

		if messageTagsStorage.isEmpty {
			messageTagsStorage = [:]
		}

		if paramsStorage.isEmpty {
			paramsStorage = []
		}
	}

	@objc(paramAt:)
	public func param(at index: UInt) -> String {
		let index = Int(index)

		if index < paramsStorage.count {
			return paramsStorage[index]
		}

		return ""
	}

	@objc(sequence:)
	public func sequence(_ index: UInt) -> String {
		let start = Int(index)
		guard start < paramsStorage.count else {
			return ""
		}

		return paramsStorage[start...].joined(separator: " ")
	}

	@objc
	public func markAsNotHistoric() {
		isHistoricStorage = false
	}

	@objc
	public func markAsHistoric() {
		isHistoricStorage = true
	}

	@objc(populateDuringCopy:mutableCopy:)
	override public func populateDuringCopy(_ newObject: PortablePropertyObject, mutableCopy _: Bool) {
		guard let object = newObject as? Message else {
			return
		}

		object.batchTokenStorage = batchTokenStorage
		object.commandStorage = commandStorage
		object.commandNumericStorage = commandNumericStorage
		object.isHistoricStorage = isHistoricStorage
		object.isEventOnlyMessageStorage = isEventOnlyMessageStorage
		object.isPrintOnlyMessageStorage = isPrintOnlyMessageStorage
		object.messageTagsStorage = messageTagsStorage
		object.messageIdentifierStorage = messageIdentifierStorage
		object.senderAccountStorage = senderAccountStorage
		object.paramsStorage = paramsStorage
		object.receivedAtStorage = receivedAtStorage
		object.senderStorage = senderStorage
		object.parentBatchMessageStorage = parentBatchMessageStorage
	}

	override public var mutableClass: PortablePropertyObject {
		unsafeBitCast(MessageMutable.self, to: PortablePropertyObject.self)
	}

	// MARK: - Line Parser

	@objc(parseLine:forClient:)
	@discardableResult
	@MainActor
	public func parseLine(_ line: String, for client: IRCClient?) -> Bool {
		guard let parsed = LineParser.parsedLine(fromLine: line) else {
			return false
		}

		if let tagSection = parsed.messageTagSection {
			parseExtensions(tagSection, for: client)
		}

		if let senderSection = parsed.senderSection {
			parseSender(senderSection, for: client)
		} else {
			let serverAddress = client?.serverAddress ?? ""
			let sender = MutablePrefix()
			sender.nickname = serverAddress
			sender.hostmask = serverAddress
			sender.isServer = true
			guard let immutableSender = sender.copy() as? Prefix else {
				assertionFailure("Mutable prefixes must produce immutable Prefix copies")
				return false
			}
			senderStorage = immutableSender
		}

		commandStorage = parsed.command
		commandNumericStorage = parsed.commandNumeric
		paramsStorage = parsed.parameters

		return true
	}

	@objc(parseExtensions:forClient:)
	@MainActor
	public func parseExtensions(_ extensionInfo: String, for client: IRCClient?) {
		let parsedTags = MessageTagParser.parsedTags(fromSection: extensionInfo)

		messageTagsStorage = parsedTags.tags
		messageIdentifierStorage = parsedTags.messageIdentifier
		senderAccountStorage = parsedTags.senderAccount

		guard let client else {
			return
		}

		if client.isCapabilityEnabled(.serverTime) {
			let dateString = parsedTags.tags["time"] ?? parsedTags.tags["t"]

			if let dateString {
				let dateObject: Date? = if dateString.unicodeScalars
					.allSatisfy(CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".")).contains)
				{
					Date(timeIntervalSince1970: (dateString as NSString).doubleValue)
				} else {
					sharedISOStandardDateFormatter().date(from: dateString)
				}

				if let dateObject {
					receivedAtStorage = dateObject
					isHistoricStorage = true
				}
			}
		}

		if client.isCapabilityEnabled(.batch) {
			if let batchToken = parsedTags.tags["batch"],
			   batchToken.unicodeScalars.allSatisfy({
			   	CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
			   })
			{
				batchTokenStorage = batchToken
				parentBatchMessageStorage = client.queuedBatchMessage(withToken: batchToken) as? MessageBatch
			}
		}
	}

	@objc(parseSender:forClient:)
	@MainActor
	public func parseSender(_ senderInfo: String, for client: IRCClient?) {
		let sender = MutablePrefix()
		sender.hostmask = senderInfo

		var nickname: NSString?
		var username: NSString?
		var address: NSString?

		if (senderInfo as NSString).hostmaskComponents(
			&nickname,
			username: &username,
			address: &address,
			on: client
		) {
			sender.nickname = nickname as String? ?? ""
			sender.username = username as String?
			sender.address = address as String?
		} else {
			sender.nickname = senderInfo
			sender.isServer = true
		}

		guard let immutableSender = sender.copy() as? Prefix else {
			assertionFailure("Mutable prefixes must produce immutable Prefix copies")
			return
		}
		senderStorage = immutableSender
	}

	public func didReceiveServerInputConcreteObject() -> PluginServerInput {
		let messageObject = PluginServerInput()

		messageObject.senderIsServer = senderIsServer
		messageObject.senderNickname = senderNickname ?? ""
		messageObject.senderUsername = senderUsername
		messageObject.senderAddress = senderAddress
		messageObject.senderHostmask = senderHostmask ?? ""
		messageObject.receivedAt = receivedAt
		messageObject.messageParameters = params
		messageObject.messageSequence = sequence
		messageObject.messageCommand = command
		messageObject.messageCommandNumeric = commandNumeric

		return messageObject
	}
}

@objc(IRCMessageMutable)
public final nonisolated class MessageMutable: Message {
	override public static var isMutable: Bool {
		true
	}

	override public var immutableClass: PortablePropertyObject {
		unsafeBitCast(Message.self, to: PortablePropertyObject.self)
	}

	@objc override public var batchToken: String? {
		get { batchTokenStorage }
		set { batchTokenStorage = newValue }
	}

	@objc override public var command: String {
		get { commandStorage }
		set { commandStorage = newValue }
	}

	@objc override public var commandNumeric: UInt {
		get { commandNumericStorage }
		set { commandNumericStorage = newValue }
	}

	@objc override public var isHistoric: Bool {
		get { isHistoricStorage }
		set { isHistoricStorage = newValue }
	}

	@objc override public var isEventOnlyMessage: Bool {
		get { isEventOnlyMessageStorage }
		set { isEventOnlyMessageStorage = newValue }
	}

	@objc override public var isPrintOnlyMessage: Bool {
		get { isPrintOnlyMessageStorage }
		set { isPrintOnlyMessageStorage = newValue }
	}

	@objc override public var messageTags: [String: String]? {
		get { messageTagsStorage }
		set { messageTagsStorage = newValue ?? [:] }
	}

	@objc override public var messageIdentifier: String? {
		get { messageIdentifierStorage }
		set { messageIdentifierStorage = newValue }
	}

	@objc override public var senderAccount: String? {
		get { senderAccountStorage }
		set { senderAccountStorage = newValue }
	}

	@objc override public var params: [String] {
		get { paramsStorage }
		set { paramsStorage = newValue }
	}

	@objc override public var receivedAt: Date {
		get { receivedAtStorage }
		set { receivedAtStorage = newValue }
	}

	@objc override public var sender: Prefix {
		get { senderStorage }
		set { senderStorage = newValue }
	}
}
