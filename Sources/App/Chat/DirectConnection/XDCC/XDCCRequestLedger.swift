// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/// A request this user sent an XDCC bot, waiting for the bot's offer.
nonisolated struct XDCCRequest: Identifiable, Equatable, Sendable {
	enum Kind: Equatable, Sendable {
		case pack(Int)
		/// `XDCC LIST`, which some bots answer by sending a text file.
		case list
	}

	enum Status: Equatable, Sendable {
		case sent
		case queued(position: Int?)
		/// The bot said it is sending; its offer has not arrived yet.
		case sending
	}

	let id: UUID
	/// The bot's nickname, following its NICK changes.
	var bot: String
	/// The bot's `user@host`, from when the request was made or from the
	/// bot's first notice about it. An offer from the nickname but another
	/// host is not the bot's.
	var botUserHost: String?
	let kind: Kind
	/// The file the request is for, once the announcement or the bot named it.
	var filename: String?
	/// The size in bytes, only when the bot stated it exactly.
	var size: UInt64?
	var status: Status
	/// The connection the request was sent on. An offer arriving on a later
	/// one does not answer it.
	let startupIdentifier: UUID
	let requestedAt: Date
	/// The request expires ``XDCCRequestLedger/lifetime`` after this; a notice
	/// from the bot about it moves it on.
	var refreshedAt: Date
	/// Whether ``botUserHost`` came from the session's own view of the bot when
	/// the request was sent, rather than from whoever answered it later.
	/// Recorded by the ledger.
	private(set) var isHostPinnedAtRequest = false

	var pack: Int? {
		guard case let .pack(pack) = kind else { return nil }
		return pack
	}

	/** Whether an offer that matched is known to come from the bot the user
	 asked: its host was known when the request was sent, and the offer came
	 from that host. A host first learned from an answer only proves that the
	 answer and the offer came from the same place. */
	var isBoundToHost: Bool {
		isHostPinnedAtRequest && botUserHost != nil
	}

	fileprivate mutating func notePinnedAtRequest() {
		isHostPinnedAtRequest = botUserHost != nil
	}
}

/// Where a listed file transfer came from: an offer that arrived unasked, or
/// one that answered an XDCC request of this user's.
nonisolated enum FileTransferOrigin: Equatable, Sendable {
	case offer
	case xdcc(requestID: UUID, pack: Int?)
}

/// The offer a request is matched against.
nonisolated struct XDCCOffer: Sendable {
	let nickname: String
	/// The sender's `nick!user@host`, when the server said.
	let hostmask: String?
	/// Already sanitised, as the offer parser leaves it.
	let filename: String
	let filesize: UInt64
	let startupIdentifier: UUID
}

/** The XDCC requests a session sent and has not seen answered.

 A request is what lets the bot's offer be told apart from any other: it is
 matched by nickname, by the bot's host when that was known, by the time
 since the request or the bot's last word about it, and by file name and size
 whenever the request knows them. The first matching request is consumed, so
 one request answers one offer.

 A match labels the offer; it never lists an offer the user's settings would
 refuse, and never lifts a check every offer goes through. */
