/* *********************************************************************
 *                  _____         _               _
 *                 |_   _|____  _| |_ _   _  __ _| |
 *                   | |/ _ \ \/ / __| | | |/ _` | |
 *                   | |  __/>  <| |_| |_| | (_| | |
 *                   |_|\___/_/\_\\__|\__,_|\__,_|_|
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

@objc(TPIUserInsights)
final class UserInsightsPlugin: NSObject, THOPluginProtocol, @unchecked Sendable {
	private var bundle: Bundle {
		Bundle(for: UserInsightsPlugin.self)
	}

	var subscribedUserInputCommands: [String] {
		["clones", "namel", "finduser", "brag"]
	}

	func userInputCommandInvoked(on client: IRCClient, command commandString: String, messageString: String) {
		let client = MainActorTransfer(value: client)
		Task { @MainActor [weak self] in
			self?.handleCommand(commandString, message: messageString, client: client.value)
		}
	}

	@MainActor
	private func handleCommand(_ command: String, message: String, client: IRCClient) {
		guard let channel = NSObject.masterController().mainWindow.selectedChannel else { return }

		if command == "BRAG" {
			brag(in: channel, client: client)
			return
		}
		guard channel.isChannel else { return }

		switch command {
		case "CLONES":
			findClones(in: channel, client: client)
		case "NAMEL":
			listUsers(in: channel, client: client, parameters: message.trimmingCharacters(in: .whitespacesAndNewlines))
		case "FINDUSER":
			findUsers(matching: message.trimmingCharacters(in: .whitespacesAndNewlines), in: channel, client: client)
		default:
			break
		}
	}

	private func listUsers(in channel: IRCChannel, client: IRCClient, parameters: String) {
		var members = channel.memberList ?? []
		guard members.isEmpty == false else {
			client.printDebugInformation(localized("5dx-rs", channel.name), in: channel)
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
		client.printDebugInformation(result, in: channel)
	}

	private func findUsers(matching query: String, in channel: IRCChannel, client: IRCClient) {
		let hasQuery = query.isEmpty == false
		let matches = (channel.memberList ?? []).filter { member in
			guard let hostmask = member.user.hostmask else { return false }
			return hasQuery == false || hostmask.localizedCaseInsensitiveContains(query)
		}.sorted { $0.user.nickname.localizedCaseInsensitiveCompare($1.user.nickname) == .orderedAscending }

		guard matches.isEmpty == false else {
			let message = hasQuery
				? localized("n1j-tp", channel.name, query)
				: localized("1ab-27", channel.name)
			client.printDebugInformation(message, in: channel)
			return
		}

		let summary = hasQuery
			? localized("oq7-mg", UInt(matches.count), channel.name, query)
			: localized("nn7-6s", UInt(matches.count), channel.name)
		client.printDebugInformation(summary, in: channel)

		for member in matches {
			client.printDebugInformation("\(member.user.nickname) -> \(member.user.hostmask ?? "")", in: channel)
		}
	}

	private func findClones(in channel: IRCChannel, client: IRCClient) {
		let grouped = Dictionary(grouping: (channel.memberList ?? []).compactMap { member -> (String, String)? in
			guard let address = member.user.address else { return nil }
			return (address, member.user.nickname)
		}, by: \.0)
		let clones = grouped.compactMapValues { entries -> [String]? in
			guard entries.count > 1 else { return nil }
			return entries.map(\.1)
		}

		guard clones.isEmpty == false else {
			client.printDebugInformation(localized("gxq-47"), in: channel)
			return
		}

		client.printDebugInformation(localized("iaa-5v", UInt(clones.count), channel.name), in: channel)
		for (address, nicknames) in clones.sorted(by: { $0.key < $1.key }) {
			client.printDebugInformation("*!*@\(address) -> \(nicknames.joined(separator: ", "))", in: channel)
		}
	}

	private func brag(in channel: IRCChannel, client: IRCClient) {
		var counts = BragCounts()

		for currentClient in NSObject.masterController().world.clientList where currentClient.isConnected {
			counts.networks += 1
			if currentClient.userIsIRCop || currentClient.myself?.isIRCop == true {
				counts.operators += 1
			}

			var trackedUsers = Set<String>()
			for currentChannel in currentClient.channelList where currentChannel.isActive && currentChannel.isChannel {
				counts.channels += 1
				guard let localMember = currentChannel.findMember(currentClient.userNickname) else { continue }
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

				for member in currentChannel.memberList ?? [] where member != localMember {
					if hasPower(over: member, localRanks: localRanks, localClientIsOperator: currentClient.userIsIRCop),
					   trackedUsers.insert(member.user.nickname).inserted
					{
						counts.powerOverUsers += 1
					}
				}
			}
		}

		var result = pluralized("30l-sx", value: counts.channels)
		result += pluralized("rks-0t", value: counts.networks)
		if counts.powerOverUsers == 0 {
			result += localized("jpi-po")
		} else {
			result += pluralized("614-ac", value: counts.operators)
			result += pluralized("qne-b5", value: counts.channelOperators)
			result += pluralized("431-yv", value: counts.channelHalfOperators)
			result += pluralized("x1m-jp", value: counts.channelVoices)
			result += pluralized("ny4-wd", value: counts.powerOverUsers)
		}
		client.sendPrivmsg(result, to: channel)
	}

	private func hasPower(over member: IRCChannelUser, localRanks: IRCUserRank, localClientIsOperator: Bool) -> Bool {
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

	private func pluralized(_ token: String, value: Int) -> String {
		localized("\(token)-\(value == 1 ? 1 : 2)", value)
	}

	private func localized(_ key: String, _ arguments: CVarArg...) -> String {
		let format = bundle.localizedString(forKey: key, value: nil, table: "BasicLanguage")
		return arguments.isEmpty ? format : String(format: format, arguments: arguments)
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

/// Transfers an application-owned Objective-C object to the main actor, matching
/// the plug-in callback contract used by the host application.
private struct MainActorTransfer<Value>: @unchecked Sendable {
	let value: Value
}
