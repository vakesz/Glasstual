// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation
@testable import Glasstual
import Testing

/// Which offer answers which request, for how long, and what the bot's own
/// words change.
@Suite("XDCC request ledger")
struct XDCCRequestLedgerTests {
	private let startup = UUID()
	private let start = Date(timeIntervalSince1970: 1_800_000_000)
	private let casefold: (String) -> String = { $0.lowercased() }

	private func request(
		bot: String = "Bot",
		userHost: String? = "bot@host.example",
		kind: XDCCRequest.Kind = .pack(5),
		filename: String? = nil,
		startup: UUID? = nil,
		at date: Date? = nil
	) -> XDCCRequest {
		XDCCRequest(
			id: UUID(), bot: bot, botUserHost: userHost, kind: kind, filename: filename, size: nil,
			status: .sent, startupIdentifier: startup ?? self.startup,
			requestedAt: date ?? start, refreshedAt: date ?? start
		)
	}

	private func offer(
		from nickname: String = "bot",
		hostmask: String? = "Bot!bot@host.example",
		filename: String = "file.mkv",
		filesize: UInt64 = 1000,
		startup: UUID? = nil
	) -> XDCCOffer {
		XDCCOffer(
			nickname: nickname, hostmask: hostmask, filename: filename, filesize: filesize,
			startupIdentifier: startup ?? self.startup
		)
	}

	@Test("An offer from the bot is matched once, then never again")
	func matchIsConsumed() {
		var ledger = XDCCRequestLedger()
		let recorded = request()
		let result1 = ledger.record(recorded)
		#expect(result1)

		let result2 = ledger.match(offer(), now: start, casefold: casefold)
		#expect(result2?.id == recorded.id)
		let result3 = ledger.match(offer(), now: start, casefold: casefold)
		#expect(result3 == nil)
	}

