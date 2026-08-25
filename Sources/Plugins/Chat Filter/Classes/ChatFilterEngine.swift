/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

import AppKit

@objc(TPI_ChatFilterLogic)
final class ChatFilterEngine: NSObject, @unchecked Sendable {
	private weak var parentObject: NSObject?
	private var lastActionDates: [String: TimeInterval] = [:]

	@objc(initWithParentObject:)
	init(parentObject: NSObject) {
		self.parentObject = parentObject
		super.init()
	}

	private var filters: [ChatFilter] {
		guard let controller = parentObject?.value(forKey: "filterArrayController") as? NSArrayController else {
			return []
		}
		return controller.arrangedObjects as? [ChatFilter] ?? []
	}

	private func matchesDestination(
		_ filter: ChatFilter,
		author: IRCPrefix,
		destination: IRCChannel?,
		client: IRCClient
	) -> Bool {
		let limit = ChatFilterDestination(rawValue: filter.filterLimitedToValue) ?? .unrestricted
		if limit != .unrestricted || filter.filterIgnoreOperators, destination == nil, !author.isServer {
			return false
		}

		switch limit {
		case .channels:
			return destination?.isChannel == true
		case .privateMessages:
			return destination?.isPrivateMessage == true
		case .specificItems:
			let channelMatches: Bool = if let identifier = destination?.uniqueIdentifier {
				filter.filterLimitedToChannelsIDs.contains(identifier)
			} else {
				false
			}
			return filter.filterLimitedToClientsIDs.contains(client.uniqueIdentifier) || channelMatches
		case .unrestricted:
			return true
		}
	}

	private func matchesSender(
		_ filter: ChatFilter,
		author: IRCPrefix,
		destination: IRCChannel?,
		client: IRCClient
	) -> Bool {
		if filter.filterLimitedToMyself {
			return client.userNickname.caseInsensitiveCompare(author.nickname) == .orderedSame
		}

		if !filter.filterSenderMatch.isEmpty {
			let identity = author.isServer ? author.nickname : author.hostmask
			guard XRRegularExpression.string(identity, isMatchedByRegex: filter.filterSenderMatch, withoutCase: true)
			else {
				return false
			}
		}

		guard destination?.isChannel == true, !author.isServer else { return true }
		let sender = destination?.findMember(author.nickname)

		if filter.filterAgeLimit > 0 {
			guard let sender else { return false }
			let elapsed = Date.timeIntervalSinceReferenceDate - sender.creationTime
			switch ChatFilterAgeComparator(rawValue: filter.filterAgeComparator) ?? .none {
			case .lessThan where elapsed < Double(filter.filterAgeLimit): return false
			case .greaterThan where elapsed >= Double(filter.filterAgeLimit): return false
			default: break
			}
		}

		if filter.filterIgnoreOperators {
			guard let sender else { return false }
			return !sender.isHalfOp
		}
		return true
	}

	private func matchesText(_ filter: ChatFilter, text: String?, allowingNil: Bool) -> Bool {
		guard var text else { return allowingNil }
		guard !filter.filterMatch.isEmpty else { return true }
		if !TPCPreferences.removeAllFormatting() {
			text = text.stripIRCEffects
		}
		return XRRegularExpression.string(text, isMatchedByRegex: filter.filterMatch, withoutCase: true)
	}

	@objc(receivedCommand:withText:authoredBy:destinedFor:onClient:receivedAt:referenceMessage:)
	func receivedCommand(
		_ command: String,
		text: String?,
		author: IRCPrefix,
		destination: IRCChannel?,
		client: IRCClient,
		receivedAt: Date,
		referenceMessage: IRCMessage?
	) -> Bool {
		for filter in filters where filter.isCommandEnabled(command) {
			guard matchesDestination(filter, author: author, destination: destination, client: client),
			      matchesSender(filter, author: author, destination: destination, client: client),
			      matchesText(filter, text: text, allowingNil: true)
			else { continue }

			performAction(filter, text: text, author: author, destination: destination, client: client,
			              referenceMessage: referenceMessage)
			forwardCommand(command, text: text, using: filter, client: client, receivedAt: receivedAt)
			return !filter.filterIgnoreContent
		}
		return true
	}

	@objc(receivedText:authoredBy:destinedFor:asLineType:onClient:receivedAt:wasEncrypted:)
	func receivedText(
		_ text: String,
		author: IRCPrefix,
		destination: IRCChannel?,
		lineType: TVCLogLineType,
		client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) -> Bool {
		for filter in filters where accepts(lineType, filter: filter) {
			guard matchesDestination(filter, author: author, destination: destination, client: client),
			      matchesSender(filter, author: author, destination: destination, client: client),
			      matchesText(filter, text: text, allowingNil: false)
			else { continue }

			performAction(filter, text: text, author: author, destination: destination, client: client,
			              referenceMessage: nil)
			forwardText(text, author: author, lineType: lineType, using: filter, client: client,
			            receivedAt: receivedAt, wasEncrypted: wasEncrypted)
			return !filter.filterIgnoreContent
		}
		return true
	}

	private func accepts(_ lineType: TVCLogLineType, filter: ChatFilter) -> Bool {
		switch lineType {
		case .privateMessage, .privateMessageNoHighlight:
			filter.isEventTypeEnabled(.plainTextMessage)
		case .action, .actionNoHighlight:
			filter.isEventTypeEnabled(.actionMessage)
		case .notice:
			filter.isEventTypeEnabled(.noticeMessage)
		default:
			true
		}
	}

