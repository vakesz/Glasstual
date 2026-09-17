// Copyright (c) 2010 - 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

nonisolated enum LogLineFormat {
	static let actionNickname = "%@ "
	/// The command a line Glasstual printed itself carries, in place of the
	/// server command a line off the wire has.
	static let defaultCommand = "-100"
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

 A history entry is stored as ``LogLineStoredPayload``, a versioned Codable
 property list. */
nonisolated struct LogLine: Codable, Hashable, Sendable, CustomStringConvertible {
	var isEncrypted = false
	var isFirstForDay = false
	var receivedAt = Date()
	var messageBody = ""
	var command = LogLineFormat.defaultCommand
	var messageIdentifier: String?
	var replyToMessageIdentifier: String?
	var reactions: [String: [String]]?
	var lineType: LogLineType = .undefined
	var memberType: LogLineMemberType = .normal
	var deliveryState: LogLineDeliveryState = .none
	var highlightKeywords: [String]?
	var excludeKeywords: [String]?

	var nickname: String?
	private(set) var sessionIdentifier: UInt = 0

	/// The line's identity, stable across copies and archives.
	private(set) var uniqueIdentifier = ""

	init() {
		populateDefaultsPostflight()
	}

	init?(data: Data) {
		if let payload = try? PropertyListDecoder().decode(LogLineStoredPayload.self, from: data) {
			guard payload.version == LogLineStoredPayload.currentVersion else { return nil }
			self = payload.line
			if deliveryState == .pending {
				deliveryState = .none
			}
			populateDefaultsPostflight()
			return
		}
		return nil
	}

	static func logLine(from historicEntry: ScrollbackEntry) -> LogLine? {
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

	mutating func populateDefaultUniqueIdentifier() {
		if uniqueIdentifier.isEmpty {
			uniqueIdentifier = Self.newUniqueIdentifier()
		}
	}

	mutating func populateDefaultSessionIdentifier() {
		if sessionIdentifier == 0 {
			sessionIdentifier = Self.currentSessionIdentifier()
		}
	}

	/// Restores the two identities a stored line carried. Every other field is
	/// settable within the module; these are the line's own. A stored line that
	/// carried none leaves them empty, which is what tells
	/// `populateDefaultsPostflight` to mint a fresh one.
	mutating func restoreIdentity(uniqueIdentifier: String?, sessionIdentifier: UInt) {
		self.uniqueIdentifier = uniqueIdentifier ?? ""
		self.sessionIdentifier = sessionIdentifier
	}

	/// The identifier as the archive recorded it: empty when the archive
	/// carried none, which is what tells the decoder to mint a fresh one.
	var archivedUniqueIdentifier: String? {
		uniqueIdentifier.isEmpty ? nil : uniqueIdentifier
	}

	func historicEntry(forView viewIdentifier: String) -> ScrollbackEntry {
		guard let data = try? PropertyListEncoder().encode(LogLineStoredPayload(line: self)) else {
			preconditionFailure("A log line must remain encodable")
		}

		return ScrollbackEntry(
			logLineData: data,
			uniqueIdentifier: uniqueIdentifier,
			viewIdentifier: viewIdentifier,
			sessionIdentifier: sessionIdentifier,
			creationDate: receivedAt.timeIntervalSince1970
		)
	}

	static func newUniqueIdentifier() -> String {
		String(UUID().uuidString.dropFirst(19))
	}

	static func currentSessionIdentifier() -> UInt {
		Session.identifier
	}

	var fromCurrentSession: Bool {
		sessionIdentifier == Self.currentSessionIdentifier()
	}

	static func string(for type: LogLineType) -> String? {
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

	static func string(for type: LogLineMemberType) -> String {
		type == .localUser ? "myself" : "normal"
	}

	var lineTypeString: String? {
		Self.string(for: lineType)
	}

	var memberTypeString: String {
		Self.string(for: memberType)
	}

	static func string(for state: LogLineDeliveryState) -> String? {
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

	var deliveryStateString: String? {
		Self.string(for: deliveryState)
	}

	var formattedTimestamp: String {
		formattedTimestamp(with: nil)
	}

	func formattedTimestamp(with format: String?) -> String {
		let themeFormat = ThemeSnapshotStore.current.timestampFormat
		let selectedFormat = [
			format,
			themeFormat,
		]
		.compactMap(\.self)
		.first { !$0.isEmpty } ?? ""

		return DateFormatting.timestamp(receivedAt, format: selectedFormat) ?? ""
	}

	@MainActor var formattedNickname: String {
		formattedNickname(in: nil) ?? ""
	}

	@MainActor
	func formattedNickname(in channel: Channel?) -> String? {
		formattedNickname(in: channel, with: nil)
	}

	@MainActor
	func formattedNickname(in channel: Channel?, with format: String?) -> String? {
		guard let nickname else {
			return nil
		}

		if format == nil, let decorated = decoratedNicknameForLineType(nickname) {
			return decorated
		}

		return channel?.associatedClient?.formatNickname(nickname, in: channel, withFormat: format)
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

	@MainActor var renderedBodyForTranscriptLog: String {
		renderedBodyForTranscriptLog(in: nil)
	}

	@MainActor
	func renderedBodyForTranscriptLog(in channel: Channel?) -> String {
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
	var description: String {
		"<LogLine \(uniqueIdentifier) \(lineTypeString ?? "undefined")>"
	}

	/** A session identifier for a new process.

	 Never zero, because zero is what tells `populateDefaultSessionIdentifier`
	 that a line has none yet; and drawn from the whole range the archive and
	 the store keep (a signed 64-bit integer), so a later launch does not pick
	 an earlier one's and count that session's lines as its own. */
	static func newSessionIdentifier(using generator: inout some RandomNumberGenerator) -> UInt {
		UInt.random(in: 1 ... UInt(Int64.max), using: &generator)
	}

	private enum Session {
		static let identifier: UInt = {
			var generator = SystemRandomNumberGenerator()
			return newSessionIdentifier(using: &generator)
		}()
	}
}

nonisolated struct LogLineStoredPayload: Codable {
	static let currentVersion = 1
	var version = currentVersion
	let line: LogLine

	/// Reads the stored time without constructing a line or assigning identity.
	static func receivedAt(in data: Data) -> Date? {
		guard let timestamp = try? PropertyListDecoder().decode(Timestamp.self, from: data),
		      timestamp.version == currentVersion else { return nil }
		return timestamp.line.receivedAt
	}

	private struct Timestamp: Decodable {
		let version: Int
		let line: TimestampLine
	}

	private struct TimestampLine: Decodable { let receivedAt: Date }
}