nonisolated struct XDCCRequestLedger: Sendable {
	/// How long a request waits for its offer without word from the bot.
	static let lifetime: TimeInterval = 30 * 60
	/// The most requests one session keeps waiting.
	static let capacity = 50
	/// The most packs one `/xdcc batch` asks for.
	static let batchLimit = 20

	private(set) var requests: [XDCCRequest] = []

	var isEmpty: Bool {
		requests.isEmpty
	}

	/// Records a request, or refuses it when the session already waits on as
	/// many as it keeps.
	mutating func record(_ request: XDCCRequest) -> Bool {
		guard requests.count < Self.capacity else { return false }
		var request = request
		request.notePinnedAtRequest()
		requests.append(request)
		return true
	}

	/// Takes the first request the offer answers out of the ledger.
	mutating func match(_ offer: XDCCOffer, now: Date, casefold: (String) -> String) -> XDCCRequest? {
		let bot = casefold(offer.nickname)
		guard let index = requests.firstIndex(where: {
			Self.request($0, answers: offer, bot: bot, now: now, casefold: casefold)
		}) else { return nil }
		return requests.remove(at: index)
	}

	/** Applies what a bot said about a request to the request it is about.

	 Returns the request it touched and whether it is still waiting: an
	 invalid pack ends it, anything else refreshes it. A notice that names no
	 pack applies to the bot's oldest waiting request. */
	mutating func note(
		_ message: XDCCBotMessage,
		from bot: String,
		hostmask: String? = nil,
		now: Date,
		casefold: (String) -> String
	) -> (request: XDCCRequest, isWaiting: Bool)? {
		let key = casefold(bot)
		let pack: Int? = switch message {
		case let .sending(pack, _, _), let .queued(pack, _, _): pack
		case .alreadyRequested, .invalidPack, .denied: nil
		}
		let userHost = Self.userHost(of: hostmask)
		guard let index = requests.firstIndex(where: {
			casefold($0.bot) == key && (pack == nil || $0.pack == pack)
				&& ($0.botUserHost == nil || $0.botUserHost == userHost)
		}) else { return nil }

		var request = requests[index]
		request.refreshedAt = now
		/* A request sent before the bot's host was known is pinned to the host
		 the bot answers from, so its offer has to come from there too. */
		request.botUserHost = request.botUserHost ?? userHost
		switch message {
		case let .sending(_, filename, sizeText):
			request.status = .sending
			request.filename = filename.safeFilename
			request.size = sizeText.flatMap(Self.exactByteCount)
		case let .queued(_, filename, position):
			request.status = .queued(position: position)
			if let filename {
				request.filename = filename.safeFilename
			}
		case .alreadyRequested:
			break
		case .invalidPack, .denied:
			requests.remove(at: index)
			return (request, false)
		}
		requests[index] = request
		return (request, true)
	}

	/// Follows a bot that changed nickname.
	mutating func nicknameChanged(from old: String, to new: String, casefold: (String) -> String) {
		let key = casefold(old)
		for index in requests.indices where casefold(requests[index].bot) == key {
			requests[index].bot = new
		}
	}

	/// Drops every request to a bot that quit; whoever takes the nickname next
	/// is not the bot.
	mutating func remove(bot: String, pack: Int? = nil, casefold: (String) -> String) -> [XDCCRequest] {
		let key = casefold(bot)
		let removed = requests.filter { casefold($0.bot) == key && (pack == nil || $0.pack == pack) }
		requests.removeAll { casefold($0.bot) == key && (pack == nil || $0.pack == pack) }
		return removed
	}

	mutating func remove(id: XDCCRequest.ID) -> XDCCRequest? {
		guard let index = requests.firstIndex(where: { $0.id == id }) else { return nil }
		return requests.remove(at: index)
	}

	/// Drops requests that waited past their lifetime.
	mutating func expire(now: Date) -> [XDCCRequest] {
		let expired = requests.filter { Self.hasExpired($0, now: now) }
		requests.removeAll { Self.hasExpired($0, now: now) }
		return expired
	}

	mutating func removeAll() {
		requests.removeAll()
	}

	/// When the next request runs out, if any is waiting.
	var nextExpiry: Date? {
		requests.map { $0.refreshedAt.addingTimeInterval(Self.lifetime) }.min()
	}

	// MARK: - Matching

	private static func request(
		_ request: XDCCRequest,
		answers offer: XDCCOffer,
		bot: String,
		now: Date,
		casefold: (String) -> String
	) -> Bool {
		guard casefold(request.bot) == bot,
		      request.startupIdentifier == offer.startupIdentifier,
		      hasExpired(request, now: now) == false
		else { return false }
		if let expected = request.botUserHost, userHost(of: offer.hostmask) != expected {
			return false
		}
		switch request.kind {
		case .list:
			return offer.filename.lowercased().hasSuffix(".txt")
		case .pack:
			if let filename = request.filename, filename != offer.filename {
				return false
			}
			if let size = request.size, size != offer.filesize {
				return false
			}
			return true
		}
	}

	private static func hasExpired(_ request: XDCCRequest, now: Date) -> Bool {
		now.timeIntervalSince(request.refreshedAt) > lifetime
	}

	/// The `user@host` of a `nick!user@host`, which is the part a bot does not
	/// give up when it leaves.
	static func userHost(of hostmask: String?) -> String? {
		guard let hostmask, hostmask.contains("@") else { return nil }
		guard let bang = hostmask.firstIndex(of: "!") else { return hostmask }
		return String(hostmask[hostmask.index(after: bang)...])
	}

	/// A size a bot wrote as a plain number of bytes. `1.2G` and friends are
	/// rounded, so they are never compared.
	private static func exactByteCount(_ text: String) -> UInt64? {
		let digits = text.trimmingCharacters(in: .whitespaces)
		guard digits.isEmpty == false, digits.allSatisfy(\.isASCIIDigit) else { return nil }
		return UInt64(digits)
	}
}
