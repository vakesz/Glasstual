/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\__|\__,_|\__,_|_|
 *
 * Copyright (c) 2013 - 2018 Codeux Software, LLC & respective contributors.
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

import Foundation
import GlasstualPluginKit

@objc(TPIUserInsights)
final class UserInsightsPlugin: NSObject, GlasstualPlugin, PluginCommandHandling {
	var subscribedUserInputCommands: [String] {
		["clones", "namel", "finduser", "brag"]
	}

	func userInputCommandInvoked(_ invocation: PluginCommandInvocation) {
		handleCommand(invocation)
	}

	private func handleCommand(_ invocation: PluginCommandInvocation) {
		guard let channel = invocation.selectedChannel else { return }
		let command = invocation.command
		let client = invocation.client

		if command == "BRAG" {
			brag(in: channel, client: client, connectedClients: invocation.connectedClients)
			return
		}
		guard channel.isChannel else { return }

		switch command {
		case "CLONES":
			findClones(in: channel, client: client)
		case "NAMEL":
			listUsers(
				in: channel,
				client: client,
				parameters: invocation.message.trimmingCharacters(in: .whitespacesAndNewlines)
			)
		case "FINDUSER":
			findUsers(
				matching: invocation.message.trimmingCharacters(in: .whitespacesAndNewlines),
				in: channel,
				client: client
			)
		default:
			break
		}
	}

	private func listUsers(in channel: PluginChannel, client: PluginClient, parameters: String) {
		var members = channel.members
		guard members.isEmpty == false else {
			client.printDebug(localized(.BasicLanguage.noUsersInChannel(channel.name)), in: channel)
			return
		}

		let flags = parameters.hasPrefix("-") ? parameters.dropFirst() : ""
		let displayRank = flags.contains("d")
		if flags.contains("r") == false {
			members.sort { $0.user.nickname.localizedCaseInsensitiveCompare($1.user.nickname) == .orderedAscending }
		}

		let result = members.map { member in
			(displayRank ? member.mark : "") + member.user.nickname
		}.joined(separator: " ") + " "
		client.printDebug(result, in: channel)
	}

	private func findUsers(matching query: String, in channel: PluginChannel, client: PluginClient) {
		let hasQuery = query.isEmpty == false
		let matches = channel.members.filter { member in
			guard let hostmask = member.user.hostmask else { return false }
			return hasQuery == false || hostmask.localizedCaseInsensitiveContains(query)
		}.sorted { $0.user.nickname.localizedCaseInsensitiveCompare($1.user.nickname) == .orderedAscending }

		guard matches.isEmpty == false else {
			let message = hasQuery
				? localized(.BasicLanguage.noHostmaskQueryMatches(channel.name, query))
				: localized(.BasicLanguage.noHostmaskMatches(channel.name))
			client.printDebug(message, in: channel)
			return
		}

		let summary = hasQuery
			? localized(.BasicLanguage.hostmaskQueryMatchCount(UInt(matches.count), channel.name, query))
			: localized(.BasicLanguage.hostmaskMatchCount(UInt(matches.count), channel.name))
		client.printDebug(summary, in: channel)

		for member in matches {
			client.printDebug("\(member.user.nickname) -> \(member.user.hostmask ?? "")", in: channel)
		}
	}

	private func findClones(in channel: PluginChannel, client: PluginClient) {
		let grouped = Dictionary(grouping: channel.members.compactMap { member -> (String, String)? in
			guard let address = member.user.address else { return nil }
			return (address, member.user.nickname)
		}, by: \.0)
		let clones = grouped.compactMapValues { entries -> [String]? in
			guard entries.count > 1 else { return nil }
			return entries.map(\.1)
		}

		guard clones.isEmpty == false else {
			client.printDebug(localized(.BasicLanguage.noClones), in: channel)
			return
		}

		client.printDebug(localized(.BasicLanguage.cloneCount(UInt(clones.count), channel.name)), in: channel)
		for (address, nicknames) in clones.sorted(by: { $0.key < $1.key }) {
			client.printDebug("*!*@\(address) -> \(nicknames.joined(separator: ", "))", in: channel)
		}
	}

