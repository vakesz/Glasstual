// Copyright (c) 2026 Codeux Software, LLC & respective contributors.
// SPDX-License-Identifier: BSD-3-Clause

import Foundation

/** `/xdcc`: requesting packs from XDCC bots by typing.

 Each subcommand builds the bot's line itself from validated pieces, so
 nothing typed after the pack number reaches the bot. */
extension ServerSession {
	func handleXDCCCommand(
		_ input: CommandArguments,
		command: String,
		targetConversation: Conversation?
	) {
		var input = input
		let subcommand = input.next().lowercased()
		let bot = input.next()
		let rest = input.rest.trimmingCharacters(in: .whitespaces)

		switch subcommand {
		case "send", "get":
			guard isBot(bot), let pack = Self.packNumber(rest) else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			askXDCCBot(bot, for: .pack(pack, filename: nil))
		case "batch":
			guard isBot(bot), rest.isEmpty == false else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			requestXDCCBatch(from: bot, packs: rest)
		case "list":
			guard isBot(bot), rest.isEmpty else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			askXDCCBot(bot, for: .list)
		case "info":
			guard isBot(bot), let pack = Self.packNumber(rest) else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			askXDCCBot(bot, for: .info(pack))
		case "cancel":
			let target = bot.isEmpty ? targetConversation.flatMap { $0.isDirect ? $0.name : nil } ?? "" : bot
			guard isBot(target), rest.isEmpty else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			cancelXDCC(from: target)
		case "remove":
			let pack = rest.isEmpty ? nil : Self.packNumber(rest)
			guard isBot(bot), rest.isEmpty || pack != nil else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			leaveXDCCQueue(of: bot, pack: pack)
		case "requests":
			guard bot.isEmpty else {
				printInvalidSyntaxMessage(for: command)
				return
			}
			printXDCCRequests()
		default:
			printInvalidSyntaxMessage(for: command)
		}
	}

	/// Asks for each pack a list such as `1-5,7` names, in order, one line
	/// each. The list is refused whole when it is malformed or too long.
	func requestXDCCBatch(from bot: String, packs text: String) {
		switch XDCCPackRange.expand(text, limit: XDCCRequestLedger.batchLimit) {
		case let .success(packs):
			for pack in packs {
				guard askXDCCBot(bot, for: .pack(pack, filename: nil)) else { break }
			}
		case .failure(.tooMany):
			printDebugInformation(String(localized: .IRC.xdccBatchTooLarge(String(XDCCRequestLedger.batchLimit))))
		case .failure:
			printDebugInformation(String(localized: .IRC.xdccInvalidPackList(text)))
		}
	}

	/// Tells the bot to stop sending, stops the transfers its requests turned
	/// into, and forgets its requests.
	func cancelXDCC(from bot: String) {
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}
		sendXDCCLine("XDCC CANCEL", to: bot)
		_ = xdccRequests.remove(bot: bot, casefold: supportInfo.casefoldString)
		fileTransfers?.stopRequestedTransfers(from: bot, on: self)
		printDebugInformation(String(localized: .IRC.xdccCancelled(bot)))
	}

	/// Leaves a bot's queue, for one pack or all of them, and forgets the
	/// matching requests.
	func leaveXDCCQueue(of bot: String, pack: Int?) {
		guard isLoggedIn else {
			printDebugInformation(toConsole: String(localized: .IRC.failedToSendDataToServer))
			return
		}
		sendXDCCLine(pack.map { "XDCC REMOVE #\($0)" } ?? "XDCC REMOVE", to: bot)
		_ = xdccRequests.remove(bot: bot, pack: pack, casefold: supportInfo.casefoldString)
		printDebugInformation(pack.map {
			String(localized: .IRC.xdccRemovedPack(Self.xdccLabel(pack: $0, filename: nil), bot))
		} ?? String(localized: .IRC.xdccRemovedQueue(bot)))
	}

	private func printXDCCRequests() {
		expireXDCCRequests()
		guard xdccRequests.isEmpty == false else {
			printDebugInformation(String(localized: .IRC.xdccNoRequests))
			return
		}
		for request in xdccRequests.requests {
			let status = switch request.status {
			case .sent: String(localized: .IRC.xdccStatusSent)
			case let .queued(position?): String(localized: .IRC.xdccStatusQueuedAtPosition(String(position)))
			case .queued(nil): String(localized: .IRC.xdccStatusQueued)
			case .sending: String(localized: .IRC.xdccStatusSending)
			}
			printDebugInformation(String(localized: .IRC.xdccRequestRow(Self.xdccLabel(for: request), request.bot, status)))
		}
	}

	private func isBot(_ name: String) -> Bool {
		name.isEmpty == false && stringIsNickname(name) && XDCCAnnouncementParser.isPlausibleBotName(name)
	}

	/// `#12` or `12`, within the range a pack number can take.
	static func packNumber(_ text: String) -> Int? {
		let digits = text.hasPrefix("#") ? text.dropFirst() : Substring(text)
		guard digits.isEmpty == false, digits.allSatisfy(\.isASCIIDigit), let pack = Int(digits),
		      XDCCAnnouncementParser.packRange.contains(pack)
		else { return nil }
		return pack
	}
}
