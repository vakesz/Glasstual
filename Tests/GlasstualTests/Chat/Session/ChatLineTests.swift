// Copyright (c) 2008 - 2010 Satoshi Nakagawa <psychs AT limechat DOT net>
// Copyright (c) 2010 - 2018 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("Log line")
struct ChatLineTests {
	@Test("New history uses a versioned Codable payload and refuses unknown versions")
	func versionedHistoryPayload() throws {
		let line = ChatLine()
		let entry = line.scrollbackEntry(forView: "view")
		let dictionary = try #require(PropertyListSerialization.propertyList(from: entry.data, format: nil) as? [String: Any])
		#expect(dictionary["version"] as? Int == 1)
		#expect(dictionary["$archiver"] == nil)
		var unsupported = ChatLineStoredPayload(line: line)
		unsupported.version += 1
		#expect(try ChatLine(data: PropertyListEncoder().encode(unsupported)) == nil)
	}

	@Test("The message identifier survives a Codable history round trip")
	func messageIdentifierSurvivesArchiving() throws {
		var line = ChatLine()
		line.command = "privmsg"
		line.lineType = .privateMessage
		line.nickname = "alice"
		line.messageBody = "hello"
		line.messageIdentifier = "63E1033A0"

		let data = line.scrollbackEntry(forView: "test-view").data
		let decoded = try #require(ChatLine(data: data))

		#expect(decoded.messageIdentifier == "63E1033A0")
		#expect(decoded.uniqueIdentifier == line.uniqueIdentifier)
		#expect(decoded.messageBody == "hello")
	}

	@Test("A line with no message identifier decodes without one")
	func messageIdentifierIsOptional() throws {
		var line = ChatLine()
		line.messageBody = "hello"

		let data = line.scrollbackEntry(forView: "test-view").data
		let decoded = try #require(ChatLine(data: data))

		#expect(decoded.messageIdentifier == nil)
	}

	/// Scrollback is stored as this archive, so a field the encoder forgets is a
	/// field the user loses on relaunch. Every property a line carries is set to
	/// something distinguishable and read back off the decoded value.
	@Test("Every value a line carries survives the scrollback archive")
	func archivePreservesCompleteValueState() throws {
		let receivedAt = Date(timeIntervalSince1970: 1_725_000_000)
		var line = ChatLine()
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

		let data = line.scrollbackEntry(forView: "test-view").data
		let decoded = try #require(ChatLine(data: data))

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
		var line = ChatLine()
		line.deliveryState = .pending

		let data = line.scrollbackEntry(forView: "test-view").data
		let decoded = try #require(ChatLine(data: data))

		#expect(decoded.deliveryState == ChatLineDeliveryState.none)
	}

	/// The checked-in row a user's database would hold. Read from the source tree
	/// rather than bundled, so the file a reviewer edits is the file the test reads.
	private static var storedPayloadFixture: URL {
		RepositoryPaths.corpora.appending(path: "History/ScrollbackPayload-v1.plist")
	}

	@Test("A checked-in stored row still decodes into every value it carried")
	func storedPayloadFixtureDecodes() throws {
		let data = try Data(contentsOf: Self.storedPayloadFixture)
		let line = try #require(ChatLine(data: data))

		#expect(line.isEncrypted)
		#expect(line.isFirstForDay)
		#expect(line.receivedAt == Date(timeIntervalSince1970: 1_725_000_000))
		#expect(line.messageBody == "hello from the fixture")
		#expect(line.command == "PRIVMSG")
		#expect(line.messageIdentifier == "fixture-message")
		#expect(line.replyToMessageIdentifier == "fixture-parent")
		#expect(line.reactions == ["👍": ["bob", "carol"]])
		#expect(line.lineType == .privateMessage)
		#expect(line.memberType == .localUser)
		#expect(line.deliveryState == .delivered)
		#expect(line.highlightKeywords == ["fixture"])
		#expect(line.excludeKeywords == ["ignore me"])
		#expect(line.nickname == "alice")
		#expect(line.sessionIdentifier == 77)
		#expect(line.uniqueIdentifier == "fixture-line")
	}

	/** Renaming a `ChatLine` property invalidates every row already on disk, and
	 the compiler says nothing about it. `ChatLine.CodingKeys` is what stops that,
	 and this is what stops the enum from being edited to follow a rename. */
	@Test("The stored field names are the ones the fixture on disk carries")
	func storedPayloadFieldNamesAreUnchanged() throws {
		let fixture = try #require(try PropertyListSerialization.propertyList(
			from: Data(contentsOf: Self.storedPayloadFixture), format: nil
		) as? [String: Any])
		let line = try #require(try ChatLine(data: Data(contentsOf: Self.storedPayloadFixture)))
		let encoded = try #require(PropertyListSerialization.propertyList(
			from: line.scrollbackEntry(forView: "view").data, format: nil
		) as? [String: Any])

		#expect(Set(encoded.keys) == Set(fixture.keys))
		#expect(Set(encoded.keys) == ["version", "line"])
		#expect(encoded["version"] as? Int == ChatLineStoredPayload.currentVersion)

		let fixtureLine = try #require(fixture["line"] as? [String: Any])
		let encodedLine = try #require(encoded["line"] as? [String: Any])

		#expect(Set(encodedLine.keys) == Set(fixtureLine.keys))
		#expect(Set(encodedLine.keys) == Set(ChatLine.CodingKeys.allCases.map(\.rawValue)))
	}

	@Test("The renderer's names for the line and member types are the ones the templates read")
	func lineTypeAndMemberTypeStringsRetainRendererValues() {
		#expect(ChatLine.string(for: .actionNoHighlight) == "action")
		#expect(ChatLine.string(for: .ctcpReply) == "ctcp")
		#expect(ChatLine.string(for: .dccFileTransfer) == "dcc-file-transfer")
		#expect(ChatLine.string(for: .offTheRecordEncryptionStatus) == "off-the-record-encryption-status")
		#expect(ChatLine.string(for: .privateMessageNoHighlight) == "privmsg")
		#expect(ChatLine.string(for: .undefined) == nil)
		#expect(ChatLine.string(for: .localUser) == "myself")
		#expect(ChatLine.string(for: .normal) == "normal")
	}
}
