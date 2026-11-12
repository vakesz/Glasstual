// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// A file-transfer feature that records what the session asked of it.
@MainActor
private final class RecordingFileTransfers: FileTransferPresenting {
	struct Receiver: Equatable {
		let nickname: String
		let filename: String
		let security: DCCOfferSecurity
		let origin: FileTransferOrigin
		let peerIsKnown: Bool
	}

	private(set) var receivers: [Receiver] = []
	private(set) var stoppedBots: [String] = []
	var ipAddress: String? {
		nil
	}

	func lookUpIPAddress(routerAddress _: String?) async -> String? {
		nil
	}

	func addReceiver(
		for _: ServerSession, nickname: String, address _: String, port _: UInt16, filename: String,
		filesize _: UInt64, token _: String?, security: DCCOfferSecurity, origin: FileTransferOrigin, peerIsKnown: Bool
	) -> String? {
		receivers.append(Receiver(nickname: nickname, filename: filename, security: security, origin: origin, peerIsKnown: peerIsKnown))
		return UUID().uuidString
	}

	func offerSender(
		for _: ServerSession, nickname _: String, path _: String, autoOpen _: Bool, accessURL _: URL?, secure _: Bool,
		completion: @escaping (String?) -> Void
	) {
		completion(nil)
	}

	func stopRequestedTransfers(from bot: String, on _: ServerSession) {
		stoppedBots.append(bot)
	}

	func xdccRequestsDidChange(on _: ServerSession) {}

	func sentOfferExists(withToken _: String, on _: ServerSession, peerNickname _: String, filename _: String) -> Bool {
		false
	}

	func sentOfferAccepted(
		withToken _: String, on _: ServerSession, peerNickname _: String, filename _: String,
		address _: String, port _: UInt16, filesize _: UInt64, security _: DCCOfferSecurity
	) -> Bool {
		false
	}

	func resumeRequested(
		at _: UInt64, on _: ServerSession, peerNickname _: String, filename _: String, port _: UInt16, token _: String?
	) -> Bool {
		false
	}

	func resumeAccepted(
		at _: UInt64, on _: ServerSession, peerNickname _: String, filename _: String, port _: UInt16, token _: String?
	) -> Bool {
		false
	}
}

/// `/xdcc` sends exactly the lines it documents, remembers what it asked
/// for, and labels the bot's offer without changing what the user's settings
/// decide about it.
@MainActor
@Suite("XDCC requests")
struct ServerSessionXDCCTests {
	private let fileTransfers = RecordingFileTransfers()

	private func makeSession(
		replyAction: FileTransferRequestBehavior = .openDialog,
		requestsAreKnown: Bool = false
	) -> TestServerSession {
		var settings = ChatSettings.current()
		settings.fileTransferRequestReplyAction = replyAction
		settings.xdccRequestsAreKnownPeers = requestsAreKnown
		let session = TestServerSession(
			configDictionary: ["nickname": "me"],
			nicknamePassword: nil,
			fixture: ChatEnvironmentFixture(settings: settings)
		)
		session.environment.services.fileTransfers = fileTransfers
		session.userNickname = "me"
		session.identity.hostmask = "me!u@h"
		session.markAsLoggedIn()
		session.forwardsProcessedMessages = true
		return session
	}

	private func xdcc(_ arguments: String, on session: TestServerSession) {
		session.handleXDCCCommand(CommandArguments(arguments), command: "XDCC", targetConversation: nil)
	}

	private func receive(_ line: String, on session: TestServerSession, replayed: Bool = false) throws {
		var message = try #require(Message(line: line, on: session))
		message.isReplayed = replayed
		session.processIncomingMessage(message)
	}

	private func sent(_ session: TestServerSession) -> [String] {
		session.sentLines.compactMap { $0 as? String }
	}

	private func printed(_ session: TestServerSession) -> [String] {
		session.printedLines.compactMap { ($0 as? [String: Any])?["messageBody"] as? String }
	}

