/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2015 - 2018 Codeux Software, LLC & respective contributors.
 *       Please see Acknowledgements.pdf for additional information.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 *  * Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 *  * Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *  * Neither the name of Textual, "Codeux Software, LLC", nor the
 *    names of its contributors may be used to endorse or promote products
 *    derived from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 *
 *********************************************************************** */

import CocoaExtensions
import Foundation
import GlasstualPluginKit

final class ChatFilterEngine {
	private let filtersProvider: () -> [ChatFilter]
	private let host: PluginHostContext
	private var lastActionDates: [String: TimeInterval] = [:]

	init(host: PluginHostContext, filters: @escaping () -> [ChatFilter]) {
		self.host = host
		filtersProvider = filters
	}

	private var filters: [ChatFilter] {
		filtersProvider()
	}

	private func matchesDestination(
		_ filter: ChatFilter,
		author: PluginSender,
		destination: PluginChannel?,
		client: PluginClient
	) -> Bool {
		let limit = filter.destination
		if limit != .unrestricted || filter.ignoresOperators, destination == nil, !author.isServer {
			return false
		}

		switch limit {
		case .channels:
			return destination?.isChannel == true
		case .privateMessages:
			return destination?.isPrivateMessage == true
		case .specificItems:
			let channelMatches: Bool = if let identifier = destination?.identifier {
				filter.limitedChannelIDs.contains(identifier)
			} else {
				false
			}
			return filter.limitedClientIDs.contains(client.identifier) || channelMatches
		case .unrestricted:
			return true
		}
	}

	private func matchesSender(
		_ filter: ChatFilter,
		author: PluginSender,
		destination: PluginChannel?,
		client: PluginClient
	) -> Bool {
		if filter.isLimitedToMyself {
			return client.userNickname.caseInsensitiveCompare(author.nickname) == .orderedSame
		}

		if !filter.senderMatch.isEmpty {
			let identity = author.isServer ? author.nickname : author.hostmask
			guard RegularExpression.string(identity, isMatchedByRegex: filter.senderMatch, withoutCase: true)
			else {
				return false
			}
		}

		guard destination?.isChannel == true, !author.isServer else { return true }
		let sender = destination?.member(named: author.nickname)

		if filter.ageLimit > 0 {
			guard let sender else { return false }

			/* The editor asks for the membership age the filter applies to, so a
			 sender outside that comparison is the one that does not match. */
			let age = sender.membershipAge
			let limit = Double(filter.ageLimit)

			switch filter.ageComparator {
			case .lessThan where age >= limit: return false
			case .greaterThan where age <= limit: return false
			default: break
			}
		}

		if filter.ignoresOperators {
			guard let sender else { return false }
			return !sender.isHalfOperator
		}
		return true
	}

	private func matchesText(_ filter: ChatFilter, text: String?, allowingNil: Bool) -> Bool {
		guard var text else { return allowingNil }
		guard !filter.match.isEmpty else { return true }
		if host.removesIRCFormatting == false {
			text = IRCFormatting.removingControlCodes(from: text)
		}
		return RegularExpression.string(text, isMatchedByRegex: filter.match, withoutCase: true)
	}

	func receivedCommand(_ event: PluginIncomingCommandEvent) -> Bool {
		for filter in filters where filter.isCommandEnabled(event.command) {
			guard matchesDestination(
				filter,
				author: event.author,
				destination: event.destination,
				client: event.client
			),
				matchesSender(filter, author: event.author, destination: event.destination, client: event.client),
				matchesText(filter, text: event.text, allowingNil: true)
			else { continue }

			performAction(
				filter,
				text: event.text,
				author: event.author,
				destination: event.destination,
				client: event.client,
				messageParameters: event.messageParameters
			)
			forwardCommand(
				event.command,
				text: event.text,
				using: filter,
				client: event.client,
				receivedAt: event.receivedAt
			)
			return !filter.ignoresContent
		}
		return true
	}

	func receivedText(_ event: PluginTextEvent) -> Bool {
		for filter in filters where accepts(event.kind, filter: filter) {
			guard matchesDestination(
				filter,
				author: event.author,
				destination: event.destination,
				client: event.client
			),
				matchesSender(filter, author: event.author, destination: event.destination, client: event.client),
				matchesText(filter, text: event.text, allowingNil: false)
			else { continue }

			performAction(
				filter,
				text: event.text,
				author: event.author,
				destination: event.destination,
				client: event.client,
				messageParameters: []
			)
			forwardText(
				event.text,
				author: event.author,
				kind: event.kind,
				using: filter,
				client: event.client,
				receivedAt: event.receivedAt,
				wasEncrypted: event.wasEncrypted
			)
			return !filter.ignoresContent
		}
		return true
	}

