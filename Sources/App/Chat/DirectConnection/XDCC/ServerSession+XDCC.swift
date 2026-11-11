// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import CocoaExtensions
import Foundation

/** Asking XDCC bots for packs and recognising their answers.

 Every request goes to the bot as an ordinary private message, through the
 connection's flood control, and is remembered in ``XDCCRequestLedger`` so the
 bot's offer can be labelled as the one the user asked for. What the bot says
 back refreshes the request; when it quits, its requests go with it. */
extension ServerSession {
	/// What a `/xdcc` request asks a bot for.
	enum XDCCAsk {
		case pack(Int, filename: String?)
		case list
		case info(Int)
	}

	/// Asks `bot` for something, and remembers a pack or list request so its
	/// offer can be matched. `false` when nothing was sent.
	@discardableResult
	func askXDCCBot(_ bot: String, for ask: XDCCAsk) -> Bool {
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return false
		}
		let text: String
		let kind: XDCCRequest.Kind?
		let label: String
		switch ask {
		case let .pack(pack, filename):
			text = "XDCC SEND #\(pack)"
			kind = .pack(pack)
			label = Self.xdccLabel(pack: pack, filename: filename)
		case .list:
			text = "XDCC LIST"
			kind = .list
			label = String(localized: .IRC.xdccListLabel)
		case let .info(pack):
			text = "XDCC INFO #\(pack)"
			kind = nil
			label = Self.xdccLabel(pack: pack, filename: nil)
		}

		if let kind {
			let now = Date.now
			let filename: String? = if case let .pack(_, filename) = ask {
				filename?.safeFilename
			} else {
				nil
			}
			let request = XDCCRequest(
				id: UUID(), bot: bot, botUserHost: XDCCRequestLedger.userHost(of: findUser(bot)?.hostmask),
				kind: kind, filename: filename, size: nil, status: .sent,
				startupIdentifier: startup.identifier, requestedAt: now, refreshedAt: now
			)
			guard xdccRequests.record(request) else {
				printDebugInformation(String(localized: .IRC.xdccTooManyRequests))
				return false
			}
			scheduleXDCCExpiry()
		}

		sendXDCCLine(text, to: bot)
		printDebugInformation(ask.isInfo
			? String(localized: .IRC.xdccAskedForInfo(bot, label))
			: String(localized: .IRC.xdccRequested(label, bot)))
		return true
	}

	/// Sends a line to a bot without printing it, and keeps its echo out.
	func sendXDCCLine(_ text: String, to bot: String) {
		sendUnprinted(.privmsg, to: bot, text: text)
	}

	/// Takes the request an incoming offer answers out of the ledger.
	func matchXDCCRequest(nickname: String, hostmask: String?, filename: String, filesize: UInt64) -> XDCCRequest? {
		guard xdccRequests.isEmpty == false else { return nil }
		let offer = XDCCOffer(
			nickname: nickname, hostmask: hostmask, filename: filename, filesize: filesize,
			startupIdentifier: startup.identifier
		)
		let matched = xdccRequests.match(offer, now: .now, casefold: supportInfo.casefoldString)
		if matched != nil {
			scheduleXDCCExpiry()
		}
		return matched
	}

	/** Reads a bot's private notice or message about a request.

	 Replayed history is never read: a bouncer playing back yesterday's
	 "sending you pack" must not revive a request. */
	func noteXDCCBotText(_ text: String, from message: Message) {
		guard xdccRequests.isEmpty == false, message.isReplayed == false,
		      let bot = message.senderNickname,
		      let parsed = XDCCBotMessage.parse((text as NSString).stripIRCEffects),
		      let (request, isWaiting) = xdccRequests.note(
		      	parsed, from: bot, hostmask: message.senderHostmask, now: .now, casefold: supportInfo.casefoldString
		      )
		else { return }
		let label = Self.xdccLabel(for: request)
		switch parsed {
		case let .queued(_, _, position?):
			printDebugInformation(String(localized: .IRC.xdccQueuedAtPosition(bot, label, String(position))))
		case .queued:
			printDebugInformation(String(localized: .IRC.xdccQueued(bot, label)))
		case .invalidPack:
			printDebugInformation(String(localized: .IRC.xdccInvalidPack(bot, label)))
		case let .denied(reason):
			printDebugInformation(String(localized: .IRC.xdccDenied(bot, label, reason)))
		case .sending, .alreadyRequested:
			break
		}
		if isWaiting == false {
			scheduleXDCCExpiry()
		}
	}

	/// Follows a bot's NICK. Replayed history changes nothing.
	func noteXDCCNicknameChange(from old: String, to new: String, message: Message) {
		guard xdccRequests.isEmpty == false, message.isReplayed == false, message.isPrintOnlyMessage == false else { return }
		xdccRequests.nicknameChanged(from: old, to: new, casefold: supportInfo.casefoldString)
	}

	/// Drops the requests to a bot that quit.
	func noteXDCCQuit(of nickname: String, message: Message) {
		guard xdccRequests.isEmpty == false, message.isReplayed == false, message.isPrintOnlyMessage == false else { return }
		if xdccRequests.remove(bot: nickname, casefold: supportInfo.casefoldString).isEmpty == false {
			scheduleXDCCExpiry()
		}
	}

	/// Forgets every request, for a connection that ended.
	func resetXDCCRequests() {
		scheduled.xdccExpiry?.cancel()
		scheduled.xdccExpiry = nil
		xdccRequests.removeAll()
	}

	/// Drops expired requests, saying so, and waits for the next one to run out.
	func expireXDCCRequests(now: Date = .now) {
		for request in xdccRequests.expire(now: now) {
			printDebugInformation(toConsole: String(localized: .IRC.xdccExpired(Self.xdccLabel(for: request), request.bot)))
		}
		scheduleXDCCExpiry()
	}

	private func scheduleXDCCExpiry() {
		scheduled.xdccExpiry?.cancel()
		guard let deadline = xdccRequests.nextExpiry else {
			scheduled.xdccExpiry = nil
			return
		}
		let delay = max(deadline.timeIntervalSinceNow, 0) + 1
		scheduled.xdccExpiry = Task { [weak self] in
			do { try await Task.sleep(for: .seconds(delay)) } catch { return }
			self?.expireXDCCRequests()
		}
	}

	// MARK: - Labels

	static func xdccLabel(for request: XDCCRequest) -> String {
		switch request.kind {
		case let .pack(pack): xdccLabel(pack: pack, filename: request.filename)
		case .list: String(localized: .IRC.xdccListLabel)
		}
	}

	static func xdccLabel(pack: Int, filename: String?) -> String {
		if let filename, filename.isEmpty == false {
			return String(localized: .IRC.xdccPackLabelWithFilename(String(pack), filename))
		}
		return String(localized: .IRC.xdccPackLabel(String(pack)))
	}
}

private extension ServerSession.XDCCAsk {
	var isInfo: Bool {
		if case .info = self {
			return true
		}
		return false
	}
}
