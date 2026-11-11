// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// The File Transfers window lists what each connection waits for from XDCC
/// bots, lets the user withdraw it, and badges the transfer a request became.
@MainActor
@Suite("File transfer XDCC requests")
struct FileTransferXDCCRequestsTests {
	private let center = FileTransferStore(addressSource: { nil })

	private func makeSession() -> TestServerSession {
		let session = TestServerSession(configDictionary: ["nickname": "me"])
		session.environment.services.fileTransfers = center
		session.userNickname = "me"
		session.markAsLoggedIn()
		return session
	}

	private func sent(_ session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	@Test("Requests appear as they are made and go when the session forgets them")
	func requestsFollowTheSession() {
		let session = makeSession()

		session.askXDCCBot("Bot", for: .pack(5, filename: "file.mkv"))
		session.askXDCCBot("Bot", for: .list)

		#expect(center.model.xdccRequests.map(\.request.kind) == [.pack(5), .list])
		#expect(center.model.xdccRequests.first?.request.filename == "file.mkv")

		session.resetXDCCRequests()
		#expect(center.model.xdccRequests.isEmpty)
	}

	@Test("Each session's requests are replaced on their own")
	func sessionsAreSeparate() {
		let first = makeSession()
		let second = makeSession()

		first.askXDCCBot("Bot", for: .pack(1, filename: nil))
		second.askXDCCBot("Bot", for: .pack(2, filename: nil))
		first.resetXDCCRequests()

		#expect(center.model.xdccRequests.map(\.request.kind) == [.pack(2)])
	}

	@Test("Cancelling a queued request removes it from the bot's queue")
	func cancelQueued() throws {
		let session = makeSession()
		session.askXDCCBot("Bot", for: .pack(5, filename: nil))
		let pending = try #require(center.model.xdccRequests.first)

		center.cancelXDCCRequest(pending)

		#expect(sent(session).last == "PRIVMSG Bot :XDCC REMOVE #5")
		#expect(center.model.xdccRequests.isEmpty)
	}

	@Test("Cancelling a request the bot is sending tells it to cancel")
	func cancelSending() throws {
		let session = makeSession()
		session.forwardsProcessedMessages = true
		session.askXDCCBot("Bot", for: .pack(5, filename: nil))
		let message = try #require(Message(
			line: ":Bot!bot@host NOTICE me :** Sending you pack #5 (\"file.mkv\"), which is 700MB. (resume supported)",
			on: session
		))
		session.processIncomingMessage(message)
		let pending = try #require(center.model.xdccRequests.first)
		#expect(pending.request.status == .sending)

		center.cancelXDCCRequest(pending)

		#expect(sent(session).last == "PRIVMSG Bot :XDCC CANCEL")
	}

	@Test("A request reads its pack, file and place in the queue", arguments: [
		(XDCCRequest.Status.sent, String(localized: .FileTransfer.xdccRequestWaiting)),
		(.queued(position: 2), String(localized: .FileTransfer.xdccRequestPosition("2"))),
		(.queued(position: nil), String(localized: .FileTransfer.xdccRequestQueued)),
		(.sending, String(localized: .FileTransfer.xdccRequestSending)),
	])
	func presentation(status: XDCCRequest.Status, text: String) {
		let request = XDCCRequest(
			id: UUID(), bot: "Bot", botUserHost: nil, kind: .pack(5), filename: "file.mkv", size: nil,
			status: status, startupIdentifier: UUID(), requestedAt: .now, refreshedAt: .now
		)

		let presentation = XDCCRequestPresentation(request: request)

		#expect(presentation.title == String(localized: .FileTransfer.xdccRequestTitle("5", "Bot")))
		#expect(presentation.filename == "file.mkv")
		#expect(presentation.status == text)
	}

	@Test("A transfer that answered a request is badged with its pack")
	func requestedBadge() throws {
		let session = makeSession()
		let transfer = try #require(FileTransfer.receiver(
			for: session, center: center, nickname: "Bot", address: "203.0.113.5", port: 1234,
			filename: "file.mkv", filesize: 1024, token: nil
		))

		#expect(FileTransferRowPresentation(transfer: transfer).requestedBadge == nil)
		transfer.origin = .xdcc(requestID: UUID(), pack: 5)
		#expect(FileTransferRowPresentation(transfer: transfer).requestedBadge
			== String(localized: .FileTransfer.requestedPackBadge("5")))
		transfer.origin = .xdcc(requestID: UUID(), pack: nil)
		#expect(FileTransferRowPresentation(transfer: transfer).requestedBadge
			== String(localized: .FileTransfer.requestedListBadge))
		transfer.prepareForPermanentDestruction()
	}

	@Test("Requested packs do not count as known peers unless the user says so")
	func knownPeerSettingDefault() {
		#expect(SettingsKeys.FileTransfers.xdccRequestsAreKnownPeers.defaultValue == false)
		#expect(SettingsKeys.FileTransfers.all.contains { $0.name == SettingsKeys.FileTransfers.xdccRequestsAreKnownPeers.name })
	}
}
