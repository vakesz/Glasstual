/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
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

/** One line received from the server, parsed.

 A message is a reference type because it is passed down a long handler chain
 and because it points back at the `MessageBatch` that contains it. Handlers
 treat it as read-only; the two places that need a changed message start from
 `duplicate()`, which never touches the receiver. */
@objc(IRCMessage)
public final nonisolated class Message: NSObject {
	public internal(set) var sender = Prefix()
	public internal(set) var command = ""
	public internal(set) var commandNumeric: UInt = 0
	public internal(set) var params: [String] = []
	public internal(set) var receivedAt = Date()
	public internal(set) var isHistoric = false
	public internal(set) var isEventOnlyMessage = false
	public internal(set) var isPrintOnlyMessage = false
	public internal(set) var batchToken: String?
	public internal(set) var messageTags: [String: String]? = [:]
	public internal(set) var messageIdentifier: String?
	public internal(set) var senderAccount: String?
	public internal(set) var parentBatchMessage: MessageBatch?

	public var paramsCount: UInt {
		UInt(params.count)
	}

	public var senderNickname: String? {
		sender.nickname
	}

	public var senderUsername: String? {
		sender.username
	}

	public var senderAddress: String? {
		sender.address
	}

	public var senderHostmask: String? {
		sender.hostmask
	}

	public var senderIsServer: Bool {
		sender.isServer
	}

	public var sequence: String {
		if params.count < 2 {
			return sequence(0)
		}

		return sequence(1)
	}

	override public init() {
		super.init()
	}

	@MainActor
	public convenience init?(line: String) {
		self.init(line: line, on: nil)
	}

	@MainActor
	public init?(line: String, on client: IRCClient?) {
		super.init()

		guard parseLine(line, for: client) else {
			return nil
		}
	}

	private init(copying other: Message) {
		sender = other.sender
		command = other.command
		commandNumeric = other.commandNumeric
		params = other.params
		receivedAt = other.receivedAt
		isHistoric = other.isHistoric
		isEventOnlyMessage = other.isEventOnlyMessage
		isPrintOnlyMessage = other.isPrintOnlyMessage
		batchToken = other.batchToken
		messageTags = other.messageTags
		messageIdentifier = other.messageIdentifier
		senderAccount = other.senderAccount
		parentBatchMessage = other.parentBatchMessage

		super.init()
	}

	/// An editable copy. Handlers treat the message they are given as read-only,
	/// so a rewrite starts here rather than by editing the original.
	public func duplicate() -> Message {
		Message(copying: self)
	}

	public func param(at index: UInt) -> String {
		let index = Int(index)

		if index < params.count {
			return params[index]
		}

		return ""
	}

	public func sequence(_ index: UInt) -> String {
		let start = Int(index)
		guard start < params.count else {
			return ""
		}

		return params[start...].joined(separator: " ")
	}

	public func markAsNotHistoric() {
		isHistoric = false
	}

	public func markAsHistoric() {
		isHistoric = true
	}

	// MARK: - Line Parser

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
			sender = Prefix(nickname: serverAddress, hostmask: serverAddress, isServer: true)
		}

		command = parsed.command
		commandNumeric = parsed.commandNumeric
		params = parsed.parameters

		return true
	}

	@MainActor
	public func parseExtensions(_ extensionInfo: String, for client: IRCClient?) {
		let parsedTags = MessageTagParser.parsedTags(fromSection: extensionInfo)

		messageTags = parsedTags.tags
		messageIdentifier = parsedTags.messageIdentifier
		senderAccount = parsedTags.senderAccount

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
					receivedAt = dateObject
					isHistoric = true
				}
			}
		}

		if client.isCapabilityEnabled(.batch) {
			if let batchToken = parsedTags.tags["batch"],
			   batchToken.unicodeScalars.allSatisfy({
			   	CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-"
			   })
			{
				self.batchToken = batchToken
				parentBatchMessage = client.queuedBatchMessage(withToken: batchToken) as? MessageBatch
			}
		}
	}

	@MainActor
	public func parseSender(_ senderInfo: String, for client: IRCClient?) {
		var parsed = Prefix(hostmask: senderInfo)

		if let components = (senderInfo as NSString).hostmask(on: client) {
			parsed.nickname = components.nickname
			parsed.username = components.username
			parsed.address = components.address
		} else {
			parsed.nickname = senderInfo
			parsed.isServer = true
		}

		sender = parsed
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