	private func forwardCommand(
		_ command: String,
		text: String?,
		using filter: ChatFilter,
		client: IRCClient,
		receivedAt: Date
	) {
		guard !filter.filterForwardToDestination.isEmpty, let text, !text.isEmpty else { return }
		guard let destination = client.findChannelOrCreate(filter.filterForwardToDestination, isPrivateMessage: true)
		else {
			return
		}
		let message = localized("dct-7h", table: "TPI_ChatFilterLogic", arguments: command, text)
		let clientReference = SendableReference(client)
		let destinationReference = SendableReference(destination)
		client.print(message, by: nil, in: destination, as: .debug, command: TVCLogLineDefaultCommandValue,
		             receivedAt: receivedAt, isEncrypted: false, referenceMessage: nil)
		{ _ in
			self.setUnreadState(clientReference.value, channel: destinationReference.value)
		}
	}

	private func forwardText(
		_ text: String,
		author: IRCPrefix,
		lineType: TVCLogLineType,
		using filter: ChatFilter,
		client: IRCClient,
		receivedAt: Date,
		wasEncrypted: Bool
	) {
		guard !filter.filterForwardToDestination.isEmpty else { return }
		guard let destination = client.findChannelOrCreate(filter.filterForwardToDestination, isPrivateMessage: true)
		else {
			return
		}
		let command = lineType == .notice ? "NOTICE" : "PRIVMSG"
		let clientReference = SendableReference(client)
		let destinationReference = SendableReference(destination)
		client.print(text, by: author.nickname, in: destination, as: lineType, command: command,
		             receivedAt: receivedAt, isEncrypted: wasEncrypted, referenceMessage: nil)
		{ context in
			if lineType == .notice {
				self.setUnreadState(clientReference.value, channel: destinationReference.value)
			} else {
				if context.isHighlight {
					self.setHighlightState(clientReference.value, channel: destinationReference.value)
				}
				self.setUnreadState(
					clientReference.value,
					channel: destinationReference.value,
					isHighlight: context.isHighlight
				)
			}
		}
	}

	private func performAction(
		_ filter: ChatFilter,
		text: String?,
		author: IRCPrefix,
		destination: IRCChannel?,
		client: IRCClient,
		referenceMessage: IRCMessage?
	) {
		guard isSafeToPerformAction(filter), !filter.filterAction.isEmpty else { return }
		var action = filter.filterAction
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
		let parameters = referenceMessage?.params ?? []
		for index in 0 ... 9 {
			let value = parameters.indices.contains(index) ? parameters[index] : ""
			action = action.replacingOccurrences(of: "%_Parameter_\(index)_%", with: value)
		}

		for line in action.components(separatedBy: .newlines)
			where line.count > 1 && line.hasPrefix("/") && !line.hasPrefix("//")
		{
			client.sendCommand(String(line.dropFirst()))
		}

		guard filter.filterLogMatch else { return }
		guard let report = client.findChannelOrCreate("Filter Actions", isUtility: true) else { return }
		let message: String = if let destination {
			localized("jcm-xj", table: "TPI_ChatFilterExtension",
			          arguments: filter.filterTitle, author.nickname, destination.name)
		} else {
			localized("yla-he", table: "TPI_ChatFilterExtension",
			          arguments: filter.filterTitle, author.nickname)
		}
		client.print(message, by: nil, in: report, as: .privateMessage, command: "PRIVMSG")
		setUnreadState(client, channel: report)
	}

	private func isSafeToPerformAction(_ filter: ChatFilter) -> Bool {
		let interval = TimeInterval(filter.filterActionFloodControlInterval)
		guard interval > 0 else { return true }
		let now = Date.timeIntervalSinceReferenceDate
		if let lastAction = lastActionDates[filter.uniqueIdentifier], now - lastAction <= interval {
			return false
		}
		lastActionDates[filter.uniqueIdentifier] = now
		return true
	}

	@objc func reloadFilterActionPerforms() {
		let validIdentifiers = Set(filters.lazy.filter { $0.filterActionFloodControlInterval > 0 }
			.map(\.uniqueIdentifier))
		lastActionDates = lastActionDates.filter { validIdentifiers.contains($0.key) }
	}

	private func localized(_ key: String, table: String, arguments: CVarArg...) -> String {
		let format = Bundle(for: Self.self).localizedString(forKey: key, value: key, table: table)
		return String(format: format, arguments: arguments)
	}

	private nonisolated func setUnreadState(_ client: IRCClient, channel: IRCChannel) {
		client.perform(NSSelectorFromString("setUnreadStateForChannel:"), with: channel)
	}

	private nonisolated func setUnreadState(_ client: IRCClient, channel: IRCChannel, isHighlight: Bool) {
		let selector = NSSelectorFromString("setUnreadStateForChannel:isHighlight:")
		typealias Function = @convention(c) (AnyObject, Selector, IRCChannel, Bool) -> Void
		let implementation = client.method(for: selector)
		unsafeBitCast(implementation, to: Function.self)(client, selector, channel, isHighlight)
	}

	private nonisolated func setHighlightState(_ client: IRCClient, channel: IRCChannel) {
		client.perform(NSSelectorFromString("setHighlightStateForChannel:"), with: channel)
	}
}

private final class SendableReference<Value: AnyObject>: @unchecked Sendable {
	let value: Value
	init(_ value: Value) {
		self.value = value
	}
}