	private func brag(in channel: PluginChannel, client: PluginClient, connectedClients: [PluginClient]) {
		var counts = BragCounts()

		for currentClient in connectedClients where currentClient.isConnected {
			counts.networks += 1
			if currentClient.isIRCop || currentClient.localUser?.isIRCop == true {
				counts.operators += 1
			}

			var trackedUsers = Set<String>()
			for currentChannel in currentClient.channels where currentChannel.isActive && currentChannel.isChannel {
				counts.channels += 1
				guard let localMember = currentChannel.member(named: currentClient.userNickname) else { continue }
				let localRanks = localMember.ranks

				if localRanks.contains(.channelOwner) || localRanks.contains(.superOperator) || localRanks
					.contains(.normalOperator)
				{
					counts.channelOperators += 1
				} else if localRanks.contains(.halfOperator) {
					counts.channelHalfOperators += 1
				} else if localRanks.contains(.voiced) {
					counts.channelVoices += 1
				}

				for member in currentChannel.members where member != localMember {
					if hasPower(over: member, localRanks: localRanks, localClientIsOperator: currentClient.isIRCop),
					   trackedUsers.insert(member.user.nickname).inserted
					{
						counts.powerOverUsers += 1
					}
				}
			}
		}

		var result = pluralized(.channels, value: counts.channels)
		result += pluralized(.networks, value: counts.networks)
		if counts.powerOverUsers == 0 {
			result += localized(.BasicLanguage.bragNoPower)
		} else {
			result += pluralized(.operators, value: counts.operators)
			result += pluralized(.channelOperators, value: counts.channelOperators)
			result += pluralized(.channelHalfOperators, value: counts.channelHalfOperators)
			result += pluralized(.channelVoices, value: counts.channelVoices)
			result += pluralized(.poweredUsers, value: counts.powerOverUsers)
		}
		client.sendPrivateMessage(result, to: channel)
	}

	private func hasPower(
		over member: PluginChannelMember,
		localRanks: UserRank,
		localClientIsOperator: Bool
	) -> Bool {
		let ranks = member.ranks
		if localClientIsOperator, member.user.isIRCop == false {
			return true
		}
		if localRanks.contains(.channelOwner), ranks.contains(.channelOwner) == false {
			return true
		}
		if localRanks.contains(.superOperator),
		   ranks.isDisjoint(with: [.channelOwner, .superOperator])
		{
			return true
		}
		if localRanks.contains(.normalOperator),
		   ranks.isDisjoint(with: [.channelOwner, .superOperator, .normalOperator])
		{
			return true
		}
		if localRanks.contains(.halfOperator), ranks.isDisjoint(with: [
			.channelOwner,
			.superOperator,
			.normalOperator,
			.halfOperator,
		]) {
			return true
		}
		return false
	}

	private func pluralized(_ metric: BragMetric, value: Int) -> String {
		localized(metric.resource(value: value))
	}

	private func localized(_ resource: LocalizedStringResource) -> String {
		String(localized: resource)
	}
}

private nonisolated enum BragMetric { // nonisolated: value
	case channelHalfOperators
	case channelOperators
	case channelVoices
	case channels
	case networks
	case operators
	case poweredUsers

	func resource(value: Int) -> LocalizedStringResource {
		switch self {
		case .channelHalfOperators:
			.BasicLanguage.bragChannelHalfOperatorCount(value)
		case .channelOperators:
			.BasicLanguage.bragChannelOperatorCount(value)
		case .channelVoices:
			.BasicLanguage.bragChannelVoiceCount(value)
		case .channels:
			.BasicLanguage.bragChannelCount(value)
		case .networks:
			.BasicLanguage.bragNetworkCount(value)
		case .operators:
			.BasicLanguage.bragOperatorCount(value)
		case .poweredUsers:
			.BasicLanguage.bragPoweredUserCount(value)
		}
	}
}

private struct BragCounts {
	var operators = 0
	var channelOperators = 0
	var channelHalfOperators = 0
	var channelVoices = 0
	var channels = 0
	var networks = 0
	var powerOverUsers = 0
}