	@Test("Another host using the bot's nickname is not the bot")
	func hostMustMatch() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		let result4 = ledger.match(offer(hostmask: "Bot!evil@elsewhere.example"), now: start, casefold: casefold)
		#expect(result4 == nil)
		let result5 = ledger.match(offer(hostmask: nil), now: start, casefold: casefold)
		#expect(result5 == nil)
		#expect(ledger.requests.count == 1)
	}

	@Test("A request made before the bot's host was known matches on nickname")
	func unknownHostMatchesNickname() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request(userHost: nil))

		let result6 = ledger.match(offer(hostmask: nil), now: start, casefold: casefold)
		#expect(result6 != nil)
	}

	@Test("A known file name has to agree, compared in its sanitised form")
	func filenameMustMatch() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request(filename: "file.mkv"))

		let result7 = ledger.match(offer(filename: "other.mkv"), now: start, casefold: casefold)
		#expect(result7 == nil)
		let result8 = ledger.match(offer(filename: "file.mkv"), now: start, casefold: casefold)
		#expect(result8 != nil)
	}

	@Test("An offer on a later connection does not answer a request from an earlier one")
	func otherConnectionDoesNotMatch() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		let result9 = ledger.match(offer(startup: UUID()), now: start, casefold: casefold)
		#expect(result9 == nil)
	}

	@Test("A request expires, unless the bot's queue notice refreshed it")
	func expiryAndRefresh() throws {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())
		let later = start.addingTimeInterval(XDCCRequestLedger.lifetime - 60)
		let past = start.addingTimeInterval(XDCCRequestLedger.lifetime + 60)

		let note = ledger.note(
			.queued(pack: 5, filename: "file.mkv", position: 3),
			from: "BOT",
			hostmask: "Bot!bot@host.example",
			now: later,
			casefold: casefold
		)
		let noted = try #require(note)
		#expect(noted.isWaiting)
		#expect(noted.request.status == .queued(position: 3))
		let result10 = ledger.expire(now: past)
		#expect(result10.isEmpty)
		let result11 = ledger.match(offer(), now: past, casefold: casefold)
		#expect(result11 != nil)

		_ = ledger.record(request())
		let result12 = ledger.match(offer(), now: past, casefold: casefold)
		#expect(result12 == nil)
		let result13 = ledger.expire(now: past)
		#expect(result13.count == 1)
	}

	@Test("A sending notice names the file the offer must then carry")
	func sendingNamesTheFile() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		_ = ledger.note(
			.sending(pack: 5, filename: "real.mkv", sizeText: "1000"),
			from: "Bot",
			hostmask: "Bot!bot@host.example",
			now: start,
			casefold: casefold
		)

		let result14 = ledger.match(offer(filename: "file.mkv"), now: start, casefold: casefold)
		#expect(result14 == nil)
		let result15 = ledger.match(offer(filename: "real.mkv", filesize: 999), now: start, casefold: casefold)
		#expect(result15 == nil)
		let result16 = ledger.match(offer(filename: "real.mkv", filesize: 1000), now: start, casefold: casefold)
		#expect(result16 != nil)
	}

	@Test("An invalid pack or a refusal ends the request; already requested keeps it")
	func botAnswersThatEndRequests() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		let result17 = ledger.note(.alreadyRequested, from: "Bot", hostmask: "Bot!bot@host.example", now: start, casefold: casefold)
		#expect(result17?.isWaiting == true)
		let result18 = ledger.note(.invalidPack, from: "Bot", hostmask: "Bot!bot@host.example", now: start, casefold: casefold)
		#expect(result18?.isWaiting == false)
		#expect(ledger.isEmpty)

		_ = ledger.record(request())
		let result19 = ledger.note(.denied("no slots"), from: "Bot", hostmask: "Bot!bot@host.example", now: start, casefold: casefold)
		#expect(result19?.isWaiting == false)
		#expect(ledger.isEmpty)
	}

	@Test("A notice from another host does not touch a request bound to the bot's host")
	func noticeFromOtherHostIsIgnored() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		let noted = ledger.note(.invalidPack, from: "Bot", hostmask: "Bot!evil@elsewhere.example", now: start, casefold: casefold)

		#expect(noted == nil)
		#expect(ledger.requests.count == 1)
	}

	@Test("Only a host known when the request was sent vouches for the offer")
	func hostPinnedAtRequestVouches() {
		var pinned = XDCCRequestLedger()
		_ = pinned.record(request())
		#expect(pinned.requests.map(\.isBoundToHost) == [true])

		var learned = XDCCRequestLedger()
		_ = learned.record(request(userHost: nil))
		_ = learned.note(.alreadyRequested, from: "Bot", hostmask: "Bot!bot@host.example", now: start, casefold: casefold)
		#expect(learned.requests.map(\.botUserHost) == ["bot@host.example"])
		#expect(learned.requests.map(\.isBoundToHost) == [false])
	}

	@Test("A notice from someone else changes nothing")
	func otherSenderIsIgnored() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		let result20 = ledger.note(.invalidPack, from: "Stranger", now: start, casefold: casefold)
		#expect(result20 == nil)
		#expect(ledger.requests.count == 1)
	}

	@Test("Requests follow the bot's nickname and go when it quits")
	func nicknameAndQuit() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request())

		ledger.nicknameChanged(from: "bot", to: "Bot2", casefold: casefold)
		#expect(ledger.requests.first?.bot == "Bot2")
		let result21 = ledger.match(offer(from: "Bot"), now: start, casefold: casefold)
		#expect(result21 == nil)

		let result22 = ledger.remove(bot: "BOT2", casefold: casefold)
		#expect(result22.count == 1)
		#expect(ledger.isEmpty)
	}

	@Test("A list request matches a text file")
	func listMatchesText() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request(kind: .list))

		let result23 = ledger.match(offer(filename: "file.mkv"), now: start, casefold: casefold)
		#expect(result23 == nil)
		let result24 = ledger.match(offer(filename: "Bot.TXT"), now: start, casefold: casefold)
		#expect(result24 != nil)
	}

	@Test("A session keeps a bounded number of requests")
	func capacity() {
		var ledger = XDCCRequestLedger()
		for _ in 0 ..< XDCCRequestLedger.capacity {
			let result25 = ledger.record(request())
			#expect(result25)
		}

		let result26 = ledger.record(request())
		#expect(result26 == false)
	}

	@Test("Removing by pack leaves the bot's other requests")
	func removeOnePack() {
		var ledger = XDCCRequestLedger()
		_ = ledger.record(request(kind: .pack(5)))
		_ = ledger.record(request(kind: .pack(6)))

		let result27 = ledger.remove(bot: "bot", pack: 5, casefold: casefold)
		#expect(result27.map(\.pack) == [5])
		#expect(ledger.requests.map(\.pack) == [6])
	}

	@Test("The user and host are read from a full hostmask")
	func userHost() {
		#expect(XDCCRequestLedger.userHost(of: "Bot!bot@host") == "bot@host")
		#expect(XDCCRequestLedger.userHost(of: "Bot") == nil)
		#expect(XDCCRequestLedger.userHost(of: nil) == nil)
	}
}
