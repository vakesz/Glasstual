// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

@MainActor
@Suite("History message references")
struct ChatHistoryReferenceTests {
	@Test("A msgid-only server receives an exact identifier and cannot be sent invalid references",
	      arguments: ["valid-id", "é", "e\u{301}", "", ":invalid", "two words", "line\nfeed"])
	func identifierPagination(_ identifier: String) throws {
		let session = TestServerSession()
		session.isLoggedIn = true
		session.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
		session.supportInfo.processConfigurationData("MSGREFTYPES=msgid")
		let channel = try #require(session.findConversationOrCreate("#history"))
		defer { session.resetChatHistoryState() }
		let request = ServerHistoryRequest(id: UUID(), before: Date(timeIntervalSince1970: 100),
		                                   oldestLineNumber: "local", messageIdentifier: identifier)
		let valid = !identifier.isEmpty && !identifier.hasPrefix(":") && !identifier.contains(" ") && !identifier.contains("\n")
		#expect(session.canRetryServerHistory(for: channel, request: request) == valid)
		#expect(session.requestServerHistory(request, in: channel) == valid)
		let lines = session.sentLines.compactMap { $0 as? String }
		if valid {
			#expect(lines == ["CHATHISTORY BEFORE #history msgid=\(identifier) 100"])
		} else {
			#expect(lines.isEmpty)
		}
	}

	@Test("Local events cannot move the catch-up cursor beyond the last server timestamp", arguments: [false, true])
	func localEventsDoNotSkipMissedHistory(_ hasServerMessage: Bool) throws {
		let session = TestServerSession()
		session.isLoggedIn = true
		session.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
		let channel = try #require(session.findConversationOrCreate("#history"))
		defer { Scrollback.shared.duplicates.forgetViewIfEmpty(channel.uniqueIdentifier) }
		var known = ChatLine()
		known.lineType = .privateMessage
		known.receivedAt = Date(timeIntervalSince1970: 100)
		known.serverTimestamp = hasServerMessage ? known.receivedAt : nil
		var local = ChatLine()
		local.lineType = .debug
		local.receivedAt = Date(timeIntervalSince1970: 5000)
		Scrollback.shared.duplicates.indexChatLines([known, local], forView: channel.uniqueIdentifier)
		defer {
			Scrollback.shared.duplicates.forgetLines([known.uniqueIdentifier, local.uniqueIdentifier], inView: channel.uniqueIdentifier)
		}
		session.requestChatHistory(for: channel)
		let expected = hasServerMessage ? "timestamp=1970-01-01T00:01:40.000Z" : "*"
		#expect(session.sentLines.compactMap { $0 as? String } == ["CHATHISTORY LATEST #history \(expected) 100"])
	}

	@Test("A labeled legacy error numeric promptly retires its history request", arguments: [401, 461, 499])
	func numericHistoryFailure(_ numeric: Int) throws {
		let session = TestServerSession()
		session.isLoggedIn = true
		session.enableCapability([.batch, .labeledResponse, .serverTime, .messageTags, .chatHistory])
		let channel = try #require(session.findConversationOrCreate("#history"))
		let request = ServerHistoryRequest(id: UUID(), before: Date(timeIntervalSince1970: 100), oldestLineNumber: nil)
		#expect(session.requestServerHistory(request, in: channel))
		let pending = try #require(session.chatHistory.serverRequests[channel.uniqueIdentifier])
		let label = try #require(pending.label)
		let message = try #require(Message(line: "@label=\(label) :server \(numeric) me CHATHISTORY :Rejected", on: session))
		session.processIncomingMessageOnMainActor(message)
		#expect(session.chatHistory.serverRequests.isEmpty)
		#expect(pending.timeoutTask == nil)
		#expect(session.canRetryServerHistory(for: channel))
		#expect(session.printedLines.count > 0, "The numeric still follows its ordinary presentation path")
	}

	@Test("An unlabelled error cannot cancel history that later arrives")
	func unlabelledNumericDoesNotCancelHistory() throws {
		let session = TestServerSession()
		session.isLoggedIn = true
		session.enableCapability([.batch, .serverTime, .messageTags, .chatHistory])
		let channel = try #require(session.findConversationOrCreate("#history"))
		let socket = Connection(config: ConnectionConfig(), onSession: session)
		session.socket = socket
		session.setConnectionTransportForTesting(.connected)
		let request = ServerHistoryRequest(id: UUID(), before: Date(timeIntervalSince1970: 100), oldestLineNumber: nil)
		#expect(session.requestServerHistory(request, in: channel))
		let pending = try #require(session.chatHistory.serverRequests[channel.uniqueIdentifier])
		#expect(pending.label == nil)

		session.connectionDidReceive(":server 404 me #history :Cannot send to channel")

		#expect(session.chatHistory.serverRequests[channel.uniqueIdentifier] === pending)

		for wire in [
			":server BATCH +history chathistory #history",
			"@batch=history;time=1970-01-01T00:00:50.000Z :alice!u@h PRIVMSG #history :older",
			":server BATCH -history",
		] {
			session.connectionDidReceive(wire)
		}

		#expect(session.chatHistory.serverRequests.isEmpty)
		#expect(pending.timeoutTask == nil)
		#expect(session.processedMessages.count == 1)
	}

	@Test("Message identifier support respects advertisement removal and reconnect", arguments: [
		("msgid", true), ("timestamp", false), ("timestamp,msgid", true), ("future", false), ("", false),
	])
	func advertisedReferences(_ advertisement: String, _ supported: Bool) {
		let support = SupportInfo()
		#expect(support.chatHistorySupportsMessageIdentifiers)
		support.processConfigurationData("MSGREFTYPES=\(advertisement)")
		#expect(support.chatHistorySupportsMessageIdentifiers == supported)
		support.processConfigurationData("-MSGREFTYPES")
		#expect(support.chatHistorySupportsMessageIdentifiers)
		support.processConfigurationData("MSGREFTYPES=timestamp")
		support.reset()
		#expect(support.chatHistorySupportsMessageIdentifiers)
	}
}