	@Test("Each subcommand sends the line it documents", arguments: [
		("send Bot #5", ["PRIVMSG Bot :XDCC SEND #5"]),
		("get Bot 5", ["PRIVMSG Bot :XDCC SEND #5"]),
		("list Bot", ["PRIVMSG Bot :XDCC LIST"]),
		("info Bot #7", ["PRIVMSG Bot :XDCC INFO #7"]),
		("cancel Bot", ["PRIVMSG Bot :XDCC CANCEL"]),
		("remove Bot", ["PRIVMSG Bot :XDCC REMOVE"]),
		("remove Bot #3", ["PRIVMSG Bot :XDCC REMOVE #3"]),
		(
			"batch Bot 1-3,#7",
			["PRIVMSG Bot :XDCC SEND #1", "PRIVMSG Bot :XDCC SEND #2", "PRIVMSG Bot :XDCC SEND #3", "PRIVMSG Bot :XDCC SEND #7"]
		),
	])
	func subcommandLines(arguments: String, lines: [String]) {
		let session = makeSession()

		xdcc(arguments, on: session)

		#expect(sent(session) == lines)
	}

	/// `/dcc` and `/xdcc` share one dispatch case, and each still reaches its
	/// own handler.
	@Test("Typed /xdcc and /dcc reach their own handlers")
	func typedCommandsAreDispatched() {
		let session = makeSession()

		session.sendCommand("xdcc list Bot", completeTarget: false, target: nil)
		session.sendCommand("dcc trust d9 once", completeTarget: false, target: nil)

		#expect(sent(session) == ["PRIVMSG Bot :XDCC LIST"])
		/* Answering a question is the message field's alone. */
		#expect(printed(session).contains(String(localized: .IRC.promptAnswerTypedOnly)))
	}

	@Test("Malformed requests send nothing and print the syntax", arguments: [
		"send Bot", "send Bot #0", "send Bot #1000000", "send #channel 5", "send -flag 5", "send Bot 5 extra",
		"info Bot", "list Bot extra", "remove Bot five", "batch Bot", "frobnicate Bot",
	])
	func malformedRequests(arguments: String) {
		let session = makeSession()

		xdcc(arguments, on: session)

		#expect(sent(session).isEmpty)
		#expect(session.xdccRequests.isEmpty)
		#expect(printed(session).isEmpty == false)
	}

	@Test("Pack and list requests are remembered; info is not")
	func requestsAreRemembered() {
		let session = makeSession()

		xdcc("send Bot #5", on: session)
		xdcc("list Bot", on: session)
		xdcc("info Bot #6", on: session)

		#expect(session.xdccRequests.requests.map(\.kind) == [.pack(5), .list])
		#expect(printed(session).first == String(localized: .IRC.xdccRequested(String(localized: .IRC.xdccPackLabel("5")), "Bot")))
	}

	@Test("A batch over the limit is refused whole")
	func batchLimit() {
		let session = makeSession()

		xdcc("batch Bot 1-21", on: session)

		#expect(sent(session).isEmpty)
		#expect(printed(session) == [String(localized: .IRC.xdccBatchTooLarge(String(XDCCRequestLedger.batchLimit)))])
	}

	@Test("Cancel and remove forget the bot's requests; cancel also stops its transfers")
	func cancelAndRemove() {
		let session = makeSession()
		xdcc("send Bot #5", on: session)
		xdcc("send Bot #6", on: session)

		xdcc("remove Bot #5", on: session)
		#expect(session.xdccRequests.requests.map(\.pack) == [6])

		xdcc("cancel bot", on: session)
		#expect(session.xdccRequests.isEmpty)
		#expect(fileTransfers.stoppedBots == ["bot"])
	}

	@Test("The bot's offer is labelled as the requested pack and listed like any other")
	func offerIsMatched() throws {
		let session = makeSession()
		xdcc("send Bot #5", on: session)

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)

