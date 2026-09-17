// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Log line")
struct LogLineTests {
	@Test("New history uses a versioned Codable payload and refuses unknown versions")
	func versionedHistoryPayload() throws {
		let line = LogLine()
		let entry = line.historicEntry(forView: "view")
		let dictionary = try #require(PropertyListSerialization.propertyList(from: entry.data, format: nil) as? [String: Any])
		#expect(dictionary["version"] as? Int == 1)
		#expect(dictionary["$archiver"] == nil)
		var unsupported = LogLineStoredPayload(line: line)
		unsupported.version += 1
		#expect(try LogLine(data: PropertyListEncoder().encode(unsupported)) == nil)
	}

	@Test("The message identifier survives a Codable history round trip")
	func messageIdentifierSurvivesArchiving() throws {
		var line = LogLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.messageBody = "hello"
		line.messageIdentifier = "63E1033A0"

		let data = line.historicEntry(forView: "test-view").data
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.messageIdentifier == "63E1033A0")
		#expect(decoded.uniqueIdentifier == line.uniqueIdentifier)
		#expect(decoded.messageBody == "hello")
	}

	@Test("A line with no message identifier decodes without one")
	func messageIdentifierIsOptional() throws {
		var line = LogLine()
		line.messageBody = "hello"

		let data = line.historicEntry(forView: "test-view").data
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.messageIdentifier == nil)
	}

	/// Scrollback is stored as this archive, so a field the encoder forgets is a
	/// field the user loses on relaunch. Every property a line carries is set to
	/// something distinguishable and read back off the decoded value.
	@Test("Every value a line carries survives the scrollback archive")
	func archivePreservesCompleteValueState() throws {
		let receivedAt = Date(timeIntervalSince1970: 1_725_000_000)
		var line = LogLine()
		line.isEncrypted = true
		line.isFirstForDay = true
		line.receivedAt = receivedAt
		line.nickname = "alice"
		line.messageBody = "hello"
		line.command = "PRIVMSG"
		line.messageIdentifier = "message-id"
		line.replyToMessageIdentifier = "parent-id"
		line.reactions = ["👍": ["bob", "carol"]]
		line.lineType = .privateMessage
		line.memberType = .localUser
		line.deliveryState = .delivered
		line.highlightKeywords = ["hello"]
		line.excludeKeywords = ["ignore"]

		let data = line.historicEntry(forView: "test-view").data
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.isEncrypted)
		#expect(decoded.isFirstForDay)
		#expect(decoded.receivedAt == receivedAt)
		#expect(decoded.nickname == "alice")
		#expect(decoded.messageBody == "hello")
		#expect(decoded.command == "PRIVMSG")
		#expect(decoded.messageIdentifier == "message-id")
		#expect(decoded.replyToMessageIdentifier == "parent-id")
		#expect(decoded.reactions == ["👍": ["bob", "carol"]])
		#expect(decoded.lineType == .privateMessage)
		#expect(decoded.memberType == .localUser)
		#expect(decoded.deliveryState == .delivered)
		#expect(decoded.highlightKeywords == ["hello"])
		#expect(decoded.excludeKeywords == ["ignore"])
		#expect(decoded.uniqueIdentifier == line.uniqueIdentifier)
		#expect(decoded.sessionIdentifier == line.sessionIdentifier)
	}

	@Test("A pending delivery state is not carried out of the archive")
	func pendingDeliveryStateIsNotRestoredFromArchive() throws {
		var line = LogLine()
		line.deliveryState = .pending

		let data = line.historicEntry(forView: "test-view").data
		let decoded = try #require(LogLine(data: data))

		#expect(decoded.deliveryState == LogLineDeliveryState.none)
		#expect(decoded.deliveryStateString == nil)
	}

	@Test("The renderer's names for the line and member types are the ones the templates read")
	func lineTypeAndMemberTypeStringsRetainRendererValues() {
		#expect(LogLine.string(for: .actionNoHighlight) == "action")
		#expect(LogLine.string(for: .ctcpReply) == "ctcp")
		#expect(LogLine.string(for: .dccFileTransfer) == "dcc-file-transfer")
		#expect(LogLine.string(for: .offTheRecordEncryptionStatus) == "off-the-record-encryption-status")
		#expect(LogLine.string(for: .privateMessageNoHighlight) == "privmsg")
		#expect(LogLine.string(for: .undefined) == nil)
		#expect(LogLine.string(for: .localUser) == "myself")
		#expect(LogLine.string(for: .normal) == "normal")
	}
}
