// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import AppKit
@testable import Glasstual
import Testing

@MainActor
@Suite("Authoritative labeled delivery", .serialized)
struct LabeledEchoTests {
	enum Reply: CaseIterable {
		case echo, batch, acknowledgement, failure
	}

	@Test("An immediate reply updates one local row and its archive, including before a view exists",
	      arguments: Reply.allCases, [false, true])
	func immediateReply(_ reply: Reply, _ startsVisible: Bool) async throws {
		let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
		try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
		defer { try? FileManager.default.removeItem(at: directory) }
		let store = ScrollbackStore(filenameSetting: ScrollbackFilenameFixture.unique().store)
		let storage = ScrollbackSession(store: store, databaseDirectory: { directory.path }, reportFailure: {
			Issue.record(Comment(rawValue: $0))
		})
		let history = Scrollback(session: storage)
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.linePrintObserver = nil
		session.forwardsProcessedMessages = true
		session.setConnectionTransportForTesting(.connected)
		session.enableCapability([.batch, .labeledResponse, .echoMessage, .serverTime, .messageTags])
		let conversation = try #require(session.findConversationOrCreate("#echo"))
		let window = MainWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
		                        styleMask: .borderless, backing: .buffered, defer: false)
		let controller = TranscriptController(conversation: conversation, in: window, scrollback: history)
		conversation.presentation = controller
		controller.historyPageFetcher = { _ in .page([]) }
		controller.loadsHistoryLazily = { false }
		defer {
			controller.tearDown(.preservingRemoval)
			session.stopAllTimers()
		}
		if startsVisible {
			_ = controller.ensureBackingView()
			await controller.drainRenderJobs()
		}
		let label = try #require(session.registerPendingDelivery(for: conversation))
		session.print("local text", by: "me", in: conversation, as: .privateMessage,
		              command: "PRIVMSG", deliveryLabel: label)
		let local = try #require(session.labeledResponses.pending[label]?.printedLine)
		#expect(local.deliveryState == .pending)
		let serverTime = "2026-09-26T12:00:00.000Z"
		let echo = ":me!u@h PRIVMSG #echo :server rewritten text"
		switch reply {
		case .echo:
			session.connectionDidReceive("@label=\(label);msgid=confirmed;time=\(serverTime) \(echo)")
		case .batch:
			session.connectionDidReceive("@label=\(label) BATCH +response labeled-response")
			session.connectionDidReceive("@batch=response;msgid=confirmed;time=\(serverTime) \(echo)")
			session.connectionDidReceive("BATCH -response")
		case .acknowledgement:
			session.connectionDidReceive("@label=\(label) :server ACK")
		case .failure:
			session.connectionDidReceive("@label=\(label) :server FAIL PRIVMSG DENIED #echo :Rejected")
		}
		// No await separated the local print from the server response.
		await controller.drainRenderJobs()
		if !startsVisible {
			_ = controller.ensureBackingView()
			await controller.drainRenderJobs()
		}
		let rows = try #require(controller.backingView).displayedLines
		#expect(rows.count == 1)
		let row = try #require(rows.first)
		let isEcho = reply == .echo || reply == .batch
		#expect(row.lineNumber == local.uniqueIdentifier)
		#expect(row.body.plainText == (isEcho ? "server rewritten text" : "local text"))
		#expect(row.deliveryState == (reply == .failure ? .failed : .delivered))
		#expect(row.deliveryFailureReason == (reply == .failure ? "Rejected" : nil))
		#expect(row.messageIdentifier == (isEcho ? "confirmed" : nil))
		#expect(row.serverTimestamp == (isEcho ? DateFormatting.date(fromISO8601: serverTime) : nil))
		let entries = await history.fetchOutcome(.newestEntries(forView: conversation.uniqueIdentifier, fetchLimit: 10)).entries
		#expect(entries.count == 1)
		let entry = try #require(entries.first)
		let stored = try #require(ChatLine(entry: entry))
		#expect(stored.messageBody == row.body.plainText)
		#expect(stored.messageIdentifier == row.messageIdentifier)
		#expect(stored.serverTimestamp == row.serverTimestamp)
		#expect(stored.deliveryState == row.deliveryState)
		#expect(entry.creationDate == local.receivedAt.timeIntervalSince1970)
		#expect(history.duplicates.containsMessageIdentifier("confirmed", forView: conversation.uniqueIdentifier) == isEcho)
		#expect(session.labeledResponses.pending.isEmpty)
		_ = await storage.prepareForTermination()
	}
}