		let receiver = try #require(fileTransfers.receivers.first)
		guard case let .xdcc(_, pack) = receiver.origin else {
			Issue.record("The offer was not matched to the request")
			return
		}
		#expect(pack == 5)
		#expect(receiver.peerIsKnown == false)
		#expect(session.xdccRequests.isEmpty)
		#expect(printed(session).contains(String(localized: .IRC.xdccOfferMatched("Bot", String(localized: .IRC.xdccPackLabel("5"))))))
	}

	@Test("With the setting on, a requested pack from the bot's host counts as coming from someone known")
	func requestedPackIsKnownBySetting() throws {
		let session = makeSession(requestsAreKnown: true)
		try receive(":me!u@h JOIN #chan", on: session)
		try receive(":Bot!bot@host.example JOIN #chan", on: session)
		xdcc("send Bot #5", on: session)

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)

		#expect(fileTransfers.receivers.map(\.peerIsKnown) == [true])
	}

	@Test("A request matched on the nickname alone does not vouch for the sender")
	func unboundRequestIsNotKnown() throws {
		let session = makeSession(requestsAreKnown: true)
		xdcc("send Bot #5", on: session)

		try receive(":Bot!other@elsewhere.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)

		#expect(fileTransfers.receivers.map(\.peerIsKnown) == [false])
	}

	@Test("The bot's first notice binds the request to its host, without vouching for it")
	func noticeBindsHost() throws {
		let session = makeSession(requestsAreKnown: true)
		xdcc("send Bot #5", on: session)
		try receive(
			":Bot!bot@host.example NOTICE me :** All Slots Full, Added you to the main queue for pack 5 (\"file.mkv\") in position 3.",
			on: session
		)

		try receive(":Bot!other@elsewhere.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)
		#expect(fileTransfers.receivers.map(\.origin) == [.offer])

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)
		#expect(fileTransfers.receivers.last?.origin != .offer)
		#expect(fileTransfers.receivers.last?.peerIsKnown == false)
	}

	@Test("An unrequested offer from the bot is an ordinary offer")
	func unrequestedOffer() throws {
		let session = makeSession(requestsAreKnown: true)

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)

		#expect(fileTransfers.receivers.map(\.origin) == [.offer])
		#expect(fileTransfers.receivers.map(\.peerIsKnown) == [false])
	}

	@Test("Ignore still drops a requested pack, and says so")
	func ignoreStillApplies() throws {
		let session = makeSession(replyAction: .ignore, requestsAreKnown: true)
		xdcc("send Bot #5", on: session)

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 1568397154 5000 1000\u{01}", on: session)

		#expect(fileTransfers.receivers.isEmpty)
		#expect(printed(session).contains(
			String(localized: .IRC.xdccIgnoredBySetting(String(localized: .IRC.xdccPackLabel("5")), "Bot"))
		))
	}

	@Test("A requested pack offered from a private address is still refused")
	func addressRulesStillApply() throws {
		let session = makeSession()
		xdcc("send Bot #5", on: session)

		try receive(":Bot!bot@host.example PRIVMSG me :\u{01}DCC SEND file.mkv 3232235777 5000 1000\u{01}", on: session)

		#expect(fileTransfers.receivers.isEmpty)
		#expect(session.xdccRequests.requests.count == 1)
	}

	@Test("The bot's queue notice updates the request; a replayed one does not")
	func botNotices() throws {
		let session = makeSession()
		xdcc("send Bot #5", on: session)

		try receive(
			":Bot!bot@host.example NOTICE me :** All Slots Full, Added you to the main queue for pack 5 (\"file.mkv\") in position 3.",
			on: session, replayed: true
		)
		#expect(session.xdccRequests.requests.first?.status == .sent)

		try receive(
			":Bot!bot@host.example NOTICE me :** All Slots Full, Added you to the main queue for pack 5 (\"file.mkv\") in position 3.",
			on: session
		)
		#expect(session.xdccRequests.requests.first?.status == .queued(position: 3))
		#expect(session.xdccRequests.requests.first?.filename == "file.mkv")
	}

	@Test("Requests follow the bot's NICK and go when it quits")
	func nickAndQuit() throws {
		let session = makeSession()
		try receive(":me!u@h JOIN #chan", on: session)
		try receive(":Bot!bot@host.example JOIN #chan", on: session)
		xdcc("send Bot #5", on: session)

		try receive(":Bot!bot@host.example NICK :Bot2", on: session)
		#expect(session.xdccRequests.requests.first?.bot == "Bot2")

		try receive(":Bot2!bot@host.example QUIT :bye", on: session)
		#expect(session.xdccRequests.isEmpty)
	}

	@Test("A disconnect forgets every request")
	func disconnectForgets() {
		let session = makeSession()
		xdcc("send Bot #5", on: session)

		session.resetXDCCRequests()

		#expect(session.xdccRequests.isEmpty)
	}

	@Test("/xdcc requests lists what is waiting")
	func listRequests() {
		let session = makeSession()
		xdcc("requests", on: session)
		#expect(printed(session) == [String(localized: .IRC.xdccNoRequests)])

		xdcc("send Bot #5", on: session)
		xdcc("requests", on: session)

		#expect(printed(session).last == String(localized: .IRC.xdccRequestRow(
			String(localized: .IRC.xdccPackLabel("5")), "Bot", String(localized: .IRC.xdccStatusSent)
		)))
	}
}