	private func accepts(_ kind: PluginMessageKind, filter: ChatFilter) -> Bool {
		switch kind {
		case .privateMessage, .privateMessageNoHighlight:
			filter.isEventEnabled(.plainTextMessage)
		case .action, .actionNoHighlight:
			filter.isEventEnabled(.actionMessage)
		case .notice:
			filter.isEventEnabled(.noticeMessage)
		default:
			true
		}
	}

	private func forwardCommand(
		_ command: String,
		text: String?,
		using filter: ChatFilter,
		client: PluginClient,
		receivedAt: Date
	) {
		guard !filter.forwardDestination.isEmpty, let text, !text.isEmpty else { return }
		guard let destination = client.privateMessage(named: filter.forwardDestination)
		else {
			return
		}
		let message = String(localized: .TPIChatFilterLogic.forwardedMessage(command, text))
		client.print(message, authoredBy: nil, in: destination, as: .debug, command: "", receivedAt: receivedAt) { _ in
			client.markUnread(destination)
		}
	}

	private func forwardText(
		_ text: String,
		author: PluginSender,
		kind: PluginMessageKind,
		using filter: ChatFilter,
		client: PluginClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) {
		guard !filter.forwardDestination.isEmpty else { return }
		guard let destination = client.privateMessage(named: filter.forwardDestination)
		else {
			return
		}
		let command = kind == .notice ? "NOTICE" : "PRIVMSG"
		client.print(
			text,
			authoredBy: author.nickname,
			in: destination,
			as: kind,
			command: command,
			receivedAt: receivedAt,
			isEncrypted: wasEncrypted
		) { context in
			if kind == .notice {
				client.markUnread(destination)
			} else {
				if context.isHighlight {
					client.markHighlight(destination)
				}
				client.markUnread(destination, isHighlight: context.isHighlight)
			}
		}
	}

	private func performAction(
		_ filter: ChatFilter,
		text: String?,
		author: PluginSender,
		destination: PluginChannel?,
		client: PluginClient,
		messageParameters: [String]
	) {
		guard isSafeToPerformAction(filter), !filter.action.isEmpty else { return }
		var action = filter.action
		let replacements: [String: String?] = [
			"%_channelName_%": destination?.name,
			"%_localNickname_%": client.userNickname,
			"%_networkName_%": client.networkName,
			"%_originalMessage_%": text,
			"%_senderNickname_%": author.nickname,
			"%_senderUsername_%": author.username,
			"%_senderAddress_%": author.address,
			"%_senderHostmask_%": author.hostmask,
			"%_serverAddress_%": client.serverAddress,
		]
		for (token, value) in replacements {
			action = action.replacingOccurrences(of: token, with: value ?? "")
		}
		for index in 0 ... 9 {
			let value = messageParameters.indices.contains(index) ? messageParameters[index] : ""
			action = action.replacingOccurrences(of: "%_Parameter_\(index)_%", with: value)
		}

		for line in action.components(separatedBy: .newlines)
			where line.count > 1 && line.hasPrefix("/") && !line.hasPrefix("//")
		{
			client.sendCommand(String(line.dropFirst()))
		}

		guard filter.logsMatch else { return }
		guard let report = client.utilityChannel(named: "Filter Actions") else {
			return
		}
		let message = if let destination {
			String(
				localized: .TPIChatFilterExtension.actionLogUserInChannel(
					filter.title,
					author.nickname,
					destination.name
				)
			)
		} else {
			String(
				localized: .TPIChatFilterExtension.actionLogUser(
					filter.title,
					author.nickname
				)
			)
		}
		client.print(message, authoredBy: nil, in: report, as: .privateMessage, command: "PRIVMSG")
		client.markUnread(report)
	}

	private func isSafeToPerformAction(_ filter: ChatFilter) -> Bool {
		let interval = TimeInterval(filter.actionFloodControlInterval)
		guard interval > 0 else { return true }
		let now = Date.timeIntervalSinceReferenceDate
		if let lastAction = lastActionDates[filter.id], now - lastAction <= interval {
			return false
		}
		lastActionDates[filter.id] = now
		return true
	}

	func reloadFilterActionPerforms() {
		let validIdentifiers = Set(filters.lazy.filter { $0.actionFloodControlInterval > 0 }.map(\.id))
		lastActionDates = lastActionDates.filter { validIdentifiers.contains($0.key) }
	}
}
