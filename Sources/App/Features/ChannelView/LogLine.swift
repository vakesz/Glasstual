/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
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

public nonisolated enum LogLineFormat { // nonisolated: value
	static let actionNickname = "%@ "
	/// The command a line Glasstual printed itself carries, in place of the
	/// server command a line off the wire has.
	public static let defaultCommand = "-100"
	static let loggerActionNickname = "\u{2022} %n:"
	static let loggerClock = "[%Y-%m-%dT%H:%M:%S%z]"
	static let loggerNoticeNickname = "-%n-"
	static let loggerUndefinedNickname = "<%@%n>"
	static let noticeNickname = "-%@-"
	static let specialNoticeMessage = "[%@]: %@"
}

/** One printed line: what the renderer draws and what the historic log stores.

 A value. Every field is a `Sendable` value, so a line crosses into the render
 pipeline as itself rather than through a hand-written snapshot, and a line a
 controller has already queued cannot change underneath it. `uniqueIdentifier`
 is its identity: assigned once when the line is created and carried through
 every copy and every archive.

 Archiving lives on ``LogLineArchive``. `NSKeyedArchiver` needs a class, and the
 archives on disk name `TVCLogLine` as their root object, so the envelope wears
 that name and this type stays free of Objective-C. */
public nonisolated struct LogLine: Codable, Hashable, Sendable, CustomStringConvertible { // nonisolated: value
	public internal(set) var isEncrypted = false
	public internal(set) var isFirstForDay = false
	public internal(set) var receivedAt = Date()
	public internal(set) var messageBody = ""
	public internal(set) var command = LogLineFormat.defaultCommand
	public internal(set) var messageIdentifier: String?
	public internal(set) var replyToMessageIdentifier: String?
	public internal(set) var reactions: [String: [String]]?
	public internal(set) var lineType: LogLineType = .undefined
	public internal(set) var memberType: LogLineMemberType = .normal
	public internal(set) var deliveryState: LogLineDeliveryState = .none
	public internal(set) var highlightKeywords: [String]?
	public internal(set) var excludeKeywords: [String]?

	public internal(set) var nickname: String?
	public private(set) var sessionIdentifier: UInt = 0

	/// The line's identity, stable across copies and archives.
	public private(set) var uniqueIdentifier = ""

	public init() {
		populateDefaultsPostflight()
	}

	public init?(data: Data) {
		guard let archive = try? NSKeyedUnarchiver.unarchivedObject(
			ofClass: LogLineArchive.self,
			from: data
		) else {
			return nil
		}

		self = archive.line
	}

	static func logLine(from historicEntry: HistoricLogEntry) -> LogLine? {
		guard var line = LogLine(data: historicEntry.data) else {
			return nil
		}

		if line.uniqueIdentifier.isEmpty {
			line.uniqueIdentifier = historicEntry.uniqueIdentifier
		}

		return line
	}

	/// Fills in the identifiers a fresh line needs and folds the two retired
	/// "no highlight" line types onto their live equivalents.
	mutating func populateDefaultsPostflight() {
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

	public mutating func populateDefaultUniqueIdentifier() {
		if uniqueIdentifier.isEmpty {
			uniqueIdentifier = Self.newUniqueIdentifier()
		}
	}

	public mutating func populateDefaultSessionIdentifier() {
		if sessionIdentifier == 0 {
			sessionIdentifier = Self.currentSessionIdentifier()
		}
	}

	/// Restores the state an archive carried. Only ``LogLineArchive`` calls it.
	mutating func restore(from decoded: LogLineArchive.DecodedValues) {
		receivedAt = decoded.receivedAt
		excludeKeywords = decoded.excludeKeywords
		highlightKeywords = decoded.highlightKeywords
		isEncrypted = decoded.isEncrypted
		isFirstForDay = decoded.isFirstForDay
		command = decoded.command
		messageBody = decoded.messageBody
		messageIdentifier = decoded.messageIdentifier
		replyToMessageIdentifier = decoded.replyToMessageIdentifier
		reactions = decoded.reactions
		nickname = decoded.nickname
		lineType = decoded.lineType
		memberType = decoded.memberType
		deliveryState = decoded.deliveryState
		uniqueIdentifier = decoded.uniqueIdentifier ?? ""
		sessionIdentifier = decoded.sessionIdentifier
	}

	/// The identifier as the archive recorded it: empty when the archive
	/// carried none, which is what tells the decoder to mint a fresh one.
	var archivedUniqueIdentifier: String? {
		uniqueIdentifier.isEmpty ? nil : uniqueIdentifier
	}

	func historicEntry(forView viewIdentifier: String) -> HistoricLogEntry {
		guard let data = try? NSKeyedArchiver.archivedData(
			withRootObject: LogLineArchive(self),
			requiringSecureCoding: true
		) else {
			preconditionFailure("A log line must remain securely archivable")
		}

		return HistoricLogEntry(
			logLineData: data,
			uniqueIdentifier: uniqueIdentifier,
			viewIdentifier: viewIdentifier,
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

	public var fromCurrentSession: Bool {
		sessionIdentifier == Self.currentSessionIdentifier()
	}

	public static func string(for type: LogLineType) -> String? {
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

	public static func string(for type: LogLineMemberType) -> String {
		type == .localUser ? "myself" : "normal"
	}

	public var lineTypeString: String? {
		Self.string(for: lineType)
	}

	public var memberTypeString: String {
		Self.string(for: memberType)
	}

	public static func string(for state: LogLineDeliveryState) -> String? {
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

	public var deliveryStateString: String? {
		Self.string(for: deliveryState)
	}

	public var formattedTimestamp: String {
		formattedTimestamp(with: nil)
	}

	public func formattedTimestamp(with format: String?) -> String {
		let themeFormat = ThemeController.activeSnapshot?.timestampFormat
		let selectedFormat = [
			format,
			themeFormat,
		]
		.compactMap(\.self)
		.first { !$0.isEmpty } ?? ""

		return Glasstual.formattedTimestamp(receivedAt as NSDate, selectedFormat as NSString) as String? ?? ""
	}

	@MainActor public var formattedNickname: String {
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

	@MainActor public var renderedBodyForTranscriptLog: String {
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

	/// Names the line without formatting it: the identifier is what a failure
	/// log needs in order to find it again in the archive.
	public var description: String {
		"<LogLine \(uniqueIdentifier) \(lineTypeString ?? "undefined")>"
	}

	private enum Session {
		static let identifier = UInt(UInt32.random(in: 0 ..< 999_999))
	}
}
